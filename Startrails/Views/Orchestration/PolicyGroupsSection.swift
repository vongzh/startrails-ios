import SwiftUI

struct PolicyGroupsSection: View {
    @Environment(AppStore.self) private var store

    @State private var mode: OverlayMode = .inherit
    @State private var autoIcons: Bool = true
    @State private var groups: [GroupView] = []
    @State private var isDirty = false
    @State private var isSaving = false

    @State private var editingGroupIndex: Int?
    @State private var showNewGroupAlert = false
    @State private var newGroupName = ""

    private var baseGroups: [PolicyGroupBaseView] {
        store.policyGroupsResponse?.base ?? []
    }

    var body: some View {
        List {
            Section {
                Picker("覆盖模式", selection: $mode) {
                    ForEach(OverlayMode.allCases, id: \.self) { item in
                        Text(item.label).tag(item)
                    }
                }
                .onChange(of: mode) { _, _ in isDirty = true }

                Toggle("策略组自动图标 (Fluent Emoji 3D / Twemoji)", isOn: $autoIcons)
                    .onChange(of: autoIcons) { _, _ in isDirty = true }
            } header: {
                Text("策略组覆盖策略")
            } footer: {
                Text("「自动继承」仅输出基础组；「合并增强」在基础组之上叠加自定义策略组；「完全覆盖」只使用下方列表。")
            }

            if mode != .inherit {
                Section {
                    if groups.isEmpty {
                        Text("尚未添加自定义策略组，点击下方按钮新建，或从基础组复制。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            PolicyGroupCardRow(
                                group: group,
                                autoIcons: autoIcons,
                                onEdit: { editingGroupIndex = index }
                            )
                        }
                        .onDelete { offsets in
                            groups.remove(atOffsets: offsets)
                            isDirty = true
                        }
                        .onMove { from, to in
                            groups.move(fromOffsets: from, toOffset: to)
                            isDirty = true
                        }
                    }

                    Button {
                        newGroupName = ""
                        showNewGroupAlert = true
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "plus", tint: .teal)
                            Text("新建策略组")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if !baseGroups.isEmpty && groups.isEmpty {
                        Button {
                            groups = baseGroups.map { base in
                                GroupView(
                                    name: base.name,
                                    members: base.members.map { .ref($0) },
                                    order: nil,
                                    strategy: base.strategy ?? .select,
                                    testUrl: base.testUrl,
                                    interval: base.interval,
                                    tolerance: base.tolerance,
                                    lazy: base.lazy,
                                    hidden: base.hidden,
                                    icon: base.icon
                                )
                            }
                            isDirty = true
                        } label: {
                            HStack(spacing: 12) {
                                SettingsRowIcon(systemName: "doc.on.doc", tint: .indigo)
                                Text("克隆当前继承的基础组 (\(baseGroups.count))")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("自定义策略组 (\(groups.count))")
                        Spacer()
                        EditButton().font(.caption).textCase(nil)
                    }
                }
            }

            if mode != .replace && !baseGroups.isEmpty {
                Section("基础继承策略组只读预览 (\(baseGroups.count))") {
                    ForEach(baseGroups) { base in
                        HStack(spacing: 12) {
                            let emoji = GroupIconResolver.resolveEmoji(
                                name: base.name,
                                strategy: base.strategy,
                                members: base.members.map { .ref($0) }
                            )
                            GroupEmojiBadge(
                                emoji: emoji,
                                iconURL: autoIcons ? GroupIconResolver.iconURL(for: emoji) : nil
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(base.name)
                                    .font(.subheadline.weight(.medium))
                                Text("\(base.strategy?.label ?? "select") · \(base.members.count) 成员")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.snappy(duration: 0.24), value: isDirty)
        .safeAreaInset(edge: .bottom) {
            if isDirty {
                StickySaveBar(
                    title: "策略组配置已修改",
                    subtitle: "\(groups.count) 个自定义组 · \(store.activeProfile)",
                    isSaving: isSaving
                ) {
                    Task { await save() }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear { syncFromStore() }
        .onChange(of: store.activeProfile) { _, _ in syncFromStore() }
        .onChange(of: store.policyGroupsResponse?.groups) { _, _ in
            if !isDirty { syncFromStore() }
        }
        .alert("新建策略组", isPresented: $showNewGroupAlert) {
            TextField("例如：🚀 节点选择 / 🇭🇰 香港节点", text: $newGroupName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !groups.contains(where: { $0.name == trimmed }) else { return }
                groups.append(GroupView(
                    name: trimmed,
                    members: [.rest],
                    order: groups.count,
                    strategy: .select
                ))
                isDirty = true
                editingGroupIndex = groups.count - 1
            }
        }
        .sheet(item: Binding(
            get: { editingGroupIndex.map { GroupEditIndex(index: $0) } },
            set: { editingGroupIndex = $0?.index }
        )) { sel in
            if groups.indices.contains(sel.index) {
                PolicyGroupEditorSheet(group: groups[sel.index]) { updated in
                    groups[sel.index] = updated
                    isDirty = true
                }
            }
        }
    }

    private func syncFromStore() {
        guard let res = store.policyGroupsResponse else { return }
        mode = res.mode
        autoIcons = res.groupIcons == "auto"
        groups = res.groups
        isDirty = false
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let ordered = groups.enumerated().map { idx, grp in
            var copy = grp
            copy.order = idx
            return copy
        }
        do {
            _ = try await store.client.savePolicyGroups(
                mode: mode,
                groupIcons: autoIcons ? "auto" : "off",
                groups: ordered,
                profile: store.activeProfile
            )
            isDirty = false
            await store.reloadAll()
            store.showToast("策略组已保存")
            Haptics.notify(.success)
        } catch {
            store.handleError(error)
        }
    }
}

private struct GroupEditIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

private struct PolicyGroupCardRow: View {
    let group: GroupView
    let autoIcons: Bool
    let onEdit: () -> Void

    private var previewEmoji: String {
        GroupIconResolver.resolveEmoji(name: group.name, strategy: group.strategy, members: group.members)
    }

    private var previewIconURL: URL? {
        if let custom = group.icon?.trimmingCharacters(in: .whitespaces), !custom.isEmpty {
            return URL(string: custom)
        }
        if autoIcons {
            return GroupIconResolver.iconURL(for: previewEmoji)
        }
        return nil
    }

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                GroupEmojiBadge(emoji: previewEmoji, iconURL: previewIconURL)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(group.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if group.hidden == true {
                            BadgePill(text: "隐藏", tint: .secondary)
                        }
                    }

                    HStack(spacing: 6) {
                        BadgePill(text: (group.strategy ?? .select).rawValue, tint: .blue)
                        BadgePill(text: "\(group.members.count) 成员", tint: .teal)
                    }

                    if !group.members.isEmpty {
                        Text(group.members.prefix(4).map(\.displayLabel).joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
                RowChevron()
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }
}

private struct GroupEmojiBadge: View {
    let emoji: String
    let iconURL: URL?

    @ViewBuilder
    private var safeEmojiFallback: some View {
        if let regionCode = RegionCatalog.regionCode(fromEmoji: emoji) {
            RegionFlagBadge(code: regionCode, font: .title3, monogramWidth: 26, monogramHeight: 20)
        } else {
            Text(emoji).font(.title3)
        }
    }

    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        safeEmojiFallback
                    }
                }
                .frame(width: 30, height: 30)
            } else {
                safeEmojiFallback
            }
        }
        .frame(width: 36, height: 36)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PolicyGroupEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State var group: GroupView
    let onSave: (GroupView) -> Void

    @State private var strategy: GroupStrategy = .select
    @State private var testUrl: String = ""
    @State private var intervalText: String = "300"
    @State private var toleranceText: String = "50"
    @State private var lazy: Bool = false
    @State private var hidden: Bool = false
    @State private var customIcon: String = ""

    @State private var addKind: String = "ref"
    @State private var refInput: String = ""
    @State private var matchPattern: String = ""
    @State private var selectedRegion: String = "HK"

    private var refSuggestions: [String] {
        var seen = Set<String>()
        var list = [String]()
        let raw = ["DIRECT", "REJECT"]
            + (store.policyGroupsResponse?.groups.map(\.name) ?? [])
            + (store.policyGroupsResponse?.base.map(\.name) ?? [])
        for name in raw where name != group.name && !name.isEmpty {
            if seen.insert(name).inserted {
                list.append(name)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("策略组属性") {
                    TextField("组名", text: $group.name)
                    Picker("调度策略", selection: $strategy) {
                        ForEach(GroupStrategy.allCases, id: \.self) { st in
                            Text(st.label).tag(st)
                        }
                    }
                    Toggle("在客户端中隐藏此组", isOn: $hidden)
                    TextField("自定义图标 URL（留空自动识别）", text: $customIcon)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if strategy != .select {
                    Section("测速 / 故障转移参数") {
                        TextField("测速 URL", text: $testUrl)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("检测间隔（秒）", text: $intervalText)
                            .keyboardType(.numberPad)
                        if strategy == .urlTest {
                            TextField("容差（ms）", text: $toleranceText)
                                .keyboardType(.numberPad)
                        }
                        Toggle("懒测速 (lazy)", isOn: $lazy)
                    }
                }

                Section {
                    ForEach(group.members) { member in
                        Text(member.displayLabel)
                            .font(.subheadline)
                    }
                    .onDelete { offsets in
                        group.members.remove(atOffsets: offsets)
                    }
                    .onMove { from, to in
                        group.members.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    HStack {
                        Text("成员顺序 (\(group.members.count))")
                        Spacer()
                        EditButton().font(.caption).textCase(nil)
                    }
                }

                Section("追加成员") {
                    Picker("成员类型", selection: $addKind) {
                        Text("引用节点/组 (ref)").tag("ref")
                        Text("按地区筛选 (region)").tag("region")
                        Text("正则匹配 (match)").tag("match")
                        Text("其余节点 (rest)").tag("rest")
                    }

                    switch addKind {
                    case "region":
                        Picker("选择地区", selection: $selectedRegion) {
                            ForEach(["HK", "TW", "JP", "SG", "US", "UK", "DE", "KR"], id: \.self) { code in
                                Text("\(RegionCatalog.displayLabel(for: code)) (\(code))").tag(code)
                            }
                        }
                        Button {
                            let item = GroupMemberItem.region(selectedRegion)
                            if !group.members.contains(item) { group.members.append(item) }
                            Haptics.impact(.light)
                        } label: {
                            HStack(spacing: 12) {
                                SettingsRowIcon(systemName: "plus", tint: .teal)
                                Text("添加地区成员")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    case "match":
                        TextField("正则（如 /香港|HK/i）", text: $matchPattern)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            let pat = matchPattern.trimmingCharacters(in: .whitespaces)
                            guard !pat.isEmpty else { return }
                            group.members.append(.match(pat))
                            matchPattern = ""
                            Haptics.impact(.light)
                        } label: {
                            HStack(spacing: 12) {
                                SettingsRowIcon(systemName: "plus", tint: .teal)
                                Text("添加正则匹配")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(matchPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                    case "rest":
                        Button {
                            if !group.members.contains(.rest) {
                                group.members.append(.rest)
                                Haptics.impact(.light)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                SettingsRowIcon(systemName: "plus", tint: .teal)
                                Text("添加其余节点 (rest)")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(group.members.contains(.rest))
                    default:
                        TextField("组名、节点别名或 DIRECT / REJECT", text: $refInput)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(refSuggestions, id: \.self) { candidate in
                                    Button(candidate) {
                                        let item = GroupMemberItem.ref(candidate)
                                        if !group.members.contains(item) { group.members.append(item) }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                            }
                        }
                        Button {
                            let val = refInput.trimmingCharacters(in: .whitespaces)
                            guard !val.isEmpty else { return }
                            let item = GroupMemberItem.ref(val)
                            if !group.members.contains(item) { group.members.append(item) }
                            refInput = ""
                            Haptics.impact(.light)
                        } label: {
                            HStack(spacing: 12) {
                                SettingsRowIcon(systemName: "plus", tint: .teal)
                                Text("添加引用")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(refInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("编辑策略组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        applyAndClose()
                    }
                    .disabled(group.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                strategy = group.strategy ?? .select
                testUrl = group.testUrl ?? (strategy == .select ? "" : "https://www.gstatic.com/generate_204")
                intervalText = group.interval.map(String.init) ?? "300"
                toleranceText = group.tolerance.map(String.init) ?? "50"
                lazy = group.lazy ?? false
                hidden = group.hidden ?? false
                customIcon = group.icon ?? ""
            }
        }
    }

    private func applyAndClose() {
        var next = group
        next.name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.strategy = strategy
        if strategy == .select {
            next.testUrl = nil
            next.interval = nil
            next.tolerance = nil
            next.lazy = nil
        } else {
            let trimmedURL = testUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            next.testUrl = trimmedURL.isEmpty ? "https://www.gstatic.com/generate_204" : trimmedURL
            next.interval = Int(intervalText) ?? 300
            next.tolerance = strategy == .urlTest ? (Int(toleranceText) ?? 50) : nil
            next.lazy = lazy ? true : nil
        }
        next.hidden = hidden ? true : nil
        let trimmedIcon = customIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        next.icon = trimmedIcon.isEmpty ? nil : trimmedIcon
        onSave(next)
        dismiss()
    }
}
