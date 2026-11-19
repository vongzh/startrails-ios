import SwiftUI

enum OrchestrationSegment: String, CaseIterable {
    case composition
    case groups
    case rulesAndDns

    var title: String {
        switch self {
        case .composition: return "构成与清洗"
        case .groups: return "策略组"
        case .rulesAndDns: return "规则与 DNS"
        }
    }
}

struct OrchestrationView: View {
    @Environment(AppStore.self) private var store
    @Binding var showSettings: Bool
    @Binding var showCreateProfile: Bool
    @Binding var showRenameProfile: Bool
    @Binding var showDeleteProfile: Bool
    @Binding var newProfileName: String

    @State private var segment: OrchestrationSegment = .composition

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("编排模块", selection: $segment) {
                    ForEach(OrchestrationSegment.allCases, id: \.self) { seg in
                        Text(seg.title).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGroupedBackground))

                switch segment {
                case .composition:
                    ProfileCompositionSection()
                case .groups:
                    PolicyGroupsSection()
                case .rulesAndDns:
                    RulesRuntimeSection()
                }
            }
            .animation(.snappy(duration: 0.22), value: segment)
            .navigationTitle("编排与规则")
            .workspaceToolbar(
                showSettings: $showSettings,
                showCreateProfile: $showCreateProfile,
                showRenameProfile: $showRenameProfile,
                showDeleteProfile: $showDeleteProfile,
                newProfileName: $newProfileName
            )
        }
    }
}

// MARK: - Composition & Batch Transforms

private struct ProfileCompositionSection: View {
    @Environment(AppStore.self) private var store
    @State private var entries: [ProfileEntryView] = []
    @State private var isDirty = false
    @State private var isSaving = false
    @State private var showTransformsSheet = false

    private var availableEntries: [ProfileEntryView] {
        let existingKeys = Set(entries.map { "\($0.kind.rawValue):\($0.id)" })
        var list = [ProfileEntryView]()
        for col in store.collections {
            let candidate = ProfileEntryView(kind: .collection, id: col.id)
            if !existingKeys.contains("collection:\(col.id)") {
                list.append(candidate)
            }
        }
        for src in store.workspaceState?.sources ?? [] {
            let candidate = ProfileEntryView(kind: .source, id: src.id)
            if !existingKeys.contains("source:\(src.id)") {
                list.append(candidate)
            }
        }
        return list
    }

    var body: some View {
        List {
            Section {
                Button {
                    showTransformsSheet = true
                } label: {
                    HStack(spacing: 12) {
                        SettingsRowIcon(systemName: "wand.and.stars", tint: .purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("节点批量清洗规则")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(store.nodeTransforms.isEmpty
                                ? "按节点名批量移除、仅保留或改名"
                                : "已配置 \(store.nodeTransforms.count) 条算子（早于单节点标注生效）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        BadgePill(text: "\(store.nodeTransforms.count) 条", tint: .purple)
                        RowChevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section {
                if entries.isEmpty {
                    Text("当前配置尚无构成来源，请在下方点选添加。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries, id: \.id) { entry in
                        HStack(spacing: 12) {
                            SettingsRowIcon(
                                systemName: entry.kind == .collection ? "square.stack.3d.down.right" : "tray.fill",
                                tint: entry.kind == .collection ? .indigo : .blue
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(titleOf(entry))
                                    .font(.subheadline.weight(.medium))
                                Text(entry.kind == .collection ? "组合订阅" : "订阅源")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        entries.remove(atOffsets: offsets)
                        isDirty = true
                    }
                    .onMove { from, to in
                        entries.move(fromOffsets: from, toOffset: to)
                        isDirty = true
                    }
                }
            } header: {
                HStack {
                    Text("配置构成顺序 (\(entries.count))")
                    Spacer()
                    EditButton()
                        .font(.caption)
                        .textCase(nil)
                }
            } footer: {
                Text("构成顺序决定节点在默认策略组中的排列次序，仅作用于当前配置「\(store.activeProfile)」。")
            }

            if !availableEntries.isEmpty {
                Section("可加入的订阅源与组合") {
                    ForEach(availableEntries, id: \.id) { entry in
                        Button {
                            entries.append(entry)
                            isDirty = true
                            Haptics.impact(.light)
                        } label: {
                            HStack(spacing: 12) {
                                SettingsRowIcon(systemName: "plus", tint: .green)
                                Text(titleOf(entry))
                                    .foregroundStyle(.primary)
                                Spacer()
                                BadgePill(
                                    text: entry.kind == .collection ? "组合" : "来源",
                                    tint: entry.kind == .collection ? .indigo : .blue
                                )
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.snappy(duration: 0.24), value: isDirty)
        .safeAreaInset(edge: .bottom) {
            if isDirty {
                StickySaveBar(
                    title: "构成顺序已调整",
                    subtitle: "作用于配置「\(store.activeProfile)」",
                    isSaving: isSaving
                ) {
                    Task { await saveEntries() }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear { syncEntries() }
        .onChange(of: store.activeProfile) { _, _ in syncEntries() }
        .onChange(of: store.currentProfileDef?.entries) { _, _ in
            if !isDirty { syncEntries() }
        }
        .sheet(isPresented: $showTransformsSheet) {
            NodeTransformsSheet()
        }
    }

    private func syncEntries() {
        entries = store.currentProfileDef?.entries ?? []
        isDirty = false
    }

    private func titleOf(_ entry: ProfileEntryView) -> String {
        switch entry.kind {
        case .collection:
            return store.collections.first(where: { $0.id == entry.id })?.name ?? entry.id
        case .source:
            return store.workspaceState?.sources.first(where: { $0.id == entry.id })?.name ?? entry.id
        }
    }

    private func saveEntries() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await store.client.saveProfile(entries: entries, profile: store.activeProfile)
            isDirty = false
            await store.reloadAll()
            store.showToast("构成顺序已保存")
            Haptics.notify(.success)
        } catch {
            store.handleError(error)
        }
    }
}

private struct NodeTransformsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var transforms: [NodeTransformView] = []
    @State private var newPattern: String = ""
    @State private var newAction: TransformAction = .exclude
    @State private var newReplacement: String = ""
    @State private var isSaving: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("新增批量规则") {
                    TextField("匹配表达式（正则或字面量，如 /剩余|到期/i）", text: $newPattern)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("处理动作", selection: $newAction) {
                        ForEach(TransformAction.allCases, id: \.self) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    if newAction == .rename {
                        TextField("替换为（可用 {name} 代表原名）", text: $newReplacement)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Button {
                        let pat = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !pat.isEmpty else { return }
                        let rep = newReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
                        transforms.append(NodeTransformView(
                            id: UUID().uuidString.prefix(8).lowercased(),
                            order: transforms.count,
                            pattern: pat,
                            action: newAction,
                            replacement: newAction == .rename && !rep.isEmpty ? rep : nil
                        ))
                        newPattern = ""
                        newReplacement = ""
                        Haptics.impact(.light)
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "plus", tint: .teal)
                            Text("添加规则")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section {
                    if transforms.isEmpty {
                        Text("暂无批量清洗规则")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(transforms) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    BadgePill(text: item.action.label, tint: actionTint(item.action))
                                    Text(item.pattern)
                                        .font(.caption.monospaced())
                                }
                                if let rep = item.replacement, !rep.isEmpty {
                                    Text("-> \(rep)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            transforms.remove(atOffsets: offsets)
                        }
                        .onMove { from, to in
                            transforms.move(fromOffsets: from, toOffset: to)
                        }
                    }
                } header: {
                    HStack {
                        Text("已排序规则 (\(transforms.count))")
                        Spacer()
                        EditButton().font(.caption).textCase(nil)
                    }
                }
            }
            .navigationTitle("节点批量清洗")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中..." : "保存") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                transforms = store.nodeTransforms
            }
        }
    }

    private func actionTint(_ action: TransformAction) -> Color {
        switch action {
        case .exclude: return .red
        case .keep: return .green
        case .rename: return .blue
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let normalized = transforms.enumerated().map { idx, item in
            NodeTransformView(id: item.id, order: idx, pattern: item.pattern, action: item.action, replacement: item.replacement)
        }
        do {
            _ = try await store.client.saveNodeTransforms(normalized, profile: store.activeProfile)
            await store.reloadAll()
            store.showToast("批量清洗规则已保存")
            Haptics.notify(.success)
            dismiss()
        } catch {
            store.handleError(error)
        }
    }
}
