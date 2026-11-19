import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showAddServer = false
    @State private var showRotateToken = false
    @State private var nextAdminToken = ""
    @State private var isUpdatingGeo = false
    @State private var isBackingUpLocal = false
    @State private var showFetchDefaults = false
    @State private var showWebDav = false
    @State private var showNotify = false
    @State private var showHistory = false
    @State private var showCapabilities = false
    @State private var showTipJar = false

    var body: some View {
        @Bindable var lock = store.lockManager

        NavigationStack {
            List {
                Section("控制台实例") {
                    ForEach(store.servers) { server in
                        Button {
                            Task { await store.switchServer(server) }
                        } label: {
                            HStack(spacing: 12) {
                                SettingsRowIcon(
                                    systemName: "server.rack",
                                    tint: server.id == store.activeServer?.id ? .green : .secondary
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(server.baseURL)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if server.id == store.activeServer?.id {
                                    BadgePill(text: "当前", tint: .green)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if store.servers.count > 1 {
                                Button(role: .destructive) {
                                    store.removeServer(server)
                                } label: {
                                    Label("移除", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Button {
                        showAddServer = true
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "plus", tint: .teal)
                            Text("添加或切换新实例")
                                .foregroundStyle(.primary)
                            Spacer()
                            RowChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showRotateToken = true
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "key.radiowaves.forward", tint: .orange)
                            Text("轮换服务端管理令牌")
                                .foregroundStyle(.primary)
                            Spacer()
                            RowChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section("安全与隐私") {
                    Toggle(isOn: $lock.isEnabled) {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: store.lockManager.biometricIcon, tint: .indigo)
                            Text(store.lockManager.biometricLabel)
                                .foregroundStyle(.primary)
                        }
                    }

                    Button(role: .destructive) {
                        store.signOutCurrentServer()
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "rectangle.portrait.and.arrow.right", tint: .red)
                            Text("断开当前实例令牌")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                }

                Section("离线 Geo IP / ASN 库") {
                    if let geo = store.geoStatus {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "globe.desk", tint: .teal)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(geo.available ? "已就绪 (\(geo.source))" : "尚未下载离线库")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text("v4: \(geo.counts.countryV4) 条 · v6: \(geo.counts.countryV6) 条 · \(Formatters.bytes(Double(geo.bytes)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let updatedAt = geo.updatedAt {
                                    Text("更新于 \(Formatters.isoShort(updatedAt))")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Button {
                                Task { await triggerGeoUpdate() }
                            } label: {
                                Group {
                                    if isUpdatingGeo {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Text("更新")
                                            .font(.caption.weight(.semibold))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(.primary)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(isUpdatingGeo)
                        }
                    } else {
                        Text("正在加载 Geo 状态...")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button { showFetchDefaults = true } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "network.badge.shield.half.filled", tint: .indigo)
                            Text("全局拉取默认")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("UA / 代理")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            RowChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button { showWebDav = true } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "externaldrive.badge.icloud", tint: .teal)
                            Text("WebDAV 远端备份")
                                .foregroundStyle(.primary)
                            Spacer()
                            BadgePill(
                                text: store.opsStatus?.webdav.configured == true ? "已配置" : "未配置",
                                tint: store.opsStatus?.webdav.configured == true ? .green : .secondary
                            )
                            RowChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button { showNotify = true } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "bell.badge", tint: .orange)
                            Text("通知渠道")
                                .foregroundStyle(.primary)
                            Spacer()
                            let channels = store.opsStatus?.notify.channels ?? []
                            BadgePill(
                                text: channels.isEmpty ? "未配置" : channels.joined(separator: "+"),
                                tint: channels.isEmpty ? .secondary : .green
                            )
                            RowChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await runLocalBackup() }
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "internaldrive", tint: .secondary)
                            Text("服务端 SQLite 快照备份")
                                .foregroundStyle(.primary)
                            Spacer()
                            if isBackingUpLocal {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("立即执行")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBackingUpLocal)
                } header: {
                    Text("服务端运维")
                } footer: {
                    if let intervalMs = store.opsStatus?.scheduler.intervalMs, intervalMs > 0 {
                        Text("服务端后台巡检调度间隔：每 \(Formatters.age(ms: intervalMs)) 检查一次到期订阅源。")
                    }
                }

                Section("诊断与能力") {
                    Button { showHistory = true } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "doc.text.magnifyingglass", tint: .purple)
                            Text("构建历史与诊断回执")
                                .foregroundStyle(.primary)
                            Spacer()
                            RowChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button { showCapabilities = true } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "checklist", tint: .green)
                            Text("客户端能力矩阵")
                                .foregroundStyle(.primary)
                            Spacer()
                            RowChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section("支持与关于") {
                    Button {
                        Haptics.impact(.light)
                        showTipJar = true
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "cup.and.saucer.fill", tint: .brown)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("请作者喝杯咖啡")
                                    .foregroundStyle(.primary)
                                Text("全部功能免费 · 自愿赞赏支持")
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

                if let health = store.healthInfo {
                    Section("版本信息") {
                        LabeledContent("客户端版本", value: appVersionLabel)
                        LabeledContent("服务端版本", value: "v\(health.version)")
                        LabeledContent("内核 IR 版本", value: "v\(health.coreVersion)")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("控制台设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddServer) {
                OnboardingLoginView(isAddingModal: true)
            }
            .sheet(isPresented: $showFetchDefaults) { FetchDefaultsSheet() }
            .sheet(isPresented: $showWebDav) { WebDavSettingsSheet() }
            .sheet(isPresented: $showNotify) { NotifySettingsSheet() }
            .sheet(isPresented: $showHistory) { BuildHistorySheet() }
            .sheet(isPresented: $showCapabilities) { CapabilitiesSheet() }
            .sheet(isPresented: $showTipJar) { TipJarSheet() }
            .alert("轮换管理令牌", isPresented: $showRotateToken) {
                SecureField("输入新管理令牌（至少 8 位）", text: $nextAdminToken)
                Button("取消", role: .cancel) {}
                Button("确认轮换") {
                    Task { await rotateToken() }
                }
            } message: {
                Text("轮换后当前设备的 Keychain 凭据将同步更新；若服务端由环境变量锁定将返回提示。")
            }
        }
    }

    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(short) (\(build))"
    }

    private func triggerGeoUpdate() async {
        isUpdatingGeo = true
        defer { isUpdatingGeo = false }
        do {
            let res = try await store.client.updateGeo()
            store.geoStatus = res.status
            await store.reloadAll()
            store.showToast("离线 Geo 库已更新")
            Haptics.notify(.success)
        } catch {
            store.handleError(error)
        }
    }

    private func runLocalBackup() async {
        isBackingUpLocal = true
        defer { isBackingUpLocal = false }
        do {
            let res = try await store.client.backupLocal()
            store.showToast("本地备份完成：\(res.destination)")
            Haptics.notify(.success)
        } catch {
            store.handleError(error)
        }
    }

    private func rotateToken() async {
        let trimmed = nextAdminToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            store.showToast("新令牌至少需要 8 位字符", isError: true)
            return
        }
        do {
            _ = try await store.client.rotateAdminToken(trimmed)
            if let id = store.activeServer?.id {
                KeychainStore.saveToken(trimmed, forServerId: id)
            }
            await store.bootstrap()
            nextAdminToken = ""
            store.showToast("管理令牌已轮换并同步到本地钥匙串")
            Haptics.notify(.success)
        } catch {
            store.handleError(error)
        }
    }
}

// MARK: - Ops Sub-Sheets

private struct FetchDefaultsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var ua: String = ""
    @State private var proxy: String = ""
    @State private var headers: [FetchHeaderView] = []
    @State private var newHeaderName: String = ""
    @State private var newHeaderValue: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("默认拉取参数") {
                    TextField("默认 User-Agent（如 clash.meta）", text: $ua)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("默认上游代理（http/https/socks5）", text: $proxy)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("附加请求头（值已脱敏，未改项保留原值）") {
                    ForEach(headers) { hdr in
                        HStack {
                            Text(hdr.name).font(.caption.monospaced())
                            Spacer()
                            Text(hdr.value).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in headers.remove(atOffsets: offsets) }

                    TextField("Header 名（例如 X-Token）", text: $newHeaderName)
                        .textInputAutocapitalization(.never)
                    TextField("Header 值", text: $newHeaderValue)
                        .textInputAutocapitalization(.never)
                    Button {
                        let k = newHeaderName.trimmingCharacters(in: .whitespaces)
                        let v = newHeaderValue.trimmingCharacters(in: .whitespaces)
                        guard !k.isEmpty, !v.isEmpty else { return }
                        headers.append(FetchHeaderView(name: k, value: v))
                        newHeaderName = ""
                        newHeaderValue = ""
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "plus", tint: .teal)
                            Text("添加请求头")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("全局拉取默认")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中..." : "保存") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .task {
                if let res = try? await store.client.fetchDefaults(), let val = res.value {
                    ua = val.ua ?? ""
                    proxy = val.proxy ?? ""
                    headers = val.headers
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let payload = FetchDefaultsView(
            ua: ua.trimmingCharacters(in: .whitespaces).isEmpty ? nil : ua.trimmingCharacters(in: .whitespaces),
            proxy: proxy.trimmingCharacters(in: .whitespaces).isEmpty ? nil : proxy.trimmingCharacters(in: .whitespaces),
            headers: headers
        )
        do {
            _ = try await store.client.saveFetchDefaults(payload)
            store.showToast("全局拉取默认已保存")
            dismiss()
        } catch {
            store.handleError(error)
        }
    }
}

private struct WebDavSettingsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var url: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var hasExistingPassword = false
    @State private var effectiveURL: String?
    @State private var isTesting = false
    @State private var isBackingUp = false

    var body: some View {
        NavigationStack {
            Form {
                Section("WebDAV 目标") {
                    TextField("https://dav.example.com/startrails/", text: $url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("用户名（可选）", text: $username)
                        .textInputAutocapitalization(.never)
                    SecureField(hasExistingPassword ? "留空保持原密码" : "密码（可选）", text: $password)
                }
                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "antenna.radiowaves.left.and.right", tint: .teal)
                            Text(isTesting ? "探测中..." : "测试 WebDAV 连通性")
                                .foregroundStyle(.primary)
                            Spacer()
                            if isTesting { ProgressView().controlSize(.small) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isTesting || (url.trimmingCharacters(in: .whitespaces).isEmpty && effectiveURL == nil))

                    Button {
                        Task { await uploadBackup() }
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "icloud.and.arrow.up", tint: .indigo)
                            Text(isBackingUp ? "上传中..." : "立即备份并上传到 WebDAV")
                                .foregroundStyle(.primary)
                            Spacer()
                            if isBackingUp { ProgressView().controlSize(.small) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBackingUp)
                } footer: {
                    if url.isEmpty, let eff = effectiveURL {
                        Text("当前由服务端环境变量生效：\(eff)")
                    }
                }
            }
            .navigationTitle("WebDAV 远端备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                }
            }
            .task {
                if let res = try? await store.client.webdavSettings() {
                    if let val = res.value {
                        url = val.url
                        username = val.username ?? ""
                        hasExistingPassword = val.hasPassword
                    }
                    effectiveURL = res.effective?.url
                }
            }
        }
    }

    private func currentPayload() -> WebDavConfigPayload? {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { return nil }
        return WebDavConfigPayload(
            url: u,
            username: username.trimmingCharacters(in: .whitespaces).isEmpty ? nil : username.trimmingCharacters(in: .whitespaces),
            password: password.isEmpty ? nil : password
        )
    }

    private func save() async {
        do {
            _ = try await store.client.saveWebdav(currentPayload())
            await store.reloadAll()
            store.showToast("WebDAV 配置已保存")
            dismiss()
        } catch {
            store.handleError(error)
        }
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let res = try await store.client.testWebdav(currentPayload())
            if res.ok {
                store.showToast("WebDAV 连通正常 (HTTP \(res.status))")
                Haptics.notify(.success)
            } else {
                store.showToast(res.reason ?? res.hint ?? res.error ?? "连接失败", isError: true)
            }
        } catch {
            store.handleError(error)
        }
    }

    private func uploadBackup() async {
        isBackingUp = true
        defer { isBackingUp = false }
        do {
            let res = try await store.client.backupRemote()
            store.showToast("已上传远程备份（\(Formatters.bytes(Double(res.bytes)))）")
            Haptics.notify(.success)
        } catch {
            store.handleError(error)
        }
    }
}

private struct NotifySettingsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var enabled = true
    @State private var botToken = ""
    @State private var chatId = ""
    @State private var barkUrl = ""
    @State private var envEffectiveNote = false
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("启用异常与到期推送", isOn: $enabled)
                }
                Section("Telegram Bot") {
                    TextField("Bot Token", text: $botToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Chat ID", text: $chatId)
                        .textInputAutocapitalization(.never)
                }
                Section("Bark (iOS 推送)") {
                    TextField("https://api.day.app/<key>", text: $barkUrl)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                Section {
                    Button {
                        Task { await testSend() }
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "paperplane.fill", tint: .orange)
                            Text(isTesting ? "发送中..." : "发送测试通知")
                                .foregroundStyle(.primary)
                            Spacer()
                            if isTesting { ProgressView().controlSize(.small) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isTesting)
                } footer: {
                    if envEffectiveNote {
                        Text("当前由服务端环境变量配置推送通道，在此保存将优先使用表单设置。")
                    }
                }
            }
            .navigationTitle("通知渠道设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                }
            }
            .task {
                if let res = try? await store.client.notifySettings() {
                    if let val = res.value {
                        enabled = val.enabled ?? true
                        botToken = val.botToken ?? ""
                        chatId = val.chatId ?? ""
                        barkUrl = val.barkUrl ?? ""
                    } else if res.effective != nil {
                        envEffectiveNote = true
                    }
                }
            }
        }
    }

    private func currentPayload() -> NotifyConfigView? {
        let bt = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let cid = chatId.trimmingCharacters(in: .whitespacesAndNewlines)
        let bark = barkUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if bt.isEmpty && bark.isEmpty { return nil }
        return NotifyConfigView(
            enabled: enabled,
            botToken: bt.isEmpty ? nil : bt,
            chatId: cid.isEmpty ? nil : cid,
            barkUrl: bark.isEmpty ? nil : bark
        )
    }

    private func save() async {
        do {
            _ = try await store.client.saveNotify(currentPayload())
            await store.reloadAll()
            store.showToast("通知配置已保存")
            dismiss()
        } catch {
            store.handleError(error)
        }
    }

    private func testSend() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let res = try await store.client.testNotify(currentPayload())
            if res.ok == true {
                store.showToast("测试通知已发送成功")
                Haptics.notify(.success)
            } else {
                let err = res.results?.first(where: { !$0.ok })?.error ?? res.hint ?? res.error ?? "发送失败"
                store.showToast(err, isError: true)
            }
        } catch {
            store.handleError(error)
        }
    }
}

struct BuildHistorySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [HistoryEntry] = []
    @State private var selectedReport: BuildReportView?

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Text("客户端尚未拉取过构建产物")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { item in
                        Button {
                            Task {
                                selectedReport = try? await store.client.buildReport(buildId: item.buildId)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                ClientBrandIcon(targetId: item.target, size: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.target)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(item.passed) 通过 · \(item.skipped) 跳过 · \(Formatters.isoShort(item.createdAt))")
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
                }
            }
            .navigationTitle("构建历史回执")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } }
            }
            .task {
                entries = (try? await store.client.diagnostics()) ?? []
            }
            .sheet(item: Binding(
                get: { selectedReport.map { IdentifiableReport(report: $0) } },
                set: { selectedReport = $0?.report }
            )) { wrapper in
                NavigationStack {
                    Group {
                        if wrapper.report.report.diagnostics.isEmpty {
                            ContentUnavailableView(
                                "本次构建 0 警告",
                                systemImage: "checkmark.seal.fill",
                                description: Text("\(wrapper.report.report.passed) 项全部无损适配 \(wrapper.report.target)")
                            )
                        } else {
                            List(wrapper.report.report.diagnostics) { diag in
                                VStack(alignment: .leading, spacing: 3) {
                                    BadgePill(text: diag.stage, tint: .orange)
                                    Text(diag.subject).font(.subheadline.weight(.medium))
                                    Text(diag.reason).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .navigationTitle(wrapper.report.target)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("关闭") { selectedReport = nil }
                        }
                    }
                }
            }
        }
    }
}

private struct IdentifiableReport: Identifiable {
    let report: BuildReportView
    var id: String { report.buildId }
}

private struct CapabilitiesSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var evidence: [EvidenceView] = []
    @State private var query: String = ""

    private var filtered: [EvidenceView] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return evidence }
        return evidence.filter {
            $0.target.lowercased().contains(q) ||
                $0.subject.lowercased().contains(q) ||
                $0.note.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        ClientBrandIcon(targetId: item.target, size: 18)
                        Text(item.target)
                            .font(.caption.weight(.semibold))
                        BadgePill(text: item.scope, tint: .secondary)
                        Spacer()
                        BadgePill(text: item.value, tint: item.value == "reject" ? .red : .green)
                    }
                    Text(item.subject)
                        .font(.subheadline.weight(.semibold))
                    if !item.note.isEmpty {
                        Text(item.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .navigationTitle("客户端能力矩阵")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "筛选客户端或字段...")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } }
            }
            .task {
                evidence = (try? await store.client.capabilities()) ?? []
            }
        }
    }
}
