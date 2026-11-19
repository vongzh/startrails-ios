import SwiftUI
import UIKit

enum NodeParticipationFilter: String, CaseIterable {
    case all
    case included
    case excluded
}

enum NodesDisplayMode: String, CaseIterable {
    case map
    case list
}

enum NodeSortMode: String, CaseIterable {
    case defaultOrder
    case latencyAsc

    var shortLabel: String {
        switch self {
        case .defaultOrder: return "默认"
        case .latencyAsc: return "延迟优先"
        }
    }
}

struct NodesMapView: View {
    @Environment(AppStore.self) private var store
    @Binding var showSettings: Bool
    @Binding var showCreateProfile: Bool
    @Binding var showRenameProfile: Bool
    @Binding var showDeleteProfile: Bool
    @Binding var newProfileName: String

    @State private var displayMode: NodesDisplayMode = .map
    @State private var participation: NodeParticipationFilter = .all
    @State private var sortMode: NodeSortMode = .defaultOrder
    @State private var searchText: String = ""
    @State private var selectedRegion: String = ""
    @State private var selectedProtocol: String = ""
    @State private var selectedNode: NodeView?
    @State private var isReorderingNodes = false
    @State private var reorderBuffer: [NodeView] = []
    @State private var isSavingOrder = false

    private var participationNodes: [NodeView] {
        store.nodes.filter { node in
            switch participation {
            case .all: return true
            case .included: return !store.isExcluded(node.nodeKey)
            case .excluded: return store.isExcluded(node.nodeKey)
            }
        }
    }

    private var availableProtocols: [String] {
        let kinds = Set(store.nodes.map(\.kind))
        return kinds.sorted()
    }

    private var regionSummaryRows: [RegionSummaryRow] {
        var bucket = [String: (count: Int, latSum: Int, latN: Int)]()
        for node in participationNodes {
            let region = store.effectiveRegion(for: node)
            var entry = bucket[region] ?? (0, 0, 0)
            entry.count += 1
            if let lat = store.latency(for: node.nodeKey) {
                entry.latSum += lat
                entry.latN += 1
            }
            bucket[region] = entry
        }

        var rows = [RegionSummaryRow]()
        for code in RegionCatalog.order where code != "OTHER" {
            if let entry = bucket[code], entry.count > 0 {
                rows.append(RegionSummaryRow(
                    code: code,
                    meta: RegionCatalog.meta(for: code),
                    count: entry.count,
                    avgLatencyMs: entry.latN > 0 ? Int(round(Double(entry.latSum) / Double(entry.latN))) : nil
                ))
            }
        }
        let extra = bucket
            .filter { !RegionCatalog.order.contains($0.key) }
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count { return lhs.value.count > rhs.value.count }
                return lhs.key < rhs.key
            }
        for (code, entry) in extra where entry.count > 0 {
            rows.append(RegionSummaryRow(
                code: code,
                meta: RegionCatalog.meta(for: code),
                count: entry.count,
                avgLatencyMs: entry.latN > 0 ? Int(round(Double(entry.latSum) / Double(entry.latN))) : nil
            ))
        }
        if let other = bucket["OTHER"], other.count > 0 {
            rows.append(RegionSummaryRow(
                code: "OTHER",
                meta: RegionCatalog.meta(for: "OTHER"),
                count: other.count,
                avgLatencyMs: other.latN > 0 ? Int(round(Double(other.latSum) / Double(other.latN))) : nil
            ))
        }
        return rows
    }

    private var filteredNodes: [NodeView] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched = participationNodes.filter { node in
            if !selectedRegion.isEmpty && store.effectiveRegion(for: node) != selectedRegion {
                return false
            }
            if !selectedProtocol.isEmpty && node.kind != selectedProtocol {
                return false
            }
            if !q.isEmpty {
                let effective = store.effectiveName(for: node).lowercased()
                let origin = node.name.lowercased()
                let addr = node.address.lowercased()
                if !effective.contains(q) && !origin.contains(q) && !addr.contains(q) {
                    return false
                }
            }
            return true
        }
        guard sortMode == .latencyAsc else { return matched }
        return matched.sorted { lhs, rhs in
            let ls = store.latencyStatus(for: lhs.nodeKey)
            let rs = store.latencyStatus(for: rhs.nodeKey)
            if ls.sortRank != rs.sortRank {
                return ls.sortRank < rs.sortRank
            }
            switch (ls, rs) {
            case (.measured(let lm), .measured(let rm)):
                if lm != rm { return lm < rm }
            case (.intercepted(let lm), .intercepted(let rm)):
                let lv = lm ?? Int.max
                let rv = rm ?? Int.max
                if lv != rv { return lv < rv }
            default:
                break
            }
            return store.effectiveName(for: lhs).localizedCaseInsensitiveCompare(store.effectiveName(for: rhs)) == .orderedAscending
        }
    }

    private var probeSummary: (measured: Int, avgMs: Int?, udp: Int, unreachable: Int, intercepted: Int) {
        var measured = 0
        var sum = 0
        var udp = 0
        var unreachable = 0
        var intercepted = 0
        for node in participationNodes {
            switch store.latencyStatus(for: node.nodeKey) {
            case .measured(let ms):
                measured += 1
                sum += ms
            case .udpOnly:
                udp += 1
            case .unreachable:
                unreachable += 1
            case .intercepted:
                intercepted += 1
            case .untested:
                break
            }
        }
        return (measured, measured > 0 ? Int(round(Double(sum) / Double(measured))) : nil, udp, unreachable, intercepted)
    }

    private var includedCount: Int {
        store.nodes.filter { !store.isExcluded($0.nodeKey) }.count
    }

    private var excludedCount: Int {
        store.nodes.count - includedCount
    }

    private var isUnfiltered: Bool {
        participation == .all &&
            sortMode == .defaultOrder &&
            selectedRegion.isEmpty &&
            selectedProtocol.isEmpty &&
            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controlHeader
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemGroupedBackground))

                if store.isProbing || store.hasProbeData {
                    probeStatusStrip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .background(Color(.systemGroupedBackground))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if displayMode == .map {
                    ScrollView {
                        VStack(spacing: 14) {
                            WorldDotMapView(
                                regionRows: regionSummaryRows,
                                selectedRegion: $selectedRegion,
                                isProbing: store.isProbing,
                                hasProbeData: store.hasProbeData,
                                probeEngineLabel: store.probeEngine.label,
                                onRunProbe: store.nodes.isEmpty ? nil : {
                                    Task { await store.runProbe(engine: store.probeEngine) }
                                },
                                onOpenListForRegion: { code in
                                    selectedRegion = code
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        displayMode = .list
                                    }
                                }
                            )

                            regionChipsGrid
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .background(Color(.systemGroupedBackground))
                } else {
                    List {
                        Section {
                            if isReorderingNodes {
                                ForEach(reorderBuffer) { node in
                                    NodeRowView(
                                        node: node,
                                        effectiveName: store.effectiveName(for: node),
                                        regionMeta: RegionCatalog.meta(for: store.effectiveRegion(for: node)),
                                        isExcluded: store.isExcluded(node.nodeKey),
                                        hasAlias: (store.annotationByKey[node.nodeKey]?.alias ?? "").isEmpty == false,
                                        latencyStatus: store.latencyStatus(for: node.nodeKey)
                                    )
                                }
                                .onMove { from, to in
                                    reorderBuffer.move(fromOffsets: from, toOffset: to)
                                }
                            } else if filteredNodes.isEmpty {
                                ContentUnavailableView(
                                    "没有匹配的节点",
                                    systemImage: "network.slash",
                                    description: Text("请调整地区、协议筛选条件或检查订阅构成。")
                                )
                            } else {
                                ForEach(filteredNodes) { node in
                                    NodeRowView(
                                        node: node,
                                        effectiveName: store.effectiveName(for: node),
                                        regionMeta: RegionCatalog.meta(for: store.effectiveRegion(for: node)),
                                        isExcluded: store.isExcluded(node.nodeKey),
                                        hasAlias: (store.annotationByKey[node.nodeKey]?.alias ?? "").isEmpty == false,
                                        latencyStatus: store.latencyStatus(for: node.nodeKey)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedNode = node
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            Task { await store.probeSingleNode(node) }
                                        } label: {
                                            Label("测速", systemImage: "bolt.fill")
                                        }
                                        .tint(.teal)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        let currentlyExcluded = store.isExcluded(node.nodeKey)
                                        Button {
                                            Task {
                                                var ann = store.annotationByKey[node.nodeKey] ?? AnnotationView(nodeKey: node.nodeKey)
                                                ann.excluded = !currentlyExcluded
                                                await store.saveAnnotation(ann)
                                            }
                                        } label: {
                                            Label(currentlyExcluded ? "恢复" : "排除", systemImage: currentlyExcluded ? "eye" : "eye.slash")
                                        }
                                        .tint(currentlyExcluded ? .green : .orange)
                                    }
                                    .contextMenu {
                                        let currentlyExcluded = store.isExcluded(node.nodeKey)
                                        Button {
                                            Task { await store.probeSingleNode(node) }
                                        } label: {
                                            Label("本机 TCP 测速", systemImage: "bolt")
                                        }
                                        Button {
                                            UIPasteboard.general.string = node.address
                                            store.showToast("已复制节点地址")
                                            Haptics.notify(.success)
                                        } label: {
                                            Label("复制服务器地址", systemImage: "doc.on.doc")
                                        }
                                        Button {
                                            Task {
                                                var ann = store.annotationByKey[node.nodeKey] ?? AnnotationView(nodeKey: node.nodeKey)
                                                ann.excluded = !currentlyExcluded
                                                await store.saveAnnotation(ann)
                                            }
                                        } label: {
                                            Label(currentlyExcluded ? "恢复参与构建" : "从当前配置排除", systemImage: currentlyExcluded ? "eye" : "eye.slash")
                                        }
                                        Divider()
                                        Button {
                                            selectedNode = node
                                        } label: {
                                            Label("节点详情与标注", systemImage: "slider.horizontal.3")
                                        }
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text(isReorderingNodes ? "拖拽调整节点顺序" : "节点清单 (\(filteredNodes.count))")
                                Spacer()
                                if isReorderingNodes {
                                    Button("取消") {
                                        isReorderingNodes = false
                                    }
                                    .font(.caption)
                                    .textCase(nil)

                                    Button(isSavingOrder ? "保存中..." : "保存顺序") {
                                        Task {
                                            isSavingOrder = true
                                            await store.saveNodeOrder(reorderBuffer)
                                            isSavingOrder = false
                                            isReorderingNodes = false
                                        }
                                    }
                                    .font(.caption.weight(.semibold))
                                    .textCase(nil)
                                    .disabled(isSavingOrder)
                                } else if isUnfiltered && store.nodes.count > 1 {
                                    Button {
                                        reorderBuffer = store.nodes
                                        isReorderingNodes = true
                                    } label: {
                                        Label("调整顺序", systemImage: "arrow.up.arrow.down")
                                            .font(.caption.weight(.medium))
                                    }
                                    .textCase(nil)
                                }
                            }
                        }
                    }
                    .environment(\.editMode, .constant(isReorderingNodes ? .active : .inactive))
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await store.reloadAll()
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .animation(.snappy(duration: 0.24), value: displayMode)
            .animation(.snappy(duration: 0.22), value: selectedRegion)
            .animation(.snappy(duration: 0.22), value: selectedProtocol)
            .animation(.snappy(duration: 0.22), value: sortMode)
            .animation(.snappy(duration: 0.22), value: store.isProbing)
            .navigationTitle("节点")
            .searchable(text: $searchText, prompt: "搜索节点名、别名或服务器")
            .workspaceToolbar(
                showSettings: $showSettings,
                showCreateProfile: $showCreateProfile,
                showRenameProfile: $showRenameProfile,
                showDeleteProfile: $showDeleteProfile,
                newProfileName: $newProfileName
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("选择测速引擎") {
                            Button {
                                Task { await store.runProbe(engine: .localDirect) }
                            } label: {
                                if store.probeEngine == .localDirect {
                                    Label("本机直连 TCP 测速", systemImage: "checkmark")
                                } else {
                                    Label("本机直连 TCP 测速", systemImage: "iphone")
                                }
                            }
                            Button {
                                Task { await store.runProbe(engine: .server) }
                            } label: {
                                if store.probeEngine == .server {
                                    Label("服务端主控测速", systemImage: "checkmark")
                                } else {
                                    Label("服务端主控测速", systemImage: "server.rack")
                                }
                            }
                        }
                        if store.hasProbeData {
                            Divider()
                            Button(role: .destructive) {
                                withAnimation(.snappy(duration: 0.2)) {
                                    store.clearProbeResults()
                                }
                            } label: {
                                Label("清除测速结果", systemImage: "xmark.circle")
                            }
                        }
                    } label: {
                        if store.isProbing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: store.hasProbeData ? "bolt.fill" : "bolt")
                                .fontWeight(.semibold)
                        }
                    } primaryAction: {
                        Task { await store.runProbe(engine: store.probeEngine) }
                    }
                    .disabled(store.isProbing || store.nodes.isEmpty)
                    .accessibilityLabel("节点测速（长按切换引擎）")
                }
            }
            .sheet(item: $selectedNode) { node in
                NodeDetailSheet(node: node)
            }
        }
    }

    private var controlHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Picker("参与状态", selection: $participation) {
                    Text("全部 \(store.nodes.count)").tag(NodeParticipationFilter.all)
                    Text("参与 \(includedCount)").tag(NodeParticipationFilter.included)
                    Text("排除 \(excludedCount)").tag(NodeParticipationFilter.excluded)
                }
                .pickerStyle(.segmented)

                Picker("视图", selection: $displayMode) {
                    Image(systemName: "globe.asia.australia").tag(NodesDisplayMode.map)
                    Image(systemName: "list.bullet").tag(NodesDisplayMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 96)
            }

            if displayMode == .list {
                HStack(spacing: 8) {
                    if !regionSummaryRows.isEmpty {
                        regionFilterMenu
                    }
                    if !availableProtocols.isEmpty {
                        protocolFilterMenu
                    }
                    sortModeMenu

                    Spacer(minLength: 0)

                    if !selectedRegion.isEmpty || !selectedProtocol.isEmpty || sortMode != .defaultOrder {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                selectedRegion = ""
                                selectedProtocol = ""
                                sortMode = .defaultOrder
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("清除筛选与排序")
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var probeStatusStrip: some View {
        let summary = probeSummary
        return HStack(spacing: 8) {
            if store.isProbing {
                ProgressView()
                    .controlSize(.mini)
                if let progress = store.probeProgress, progress.total > 0 {
                    Text("\(store.probeEngine.label)测速中 \(progress.done)/\(progress.total)")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .contentTransition(.numericText())
                    Spacer()
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                        .frame(width: 68)
                } else {
                    Text("正在执行\(store.probeEngine.label)测速...")
                        .font(.caption.weight(.medium))
                    Spacer()
                }
            } else {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.teal)
                HStack(spacing: 5) {
                    Text(store.probeEngine.label)
                        .font(.caption2.weight(.semibold))
                    if let avg = summary.avgMs {
                        Text("· 均值 \(avg)ms")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Formatters.latencyColor(avg))
                    }
                    if summary.measured > 0 {
                        Text("· \(summary.measured) 可达")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if summary.unreachable > 0 {
                        Text("· \(summary.unreachable) 不可达")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                    if summary.udp > 0 {
                        Text("· \(summary.udp) UDP")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                Menu {
                    Button {
                        Task { await store.runProbe(engine: .localDirect) }
                    } label: {
                        Label("用本机直连重测", systemImage: "iphone")
                    }
                    Button {
                        Task { await store.runProbe(engine: .server) }
                    } label: {
                        Label("用服务端重测", systemImage: "server.rack")
                    }
                    Divider()
                    Button(role: .destructive) {
                        withAnimation(.snappy(duration: 0.2)) {
                            store.clearProbeResults()
                        }
                    } label: {
                        Label("收起并清除", systemImage: "xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5)
        )
    }

    private var sortModeMenu: some View {
        let isLatency = sortMode == .latencyAsc
        return Menu {
            ForEach(NodeSortMode.allCases, id: \.self) { mode in
                Button {
                    sortMode = mode
                } label: {
                    if sortMode == mode {
                        Label(mode.shortLabel, systemImage: "checkmark")
                    } else {
                        Text(mode.shortLabel)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption2)
                Text(sortMode.shortLabel)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isLatency ? Color.accentColor : .primary)
            .background(
                Capsule().fill(isLatency ? Color.accentColor.opacity(0.14) : Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private var regionFilterMenu: some View {
        let activeRow = regionSummaryRows.first(where: { $0.code == selectedRegion })
        return Menu {
            Button {
                selectedRegion = ""
            } label: {
                if selectedRegion.isEmpty {
                    Label("全部地区 (\(participationNodes.count))", systemImage: "checkmark")
                } else {
                    Text("全部地区 (\(participationNodes.count))")
                }
            }
            Divider()
            ForEach(regionSummaryRows) { row in
                Button {
                    Haptics.impact(.light)
                    selectedRegion = row.code
                } label: {
                    let lat = row.avgLatencyMs.map { " · \($0)ms" } ?? ""
                    let label = "\(RegionCatalog.displayLabel(for: row.code)) (\(row.count))\(lat)"
                    if selectedRegion == row.code {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let activeRow {
                    Text(RegionCatalog.displayLabel(for: activeRow.code))
                } else {
                    Image(systemName: "globe")
                        .font(.caption2)
                    Text("地区")
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(activeRow != nil ? Color.accentColor : .primary)
            .background(
                Capsule().fill(activeRow != nil ? Color.accentColor.opacity(0.14) : Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private var protocolFilterMenu: some View {
        let isActive = !selectedProtocol.isEmpty
        return Menu {
            Button {
                selectedProtocol = ""
            } label: {
                if selectedProtocol.isEmpty {
                    Label("全部协议", systemImage: "checkmark")
                } else {
                    Text("全部协议")
                }
            }
            Divider()
            ForEach(availableProtocols, id: \.self) { proto in
                Button {
                    selectedProtocol = proto
                } label: {
                    if selectedProtocol == proto {
                        Label(proto.uppercased(), systemImage: "checkmark")
                    } else {
                        Text(proto.uppercased())
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if isActive {
                    Text(selectedProtocol.uppercased())
                } else {
                    Image(systemName: "bolt.horizontal")
                        .font(.caption2)
                    Text("协议")
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isActive ? Color.accentColor : .primary)
            .background(
                Capsule().fill(isActive ? Color.accentColor.opacity(0.14) : Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private var regionChipsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
            ForEach(regionSummaryRows) { row in
                let isSelected = selectedRegion == row.code
                Button {
                    Haptics.impact(.light)
                    withAnimation(.snappy(duration: 0.22)) {
                        selectedRegion = isSelected ? "" : row.code
                    }
                } label: {
                    HStack(spacing: 6) {
                        RegionFlagBadge(code: row.code, font: .subheadline, monogramWidth: 22, monogramHeight: 16)
                        Text(row.meta.shortName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if let avg = row.avgLatencyMs {
                            Text("\(avg)ms")
                                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(Formatters.latencyColor(avg))
                        } else {
                            Text("\(row.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color(.separator).opacity(0.25), lineWidth: isSelected ? 1.2 : 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct NodeRowView: View {
    let node: NodeView
    let effectiveName: String
    let regionMeta: RegionMeta
    let isExcluded: Bool
    let hasAlias: Bool
    let latencyStatus: NodeLatencyStatus

    var body: some View {
        HStack(spacing: 12) {
            RegionFlagBadge(code: regionMeta.code, font: .title3, monogramWidth: 26, monogramHeight: 20)
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                .opacity(isExcluded ? 0.45 : 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(effectiveName)
                        .font(.subheadline.weight(.medium))
                        .strikethrough(isExcluded)
                        .foregroundStyle(isExcluded ? .secondary : .primary)
                        .lineLimit(1)

                    if hasAlias {
                        BadgePill(text: "别名", tint: .indigo)
                    }
                    if isExcluded {
                        BadgePill(text: "已排除", tint: .orange)
                    }
                    if node.geo?.conflict == true {
                        BadgePill(text: "多IP地区冲突", tint: .red)
                    }
                }

                HStack(spacing: 6) {
                    BadgePill(text: node.kind.uppercased(), tint: RegionCatalog.protocolTint(node.kind))
                    Text(node.address)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let org = node.geo?.org, !org.isEmpty {
                    Text("AS\(node.geo?.asn.map(String.init) ?? "-") · \(org)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            latencyBadge
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var latencyBadge: some View {
        switch latencyStatus {
        case .measured(let ms):
            let color = Formatters.latencyColor(ms)
            Text("\(ms) ms")
                .font(.caption.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12), in: Capsule())
        case .intercepted(let ms):
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                Text(ms.map { "\($0)ms 本机" } ?? "被劫持")
                    .font(.caption2.weight(.semibold).monospacedDigit())
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.12), in: Capsule())
        case .udpOnly:
            Text("UDP")
                .font(.caption2.weight(.semibold).monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill), in: Capsule())
        case .unreachable:
            Text("不可达")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.red.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.10), in: Capsule())
        case .untested:
            RowChevron()
        }
    }
}
