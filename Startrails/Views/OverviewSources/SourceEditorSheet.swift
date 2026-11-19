import SwiftUI
import UIKit

enum SourceEditorMode: Identifiable {
    case create(kind: SourceKind, prefill: String, suggestedName: String = "")
    case edit(SourceView)

    var id: String {
        switch self {
        case .create(let kind, let prefill, let suggested): return "create:\(kind.rawValue):\(suggested):\(prefill.prefix(16))"
        case .edit(let source): return "edit:\(source.id)"
        }
    }
}

struct SourceEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let mode: SourceEditorMode

    @State private var name: String = ""
    @State private var url: String = ""
    @State private var content: String = ""
    @State private var format: String = ""
    @State private var ua: String = ""
    @State private var refreshPolicy: String = "off"
    @State private var proxy: String = ""
    @State private var enabled: Bool = true
    @State private var attachToProfile: Bool = true
    @State private var isSaving: Bool = false
    @State private var isLoadingContent: Bool = false
    @State private var inspectStat: SourceStatView?
    @State private var isInspecting: Bool = false

    private var sourceKind: SourceKind {
        switch mode {
        case .create(let kind, _, _): return kind
        case .edit(let source): return source.kind
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称（留空将自动生成）", text: $name)
                    if isEditing {
                        Toggle("启用此订阅源", isOn: $enabled)
                    } else {
                        Toggle("创建后自动加入「\(store.activeProfile)」", isOn: $attachToProfile)
                    }
                }

                if sourceKind == .remote {
                    Section("远程订阅链接") {
                        TextField("https://...", text: $url, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .lineLimit(2...5)
                    }

                    Section("拉取策略（可选）") {
                        Picker("定时刷新周期", selection: $refreshPolicy) {
                            Text("不自动刷新").tag("off")
                            Text("每 30 分钟").tag("30m")
                            Text("每 2 小时").tag("2h")
                            Text("每 6 小时").tag("6h")
                            Text("每 12 小时").tag("12h")
                            Text("每天").tag("1d")
                        }
                        TextField("User-Agent（留空使用实例默认）", text: $ua)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("上游拉取代理（如 http://127.0.0.1:7890）", text: $proxy)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } else {
                    Section {
                        if isLoadingContent {
                            HStack {
                                ProgressView()
                                Text("正在加载正文...").foregroundStyle(.secondary)
                            }
                        } else {
                            TextEditor(text: $content)
                                .font(.caption.monospaced())
                                .frame(minHeight: 190)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    } header: {
                        HStack {
                            Text("节点或配置正文")
                            Spacer()
                            Button("从剪贴板粘贴") {
                                if let text = UIPasteboard.general.string {
                                    content = text
                                }
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }

                Section("输入格式") {
                    Picker("方言格式", selection: $format) {
                        Text("自动识别").tag("")
                        ForEach(store.workspaceState?.sourceFormats ?? ["uri", "clash", "surge", "singbox"], id: \.self) { fmt in
                            Text(fmt).tag(fmt)
                        }
                    }
                }

                if case .edit(let source) = mode, source.kind == .remote {
                    Section("解析状态与节点预览") {
                        if let err = source.lastError, !err.isEmpty {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if isInspecting {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("正在检查订阅节点...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let stat = inspectStat ?? store.sourceStatsById[source.id] {
                            HStack(spacing: 8) {
                                BadgePill(text: "\(stat.nodes) 节点", tint: .blue)
                                if stat.skipped > 0 {
                                    BadgePill(text: "跳过 \(stat.skipped)", tint: .orange)
                                }
                                if let fmt = stat.format {
                                    BadgePill(text: fmt, tint: .secondary)
                                }
                            }
                            if !stat.sample.isEmpty {
                                Text("节点样例：\(stat.sample.joined(separator: " · "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(stat.diagnostics) { diag in
                                Text("\(diag.subject)：\(diag.reason)")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }

                        Button {
                            Task { await refreshAndPreview(id: source.id) }
                        } label: {
                            HStack(spacing: 12) {
                                SettingsRowIcon(systemName: "arrow.clockwise", tint: .blue)
                                Text(isInspecting ? "正在拉取预览..." : "立即拉取并刷新预览")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isInspecting {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isInspecting || isSaving)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑订阅源" : (sourceKind == .remote ? "添加机场订阅" : "批量粘贴节点"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中..." : "保存") {
                        Task { await save() }
                    }
                    .disabled(isSaving || !isFormValid)
                }
            }
            .task {
                await prepareInitialValues()
            }
        }
    }

    private var isFormValid: Bool {
        if sourceKind == .remote {
            return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func prepareInitialValues() async {
        switch mode {
        case .create(let kind, let prefill, let suggestedName):
            if kind == .remote {
                url = prefill
                if !suggestedName.isEmpty {
                    name = suggestedName
                } else if let host = URL(string: prefill)?.host {
                    name = host
                }
            } else {
                content = prefill
                if !suggestedName.isEmpty {
                    name = suggestedName
                }
            }
        case .edit(let source):
            name = source.name
            url = source.url ?? ""
            format = source.format ?? ""
            ua = source.ua ?? ""
            refreshPolicy = source.refreshPolicy ?? "off"
            proxy = source.proxy ?? ""
            enabled = source.enabled
            if source.kind != .remote {
                isLoadingContent = true
                if let detail = try? await store.client.sourceDetail(id: source.id) {
                    content = detail.content ?? ""
                }
                isLoadingContent = false
            } else {
                inspectStat = store.sourceStatsById[source.id]
            }
        }
    }

    private func refreshAndPreview(id: String) async {
        isInspecting = true
        defer { isInspecting = false }
        do {
            _ = try await store.client.refreshSource(id: id)
            inspectStat = try await store.client.sourcePreview(id: id)
            await store.reloadAll()
            store.showToast("订阅已刷新")
            Haptics.notify(.success)
        } catch {
            store.handleError(error)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUA = ua.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProxy = proxy.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            switch mode {
            case .create(let kind, _, _):
                let payload = SourceInputPayload(
                    kind: kind,
                    name: trimmedName.isEmpty ? nil : trimmedName,
                    url: kind == .remote ? trimmedURL : nil,
                    content: kind == .remote ? nil : content,
                    format: format.isEmpty ? nil : format,
                    ua: trimmedUA.isEmpty ? nil : trimmedUA,
                    refreshPolicy: (kind == .remote && !refreshPolicy.isEmpty) ? refreshPolicy : nil,
                    proxy: trimmedProxy.isEmpty ? nil : trimmedProxy,
                    profile: attachToProfile ? store.activeProfile : nil
                )
                let created = try await store.client.addSource(payload)
                if attachToProfile && !created.attached,
                   let profileDef = store.currentProfileDef {
                    var nextEntries = profileDef.entries
                    if !nextEntries.contains(where: { $0.kind == .source && $0.id == created.id }) {
                        nextEntries.append(ProfileEntryView(kind: .source, id: created.id))
                        _ = try await store.client.saveProfile(entries: nextEntries, profile: store.activeProfile)
                    }
                }
                if kind == .remote {
                    _ = try? await store.client.refreshSource(id: created.id)
                }
                await store.reloadAll()
                store.showToast("已导入 \(created.name)")
                Haptics.notify(.success)
                dismiss()

            case .edit(let source):
                let payload = SourceInputPayload(
                    kind: source.kind,
                    name: trimmedName.isEmpty ? source.name : trimmedName,
                    url: source.kind == .remote ? trimmedURL : nil,
                    content: source.kind == .remote ? nil : content,
                    format: format.isEmpty ? "" : format,
                    ua: trimmedUA,
                    refreshPolicy: source.kind == .remote ? refreshPolicy : nil,
                    proxy: trimmedProxy,
                    enabled: enabled
                )
                _ = try await store.client.updateSource(id: source.id, payload: payload)
                await store.reloadAll()
                store.showToast("已保存更改")
                Haptics.notify(.success)
                dismiss()
            }
        } catch {
            store.handleError(error)
        }
    }
}
