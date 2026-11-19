import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct OverviewSourcesView: View {
    @Environment(AppStore.self) private var store
    @Binding var selectedTab: MainTab
    @Binding var showSettings: Bool
    @Binding var showCreateProfile: Bool
    @Binding var showRenameProfile: Bool
    @Binding var showDeleteProfile: Bool
    @Binding var newProfileName: String

    @State private var showAddRemote = false
    @State private var showAddInline = false
    @State private var showFileImporter = false
    @State private var showAddFileSheet = false
    @State private var showScanner = false
    @State private var editingSource: SourceView?
    @State private var showNewCollection = false
    @State private var editingCollection: CollectionView?
    @State private var showDiagnosticsSheet = false
    @State private var showBuildHistory = false

    @State private var prefillURL: String = ""
    @State private var prefillInlineContent: String = ""
    @State private var prefillFileContent: String = ""
    @State private var prefillFileName: String = ""

    private var remoteSources: [SourceView] {
        (store.workspaceState?.sources ?? []).filter { $0.kind == .remote }
    }

    private var localSources: [SourceView] {
        (store.workspaceState?.sources ?? []).filter { $0.kind != .remote }
    }

    private var activeTokensCount: Int {
        (store.workspaceState?.tokens ?? []).filter { !$0.revoked && $0.profile == store.activeProfile }.count
    }

    private var excludedCount: Int {
        store.nodes.filter { store.isExcluded($0.nodeKey) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                if let candidate = store.clipboardCandidate {
                    Section {
                        clipboardBanner(candidate)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Section {
                    summaryGrid
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if (store.workspaceState?.sources.isEmpty ?? true) || store.nodes.isEmpty {
                    Section {
                        onboardingGuideCard
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if !store.nodeDiagnostics.isEmpty
                    || remoteSources.contains(where: { $0.lastError != nil || $0.snapshotStale })
                    || store.sourceStatsById.values.contains(where: { $0.skipped > 0 }) {
                    Section {
                        attentionBanner
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if !store.recentBuilds.isEmpty {
                    Section {
                        ForEach(store.recentBuilds.prefix(3)) { entry in
                            Button {
                                showBuildHistory = true
                            } label: {
                                HStack(spacing: 10) {
                                    ClientBrandIcon(targetId: entry.target, size: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(targetDisplayName(entry.target))
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text("\(entry.passed) 通过 · \(entry.skipped) 跳过")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(Formatters.isoShort(entry.createdAt))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    RowChevron()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text("最近构建")
                            Spacer()
                            Button("全部回执") {
                                showBuildHistory = true
                            }
                            .font(.caption.weight(.medium))
                            .textCase(nil)
                        }
                    }
                }

                Section {
                    if remoteSources.isEmpty {
                        emptyActionRow(
                            icon: "icloud.and.arrow.down",
                            tint: .blue,
                            title: "暂无机场订阅",
                            subtitle: "点此添加远程订阅链接或扫码导入"
                        ) {
                            showAddRemote = true
                        }
                    } else {
                        ForEach(remoteSources) { source in
                            RemoteSourceRow(
                                source: source,
                                stat: store.sourceStatsById[source.id],
                                isRefreshing: store.refreshingSourceIds.contains(source.id),
                                onRefresh: { Task { await store.refreshSingleSource(source.id) } },
                                onEdit: { editingSource = source }
                            )
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    Task { await store.refreshSingleSource(source.id) }
                                } label: {
                                    Label("刷新", systemImage: "arrow.clockwise")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await deleteSource(source) }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    Task { await toggleSource(source) }
                                } label: {
                                    Label(source.enabled ? "停用" : "启用", systemImage: source.enabled ? "pause.circle" : "play.circle")
                                }
                                .tint(.orange)
                            }
                            .contextMenu {
                                Button {
                                    Task { await store.refreshSingleSource(source.id) }
                                } label: {
                                    Label("立即拉取刷新", systemImage: "arrow.clockwise")
                                }
                                Button {
                                    editingSource = source
                                } label: {
                                    Label("编辑与预览节点", systemImage: "slider.horizontal.3")
                                }
                                if let url = source.url {
                                    Button {
                                        UIPasteboard.general.string = url
                                        store.showToast("已复制订阅链接")
                                        Haptics.notify(.success)
                                    } label: {
                                        Label("复制源链接", systemImage: "doc.on.doc")
                                    }
                                }
                                Button {
                                    Task { await toggleSource(source) }
                                } label: {
                                    Label(source.enabled ? "停用该订阅" : "启用该订阅", systemImage: source.enabled ? "pause.circle" : "play.circle")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    Task { await deleteSource(source) }
                                } label: {
                                    Label("删除订阅", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("机场订阅 (\(remoteSources.count))")
                        Spacer()
                        if !remoteSources.isEmpty {
                            Button("全部更新") {
                                Task { await store.refreshAllRemoteSources() }
                            }
                            .font(.caption.weight(.medium))
                            .textCase(nil)
                        }
                    }
                }

                Section("我的节点与文件 (\(localSources.count))") {
                    if localSources.isEmpty {
                        emptyActionRow(
                            icon: "text.alignleft",
                            tint: .teal,
                            title: "暂无自建或粘贴节点",
                            subtitle: "点此批量粘贴 vless / vmess / trojan / ss / hy2 链接"
                        ) {
                            showAddInline = true
                        }
                    } else {
                        ForEach(localSources) { source in
                            Button {
                                editingSource = source
                            } label: {
                                HStack(spacing: 12) {
                                    SettingsRowIcon(
                                        systemName: source.kind == .inline ? "text.alignleft" : "doc.text",
                                        tint: .blue
                                    )
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(source.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            if !source.enabled {
                                                BadgePill(text: "已停用", tint: .secondary)
                                            }
                                        }
                                        let stat = store.sourceStatsById[source.id]
                                        let nodeCountText = stat.map { "\($0.nodes) 节点 · " } ?? ""
                                        Text("\(nodeCountText)\(source.kind.label) · \(Formatters.bytes(Double(source.bytes))) · \(source.format ?? "自动识别")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    RowChevron()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await deleteSource(source) }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    Task { await toggleSource(source) }
                                } label: {
                                    Label(source.enabled ? "停用" : "启用", systemImage: source.enabled ? "pause.circle" : "play.circle")
                                }
                                .tint(.orange)
                            }
                            .contextMenu {
                                Button {
                                    editingSource = source
                                } label: {
                                    Label("编辑与预览", systemImage: "slider.horizontal.3")
                                }
                                Button {
                                    Task { await toggleSource(source) }
                                } label: {
                                    Label(source.enabled ? "停用该来源" : "启用该来源", systemImage: source.enabled ? "pause.circle" : "play.circle")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    Task { await deleteSource(source) }
                                } label: {
                                    Label("删除来源", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section {
                    if store.collections.isEmpty {
                        emptyActionRow(
                            icon: "square.stack.3d.down.right",
                            tint: .indigo,
                            title: "暂无组合订阅",
                            subtitle: "点此将多个订阅源按过滤、改名与排序链合成一份来源"
                        ) {
                            showNewCollection = true
                        }
                    } else {
                        ForEach(store.collections) { collection in
                            Button {
                                editingCollection = collection
                            } label: {
                                HStack(spacing: 12) {
                                    SettingsRowIcon(systemName: "square.stack.3d.down.right", tint: .indigo)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(collection.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text("\(collection.members.count) 个成员 · \(collection.dedupe.label) · 约 \(collection.previewCount ?? 0) 节点")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    RowChevron()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await deleteCollection(collection) }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    editingCollection = collection
                                } label: {
                                    Label("编辑组合规则", systemImage: "slider.horizontal.3")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    Task { await deleteCollection(collection) }
                                } label: {
                                    Label("删除组合", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("组合订阅 (\(store.collections.count))")
                        Spacer()
                        Button("新建组合") {
                            showNewCollection = true
                        }
                        .font(.caption.weight(.medium))
                        .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .animation(.snappy(duration: 0.22), value: store.clipboardCandidate != nil)
            .refreshable {
                await store.reloadAll()
            }
            .navigationTitle("订阅概览")
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
                        Button {
                            prefillURL = ""
                            showAddRemote = true
                        } label: {
                            Label("添加机场订阅 (URL)", systemImage: "link.badge.plus")
                        }
                        Button {
                            prefillInlineContent = ""
                            showAddInline = true
                        } label: {
                            Label("批量粘贴节点链接", systemImage: "doc.on.clipboard")
                        }
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("从「文件」导入配置", systemImage: "folder.badge.plus")
                        }
                        Button {
                            showScanner = true
                        } label: {
                            Label("扫码导入订阅 / 节点", systemImage: "qrcode.viewfinder")
                        }
                        Divider()
                        Button {
                            showNewCollection = true
                        } label: {
                            Label("新建组合订阅", systemImage: "square.stack.3d.up")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("添加订阅或节点")
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [
                    .plainText,
                    .json,
                    UTType(filenameExtension: "yaml") ?? .plainText,
                    UTType(filenameExtension: "yml") ?? .plainText,
                    UTType(filenameExtension: "conf") ?? .plainText,
                    .data,
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let fileURL = urls.first else { return }
                    let scoped = fileURL.startAccessingSecurityScopedResource()
                    defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: fileURL),
                       let text = String(data: data, encoding: .utf8) {
                        prefillFileContent = text
                        prefillFileName = fileURL.deletingPathExtension().lastPathComponent
                        showAddFileSheet = true
                    } else {
                        store.showToast("无法按 UTF-8 文本读取所选文件", isError: true)
                    }
                case .failure(let error):
                    store.showToast(error.localizedDescription, isError: true)
                }
            }
            .sheet(isPresented: $showAddRemote) {
                SourceEditorSheet(mode: .create(kind: .remote, prefill: prefillURL))
            }
            .sheet(isPresented: $showAddInline) {
                SourceEditorSheet(mode: .create(kind: .inline, prefill: prefillInlineContent))
            }
            .sheet(isPresented: $showAddFileSheet) {
                SourceEditorSheet(mode: .create(kind: .file, prefill: prefillFileContent, suggestedName: prefillFileName))
            }
            .sheet(item: $editingSource) { source in
                SourceEditorSheet(mode: .edit(source))
            }
            .sheet(isPresented: $showNewCollection) {
                CollectionEditorSheet(existing: nil)
            }
            .sheet(item: $editingCollection) { collection in
                CollectionEditorSheet(existing: collection)
            }
            .sheet(isPresented: $showScanner) {
                QRScannerSheet(
                    title: "扫码导入订阅",
                    hint: "扫描机场订阅二维码或单节点分享链接",
                    onScanned: handleScannedString
                )
            }
            .sheet(isPresented: $showDiagnosticsSheet) {
                DiagnosticsModalView(
                    diagnostics: store.nodeDiagnostics,
                    sources: remoteSources,
                    allSources: store.workspaceState?.sources ?? [],
                    sourceStats: store.sourceStatsById
                )
            }
            .sheet(isPresented: $showBuildHistory) {
                BuildHistorySheet()
            }
        }
    }

    private func clipboardBanner(_ candidate: ClipboardCandidate) -> some View {
        HStack(spacing: 12) {
            SettingsRowIcon(systemName: "doc.on.clipboard.fill", tint: .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title)
                    .font(.subheadline.weight(.semibold))
                Text(candidate.subtitle)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("忽略") {
                store.dismissClipboard()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("导入") {
                Haptics.impact(.light)
                switch candidate {
                case .remoteSubscription(let url, _):
                    prefillURL = url
                    store.dismissClipboard()
                    showAddRemote = true
                case .inlineProxies(let content, _, _):
                    prefillInlineContent = content
                    store.dismissClipboard()
                    showAddInline = true
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .surfaceCard(cornerRadius: 14, padding: 12)
    }

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ],
            spacing: 10
        ) {
            SummaryTile(
                title: "订阅源",
                value: "\(store.workspaceState?.sources.count ?? 0)",
                subtitle: "\(store.collections.count) 组合 · 点此添加",
                tint: .blue,
                icon: "tray.full.fill"
            ) {
                prefillURL = ""
                showAddRemote = true
            }
            SummaryTile(
                title: "节点池",
                value: "\(store.nodes.count)",
                subtitle: excludedCount > 0 ? "已排除 \(excludedCount)" : "点击查看地图与测速",
                tint: .teal,
                icon: "network"
            ) {
                Haptics.impact(.light)
                selectedTab = .nodes
            }
            SummaryTile(
                title: "生效地址",
                value: "\(activeTokensCount)",
                subtitle: "配置: \(store.activeProfile)",
                tint: .indigo,
                icon: "link"
            ) {
                Haptics.impact(.light)
                selectedTab = .exportPublish
            }
            SummaryTile(
                title: "服务端版本",
                value: store.healthInfo.map { "v\($0.version)" } ?? "在线",
                subtitle: store.activeServer?.hostLabel ?? "",
                tint: .green,
                icon: "checkmark.shield.fill"
            ) {
                Haptics.impact(.light)
                showSettings = true
            }
        }
    }

    private var onboardingGuideCard: some View {
        let hasSources = !(store.workspaceState?.sources.isEmpty ?? true)
        let hasNodes = !store.nodes.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("快速上手引导")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("支持 \(store.workspaceState?.clientTargets.count ?? 19) 种客户端")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            onboardingStepRow(
                step: 1,
                done: hasSources,
                title: "添加机场订阅或手工节点",
                actionTitle: "去添加"
            ) {
                prefillURL = ""
                showAddRemote = true
            }

            onboardingStepRow(
                step: 2,
                done: hasNodes,
                title: "确认当前配置的节点构成",
                actionTitle: hasSources ? "去配置" : nil
            ) {
                Haptics.impact(.light)
                selectedTab = .orchestration
            }

            onboardingStepRow(
                step: 3,
                done: activeTokensCount > 0,
                title: "签发订阅并一键导入客户端",
                actionTitle: hasNodes ? "去发布" : nil
            ) {
                Haptics.impact(.light)
                selectedTab = .exportPublish
            }
        }
        .surfaceCard(cornerRadius: 14, padding: 14)
    }

    private func onboardingStepRow(
        step: Int,
        done: Bool,
        title: String,
        actionTitle: String?,
        onAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(done ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
                    .frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                } else {
                    Text("\(step)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(done ? .secondary : .primary)
                .strikethrough(done)
            Spacer()
            if !done, let actionTitle {
                Button(actionTitle, action: onAction)
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
            }
        }
    }

    private func targetDisplayName(_ id: String) -> String {
        if id == "auto" { return "自动识别" }
        return store.workspaceState?.clientTargets.first(where: { $0.id == id })?.name ?? id
    }

    private var attentionBanner: some View {
        Button {
            showDiagnosticsSheet = true
        } label: {
            HStack(spacing: 12) {
                SettingsRowIcon(systemName: "exclamationmark.triangle.fill", tint: .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("需要注意")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(store.nodeDiagnostics.count) 条构建诊断 · 点击查看详情")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                RowChevron()
            }
            .surfaceCard(cornerRadius: 14, padding: 12)
        }
        .buttonStyle(.plain)
    }

    private func emptyActionRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            HStack(spacing: 12) {
                SettingsRowIcon(systemName: icon, tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                RowChevron()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleScannedString(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            prefillURL = trimmed
            showAddRemote = true
        } else {
            prefillInlineContent = trimmed
            showAddInline = true
        }
    }

    private func toggleSource(_ source: SourceView) async {
        do {
            let payload = SourceInputPayload(kind: source.kind, enabled: !source.enabled)
            _ = try await store.client.updateSource(id: source.id, payload: payload)
            await store.reloadAll()
        } catch {
            store.handleError(error)
        }
    }

    private func deleteSource(_ source: SourceView) async {
        do {
            _ = try await store.client.removeSource(id: source.id)
            await store.reloadAll()
            store.showToast("已删除 \(source.name)")
        } catch {
            store.handleError(error)
        }
    }

    private func deleteCollection(_ collection: CollectionView) async {
        do {
            _ = try await store.client.removeCollection(id: collection.id)
            await store.reloadAll()
            store.showToast("已删除组合 \(collection.name)")
        } catch {
            store.handleError(error)
        }
    }
}

private struct SummaryTile: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color
    let icon: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 24, height: 24)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                Text(value)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .truncationMode(.middle)
                    .frame(height: 26, alignment: .leading)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, minHeight: 78, maxHeight: .infinity, alignment: .topLeading)
            .surfaceCard(cornerRadius: 14, padding: 12)
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

private struct RemoteSourceRow: View {
    let source: SourceView
    let stat: SourceStatView?
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(source.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !source.enabled {
                        BadgePill(text: "已停用", tint: .secondary)
                    } else if source.snapshotStale {
                        BadgePill(text: "缓存陈旧", tint: .orange)
                    }

                    Spacer()

                    Button(action: onRefresh) {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isRefreshing)
                }

                if let info = source.userinfo, let total = info.total, total > 0 {
                    let used = max(0, (info.upload ?? 0) + (info.download ?? 0))
                    let ratio = min(1, max(0, used / total))
                    let remaining = max(0, total - used)

                    VStack(alignment: .leading, spacing: 5) {
                        GradientQuotaBar(ratio: ratio)
                        HStack {
                            Text("已用 \(Formatters.bytes(used)) / \(Formatters.bytes(total))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("余 \(Formatters.bytes(remaining))")
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .foregroundStyle(ratio > 0.9 ? .red : .secondary)
                        }
                    }
                }

                HStack(spacing: 8) {
                    if let stat {
                        BadgePill(text: "\(stat.nodes) 节点", tint: .blue)
                        if stat.skipped > 0 {
                            BadgePill(text: "跳过 \(stat.skipped)", tint: .orange)
                        }
                    }
                    if let badge = Formatters.expiryBadge(expireTimestamp: source.userinfo?.expire) {
                        BadgePill(text: badge.text, tint: badge.tint)
                    }
                    if source.snapshotAgeMs != nil {
                        Text("同步于 \(Formatters.age(ms: source.snapshotAgeMs)) 前")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(stat?.format ?? source.format ?? "auto")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }

                if let error = source.lastError, !error.isEmpty {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        if !source.enabled { return .secondary }
        if source.lastError != nil { return .red }
        if source.snapshotStale { return .orange }
        return .green
    }
}

private struct DiagnosticsModalView: View {
    @Environment(\.dismiss) private var dismiss
    let diagnostics: [DiagnosticView]
    let sources: [SourceView]
    let allSources: [SourceView]
    let sourceStats: [String: SourceStatView]

    var body: some View {
        NavigationStack {
            List {
                let errorSources = sources.filter { $0.lastError != nil }
                if !errorSources.isEmpty {
                    Section("订阅拉取异常") {
                        ForEach(errorSources) { source in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(source.lastError ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                let skippedStats = allSources.compactMap { src -> (SourceView, SourceStatView)? in
                    guard let stat = sourceStats[src.id], stat.skipped > 0 || !stat.diagnostics.isEmpty else { return nil }
                    return (src, stat)
                }
                if !skippedStats.isEmpty {
                    Section("来源解析告警 (\(skippedStats.count))") {
                        ForEach(skippedStats, id: \.0.id) { source, stat in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(source.name)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    BadgePill(text: "\(stat.nodes) 通过 / \(stat.skipped) 跳过", tint: .orange)
                                }
                                ForEach(stat.diagnostics) { diag in
                                    Text("\(diag.subject)：\(diag.reason)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("构建与解析诊断 (\(diagnostics.count))") {
                    if diagnostics.isEmpty {
                        Text("当前无构建告警")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(diagnostics) { diag in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    BadgePill(text: diag.stage, tint: .orange)
                                    if let target = diag.target {
                                        BadgePill(text: target, tint: .blue)
                                    }
                                    Spacer()
                                }
                                Text(diag.subject)
                                    .font(.subheadline.weight(.medium))
                                Text(diag.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("需要注意")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
