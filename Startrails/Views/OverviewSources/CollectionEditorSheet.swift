import SwiftUI

struct CollectionEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existing: CollectionView?

    @State private var name: String = ""
    @State private var dedupe: DedupeMode = .nodeKey
    @State private var members: [CollectionMemberView] = []
    @State private var isSaving: Bool = false
    @State private var editingMemberIndex: Int?

    private var availableSources: [SourceView] {
        let selectedIds = Set(members.map(\.sourceId))
        return (store.workspaceState?.sources ?? []).filter { !selectedIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本设置") {
                    TextField("组合订阅名称", text: $name)
                    Picker("节点去重策略", selection: $dedupe) {
                        ForEach(DedupeMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                }

                Section {
                    if members.isEmpty {
                        Text("从下方选择至少一个订阅源加入组合")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(members.enumerated()), id: \.element.sourceId) { index, member in
                            Button {
                                editingMemberIndex = index
                            } label: {
                                HStack(spacing: 12) {
                                    SettingsRowIcon(
                                        systemName: "line.3.horizontal.decrease.circle",
                                        tint: member.filter?.enabled == false ? .secondary : .indigo
                                    )
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(sourceName(for: member.sourceId))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(filterSummary(member.filter))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    RowChevron()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            members.remove(atOffsets: offsets)
                        }
                        .onMove { from, to in
                            members.move(fromOffsets: from, toOffset: to)
                        }
                    }
                } header: {
                    HStack {
                        Text("成员管线 (\(members.count))")
                        Spacer()
                        EditButton()
                            .font(.caption)
                            .textCase(nil)
                    }
                }

                if !availableSources.isEmpty {
                    Section("添加订阅源到组合") {
                        ForEach(availableSources) { source in
                            Button {
                                members.append(CollectionMemberView(sourceId: source.id, filter: nil))
                                Haptics.impact(.light)
                            } label: {
                                HStack(spacing: 10) {
                                    SettingsRowIcon(systemName: "plus", tint: .green)
                                    Text(source.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(source.kind.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "新建组合订阅" : "编辑组合订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中..." : "保存") {
                        Task { await save() }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    dedupe = existing.dedupe
                    members = existing.members
                }
            }
            .sheet(item: Binding(
                get: { editingMemberIndex.map { MemberEditSelection(index: $0) } },
                set: { editingMemberIndex = $0?.index }
            )) { sel in
                MemberFilterEditorSheet(
                    sourceName: sourceName(for: members[sel.index].sourceId),
                    filter: members[sel.index].filter ?? MemberFilterView()
                ) { updated in
                    members[sel.index].filter = updated
                }
            }
        }
    }

    private func sourceName(for id: String) -> String {
        store.workspaceState?.sources.first(where: { $0.id == id })?.name ?? id
    }

    private func filterSummary(_ filter: MemberFilterView?) -> String {
        guard let filter else { return "原样直通，未配置过滤算子" }
        var parts = [String]()
        if filter.enabled == false { parts.append("已暂停") }
        if let steps = filter.process, !steps.isEmpty {
            parts.append("\(steps.count) 个管线步骤")
        } else {
            if let prefix = filter.prefix, !prefix.isEmpty { parts.append("前缀 \(prefix)") }
            if let inc = filter.include, !inc.isEmpty { parts.append("保留 \(inc.count) 项") }
            if let exc = filter.exclude, !exc.isEmpty { parts.append("排除 \(exc.count) 项") }
            if let limit = filter.limit { parts.append("限 \(limit) 节点") }
        }
        return parts.isEmpty ? "原样直通，点击配置清洗算子" : parts.joined(separator: " · ")
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await store.client.saveCollection(
                id: existing?.id,
                name: trimmed,
                members: members,
                dedupe: dedupe
            )
            await store.reloadAll()
            store.showToast("已保存组合 \(trimmed)")
            Haptics.notify(.success)
            dismiss()
        } catch {
            store.handleError(error)
        }
    }
}

private struct MemberEditSelection: Identifiable {
    let index: Int
    var id: Int { index }
}

private struct MemberFilterEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sourceName: String
    @State var filter: MemberFilterView
    let onApply: (MemberFilterView?) -> Void

    @State private var prefixText = ""
    @State private var renameText = ""
    @State private var includeText = ""
    @State private var excludeText = ""
    @State private var limitText = ""
    @State private var isEnabled = true
    @State private var showAddStep = false

    var body: some View {
        NavigationStack {
            Form {
                Section(sourceName) {
                    Toggle("启用该来源成员", isOn: $isEnabled)
                }

                if let steps = filter.process, !steps.isEmpty {
                    Section("当前加工链（Process 算子）") {
                        ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                            HStack(spacing: 10) {
                                BadgePill(text: "#\(idx + 1)", tint: .indigo)
                                Text(step.summaryText)
                                    .font(.footnote.monospaced())
                                    .lineLimit(2)
                            }
                        }
                        .onDelete { offsets in
                            filter.process?.remove(atOffsets: offsets)
                        }
                        .onMove { from, to in
                            filter.process?.move(fromOffsets: from, toOffset: to)
                        }

                        Button {
                            showAddStep = true
                        } label: {
                            HStack(spacing: 12) {
                                SettingsRowIcon(systemName: "plus", tint: .teal)
                                Text("追加算子步骤（支持全 8 类算子）")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Section("快速过滤与改名") {
                        TextField("节点名前缀（如 [主力] ）", text: $prefixText)
                        TextField("改名模板（支持 {name} {index} {source}）", text: $renameText)
                        TextField("仅保留正则（逗号分隔）", text: $includeText)
                            .textInputAutocapitalization(.never)
                        TextField("排除正则（逗号分隔）", text: $excludeText)
                            .textInputAutocapitalization(.never)
                        TextField("数量上限（整数，留空不限）", text: $limitText)
                            .keyboardType(.numberPad)
                    }

                    Section {
                        Button {
                            var nextSteps = [ProcessStep]()
                            if !includeText.trimmingCharacters(in: .whitespaces).isEmpty {
                                let vals = includeText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                                nextSteps.append(.filter(by: "regex", keep: true, value: vals))
                            }
                            if !excludeText.trimmingCharacters(in: .whitespaces).isEmpty {
                                let vals = excludeText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                                nextSteps.append(.filter(by: "regex", keep: false, value: vals))
                            }
                            if !prefixText.trimmingCharacters(in: .whitespaces).isEmpty {
                                nextSteps.append(.prefix(value: prefixText.trimmingCharacters(in: .whitespaces)))
                            }
                            if !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                                nextSteps.append(.rename(template: renameText.trimmingCharacters(in: .whitespaces)))
                            }
                            if let lim = Int(limitText), lim > 0 {
                                nextSteps.append(.limit(count: lim))
                            }
                            if nextSteps.isEmpty {
                                nextSteps.append(.filter(by: "useless", keep: false, value: nil))
                            }
                            filter.process = nextSteps
                        } label: {
                            HStack(spacing: 12) {
                                SettingsRowIcon(systemName: "slider.horizontal.2.square.on.square", tint: .indigo)
                                Text("转换为可排序加工链 (Process Pipeline)")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("成员过滤与算子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        applyAndClose()
                    }
                }
            }
            .onAppear {
                isEnabled = filter.enabled ?? true
                prefixText = filter.prefix ?? ""
                renameText = filter.rename ?? ""
                includeText = (filter.include ?? []).joined(separator: ", ")
                excludeText = (filter.exclude ?? []).joined(separator: ", ")
                limitText = filter.limit.map(String.init) ?? ""
            }
            .sheet(isPresented: $showAddStep) {
                AddProcessStepSheet { step in
                    var current = filter.process ?? []
                    current.append(step)
                    filter.process = current
                }
            }
        }
    }

    private func applyAndClose() {
        var result = filter
        result.enabled = isEnabled ? nil : false

        if result.process == nil || result.process?.isEmpty == true {
            result.process = nil
            result.prefix = prefixText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : prefixText.trimmingCharacters(in: .whitespaces)
            result.rename = renameText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : renameText.trimmingCharacters(in: .whitespaces)
            let inc = includeText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            result.include = inc.isEmpty ? nil : inc
            let exc = excludeText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            result.exclude = exc.isEmpty ? nil : exc
            result.limit = Int(limitText).flatMap { $0 > 0 ? $0 : nil }
        }
        onApply(result)
        dismiss()
    }
}

private struct AddProcessStepSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (ProcessStep) -> Void

    @State private var opType: String = "filter"
    @State private var filterBy: String = "useless"
    @State private var filterKeep: Bool = false
    @State private var filterValues: String = ""
    @State private var templateText: String = "{prefix}{name}"
    @State private var prefixText: String = "[主力] "
    @State private var sortBy: String = "region"
    @State private var sortOrder: String = "asc"
    @State private var dedupeStrategy: String = "nodeKey"
    @State private var limitCount: String = "30"
    @State private var propKey: String = "udp"
    @State private var propBool: Bool = true
    @State private var propAlpn: String = "h2,http/1.1"
    @State private var flagMode: String = "emoji"

    var body: some View {
        NavigationStack {
            Form {
                Section("算子类型") {
                    Picker("算子", selection: $opType) {
                        Text("过滤 filter").tag("filter")
                        Text("重命名 rename").tag("rename")
                        Text("加前缀 prefix").tag("prefix")
                        Text("排序 sort").tag("sort")
                        Text("去重 dedupe").tag("dedupe")
                        Text("数量截断 limit").tag("limit")
                        Text("设属性 set-property").tag("set-property")
                        Text("旗帜 flag").tag("flag")
                    }
                }

                Section("算子参数") {
                    switch opType {
                    case "filter":
                        Picker("过滤维度", selection: $filterBy) {
                            Text("无用信息节点 (useless)").tag("useless")
                            Text("正则匹配 (regex)").tag("regex")
                            Text("地区代码 (region)").tag("region")
                            Text("协议类型 (type)").tag("type")
                        }
                        Toggle("保留命中项 (keep)", isOn: $filterKeep)
                        if filterBy != "useless" {
                            TextField("逗号分隔值（如 HK,JP 或 /倍率/i）", text: $filterValues)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    case "rename":
                        TextField("模板（{name} {index} {source} {prefix}）", text: $templateText)
                    case "prefix":
                        TextField("前缀字符串", text: $prefixText)
                    case "sort":
                        Picker("排序字段", selection: $sortBy) {
                            Text("名称 name").tag("name")
                            Text("地区 region").tag("region")
                            Text("协议 kind").tag("kind")
                        }
                        Picker("方向", selection: $sortOrder) {
                            Text("升序 asc").tag("asc")
                            Text("降序 desc").tag("desc")
                        }
                    case "dedupe":
                        Picker("去重策略", selection: $dedupeStrategy) {
                            Text("nodeKey（指纹）").tag("nodeKey")
                            Text("name（名称）").tag("name")
                            Text("none（不去重）").tag("none")
                        }
                    case "limit":
                        TextField("保留最大节点数", text: $limitCount)
                            .keyboardType(.numberPad)
                    case "set-property":
                        Picker("属性键", selection: $propKey) {
                            Text("udp").tag("udp")
                            Text("skip-cert-verify").tag("skip-cert-verify")
                            Text("alpn").tag("alpn")
                        }
                        if propKey == "alpn" {
                            TextField("ALPN（留空表示清空）", text: $propAlpn)
                                .textInputAutocapitalization(.never)
                        } else {
                            Toggle("启用 (\(propKey))", isOn: $propBool)
                        }
                    default:
                        Picker("旗帜模式", selection: $flagMode) {
                            Text("添加国旗 Emoji").tag("emoji")
                            Text("移除国旗").tag("remove")
                        }
                    }
                }
            }
            .navigationTitle("追加管线算子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        appendAndClose()
                    }
                }
            }
        }
    }

    private func appendAndClose() {
        switch opType {
        case "filter":
            let vals = filterValues.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            onAdd(.filter(by: filterBy, keep: filterKeep, value: vals.isEmpty ? nil : vals))
        case "rename":
            onAdd(.rename(template: templateText))
        case "prefix":
            onAdd(.prefix(value: prefixText))
        case "sort":
            onAdd(.sort(by: sortBy, order: sortOrder))
        case "dedupe":
            onAdd(.dedupe(strategy: dedupeStrategy))
        case "limit":
            onAdd(.limit(count: max(1, Int(limitCount) ?? 30)))
        case "set-property":
            let val: JSONValue = propKey == "alpn" ? .string(propAlpn) : .bool(propBool)
            onAdd(.setProperty(key: propKey, value: val))
        default:
            onAdd(.flag(value: flagMode))
        }
        dismiss()
    }
}
