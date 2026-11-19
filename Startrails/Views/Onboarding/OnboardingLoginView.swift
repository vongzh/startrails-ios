import SwiftUI

struct OnboardingLoginView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var isAddingModal: Bool = false

    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var adminToken: String = ""
    @State private var secret: String = ""

    @State private var checkingSetup: Bool = false
    @State private var setupRequired: Bool = false
    @State private var secretRequired: Bool = false
    @State private var showScanner: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var showAdminToken: Bool = false
    @State private var showSecret: Bool = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    headerBanner

                    if !store.servers.isEmpty {
                        savedServersSection
                    }

                    if let reason = store.authFailureReason {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.lock.fill")
                                .foregroundStyle(.orange)
                            Text(reason)
                                .font(.footnote)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }

                    connectionForm

                    if let localError {
                        Text(localError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Haptics.impact(.light)
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "bolt.shield.fill")
                            }
                            Text(setupRequired || secretRequired ? "初始化实例并连接" : "连接 Startrails 控制台")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(isSubmitting || baseURL.trimmingCharacters(in: .whitespaces).isEmpty || adminToken.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isAddingModal ? "添加或切换实例" : "连接控制台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isAddingModal {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Label("扫码", systemImage: "qrcode.viewfinder")
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerSheet(
                    title: "扫描控制台连接码",
                    hint: "支持 Startrails 服务地址或 JSON 连接配置",
                    onScanned: applyScannedPayload
                )
            }
            .onAppear {
                if !isAddingModal, baseURL.isEmpty, let active = store.activeServer {
                    name = active.name
                    baseURL = active.baseURL
                }
            }
        }
    }

    private var headerBanner: some View {
        VStack(spacing: 12) {
            StarTrailsEmblem(size: 78)
            Text("Startrails · 星迹")
                .font(.title2.bold())
            Text("自托管多客户端代理订阅编排控制台")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var savedServersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已保存实例")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(store.servers) { server in
                Button {
                    Haptics.impact(.light)
                    name = server.name
                    baseURL = server.baseURL
                    if let savedToken = KeychainStore.loadToken(forServerId: server.id) {
                        adminToken = savedToken
                    }
                    Task { await store.switchServer(server) }
                } label: {
                    HStack(spacing: 12) {
                        SettingsRowIcon(
                            systemName: "server.rack",
                            tint: server.id == store.activeServerId ? .green : .indigo
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(server.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if server.id == store.activeServerId {
                                    BadgePill(text: "上次使用", tint: .green)
                                }
                            }
                            Text(server.baseURL)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        RowChevron()
                    }
                    .surfaceCard(cornerRadius: 14, padding: 12)
                }
                .buttonStyle(PressScaleButtonStyle())
            }
        }
    }

    private var connectionForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("服务端地址")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await probeSetupStatus() }
                    } label: {
                        if checkingSetup {
                            ProgressView().controlSize(.mini)
                        } else {
                            Label("检测实例状态", systemImage: "dot.radiowaves.left.and.right")
                                .font(.caption.weight(.medium))
                        }
                    }
                }
                TextField("https://sub.example.com 或 http://192.168.1.10:8787", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("实例备注名（可选）")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("例如：家宽主力 / 轻量 VPS", text: $name)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(setupRequired ? "设置管理令牌（至少 8 位）" : "管理令牌 (Bearer Admin Token)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Group {
                        if showAdminToken {
                            TextField("输入 Startrails Admin Token", text: $adminToken)
                        } else {
                            SecureField("输入 Startrails Admin Token", text: $adminToken)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Button {
                        showAdminToken.toggle()
                    } label: {
                        Image(systemName: showAdminToken ? "eye.slash" : "eye")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }

            if secretRequired {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Token 加密主密钥（首次启动需要设置，至少 16 位）")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                    HStack(spacing: 8) {
                        Group {
                            if showSecret {
                                TextField("输入 STARTRAILS_TOKEN_SECRET", text: $secret)
                            } else {
                                SecureField("输入 STARTRAILS_TOKEN_SECRET", text: $secret)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button {
                            showSecret.toggle()
                        } label: {
                            Image(systemName: showSecret ? "eye.slash" : "eye")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .surfaceCard(cornerRadius: 16, padding: 16)
    }

    private func probeSetupStatus() async {
        let normalized = ServerConnection.normalizeBaseURL(baseURL)
        guard !normalized.isEmpty else { return }
        checkingSetup = true
        localError = nil
        defer { checkingSetup = false }

        do {
            await store.client.configure(baseURL: normalized, adminToken: "")
            let status = try await store.client.setupStatus()
            setupRequired = status.required
            secretRequired = status.secretRequired
            if status.required || status.secretRequired {
                store.showToast("检测到未初始化的新实例，可直接设置初始凭据")
            } else {
                store.showToast("实例在线，请输入管理令牌登录")
            }
        } catch {
            localError = error.localizedDescription
        }
    }

    private func submit() async {
        let normalized = ServerConnection.normalizeBaseURL(baseURL)
        let trimmedToken = adminToken.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true
        localError = nil
        defer { isSubmitting = false }

        do {
            await store.client.configure(baseURL: normalized, adminToken: "")
            if let status = try? await store.client.setupStatus(),
               status.required || status.secretRequired {
                setupRequired = status.required
                secretRequired = status.secretRequired
                if status.secretRequired && secret.trimmingCharacters(in: .whitespacesAndNewlines).count < 16 {
                    localError = "该实例尚未配置加密主密钥，请至少填写 16 位密钥"
                    return
                }
                _ = try await store.client.setup(
                    token: status.required ? trimmedToken : nil,
                    secret: status.secretRequired ? secret.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                )
            }

            let matchingExistingId = store.servers.first(where: { $0.baseURL == normalized })?.id
            try await store.connectAndSave(
                name: name,
                baseURL: normalized,
                adminToken: trimmedToken,
                existingServerId: matchingExistingId
            )
            if isAddingModal {
                dismiss()
            }
        } catch {
            localError = error.localizedDescription
        }
    }

    private func applyScannedPayload(_ raw: String) {
        if let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let u = json["url"] as? String { baseURL = u }
            if let t = json["token"] as? String { adminToken = t }
            if let n = json["name"] as? String { name = n }
            return
        }
        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            baseURL = raw
            Task { await probeSetupStatus() }
        }
    }
}
