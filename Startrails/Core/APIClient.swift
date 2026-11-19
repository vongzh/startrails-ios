import Foundation

enum APIError: LocalizedError, Sendable {
    case invalidURL(String)
    case unauthorized(message: String)
    case serverError(statusCode: Int, code: String, hint: String?)
    case network(Error)
    case decoding(Error)

    var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "无效的服务端地址：\(url)"
        case .unauthorized(let message):
            return message.isEmpty ? "管理令牌无效或已轮换，请重新验证" : message
        case .serverError(let status, let code, let hint):
            if let hint, !hint.isEmpty {
                return "\(hint)（\(code) · HTTP \(status)）"
            }
            return "\(code)（HTTP \(status)）"
        case .network(let err):
            return "网络请求失败：\(err.localizedDescription)"
        case .decoding(let err):
            return "响应解析失败：\(err.localizedDescription)"
        }
    }
}

private struct ServerErrorBody: Decodable {
    let error: String?
    let hint: String?
    let reason: String?
    let detail: String?
}

actor APIClient {
    private let session: URLSession
    private var baseURL: String
    private var adminToken: String

    init(baseURL: String = "", adminToken: String = "") {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
        self.baseURL = ServerConnection.normalizeBaseURL(baseURL)
        self.adminToken = adminToken
    }

    func configure(baseURL: String, adminToken: String) {
        self.baseURL = ServerConnection.normalizeBaseURL(baseURL)
        self.adminToken = adminToken
    }

    // MARK: - Generic Request Helpers

    private func buildURL(path: String, query: [(String, String)] = []) throws -> URL {
        guard !baseURL.isEmpty else {
            throw APIError.invalidURL(baseURL)
        }
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard var components = URLComponents(string: "\(baseURL)\(normalizedPath)") else {
            throw APIError.invalidURL("\(baseURL)\(normalizedPath)")
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else {
            throw APIError.invalidURL("\(baseURL)\(normalizedPath)")
        }
        return url
    }

    private static let clientUserAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Startrails-iOS/\(version)"
    }()

    private func send<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [(String, String)] = [],
        bodyData: Data? = nil,
        softErrorDecoding: Bool = false
    ) async throws -> T {
        let url = try buildURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Self.clientUserAgent, forHTTPHeaderField: "User-Agent")
        if !adminToken.isEmpty {
            request.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization")
        }
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(statusCode: 0, code: "invalid-response", hint: nil)
        }

        if http.statusCode == 401 && !path.hasPrefix("/api/setup") {
            let body = try? JSONDecoder().decode(ServerErrorBody.self, from: data)
            throw APIError.unauthorized(message: body?.hint ?? body?.error ?? "管理令牌无效")
        }

        if !softErrorDecoding && !(200...299).contains(http.statusCode) {
            let body = try? JSONDecoder().decode(ServerErrorBody.self, from: data)
            let code = body?.error ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            let hint = body?.hint ?? body?.reason ?? body?.detail
            if http.statusCode == 401 {
                throw APIError.unauthorized(message: hint ?? code)
            }
            throw APIError.serverError(statusCode: http.statusCode, code: code, hint: hint)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func encodeJSON<U: Encodable>(_ payload: U) throws -> Data {
        try JSONEncoder().encode(payload)
    }

    // MARK: - Setup & Health

    func setupStatus() async throws -> SetupStatusResponse {
        try await send("/api/setup/status")
    }

    func setup(token: String?, secret: String?) async throws -> OkResponse {
        struct Body: Encodable {
            let token: String?
            let secret: String?
        }
        return try await send("/api/setup", method: "POST", bodyData: encodeJSON(Body(token: token, secret: secret)))
    }

    func health() async throws -> HealthResponse {
        try await send("/health")
    }

    func rotateAdminToken(_ token: String) async throws -> OkResponse {
        struct Body: Encodable { let token: String }
        return try await send("/api/admin/token", method: "POST", bodyData: encodeJSON(Body(token: token)))
    }

    // MARK: - Workspace State & Nodes

    func state(profile: String?) async throws -> StateView {
        let q = profile.map { [("profile", $0)] } ?? []
        return try await send("/api/state", query: q)
    }

    func nodes(profile: String) async throws -> NodesResponse {
        try await send("/api/nodes", query: [("profile", profile)])
    }

    func preview(target: String, profile: String) async throws -> PreviewView {
        try await send("/api/preview", query: [("target", target), ("profile", profile)])
    }

    func trace(profile: String) async throws -> PreviewView.TraceWrapper {
        try await send("/api/trace", query: [("profile", profile)])
    }

    func inspectSources() async throws -> [SourceStatView] {
        struct Wrapper: Decodable { let sources: [SourceStatView] }
        let res: Wrapper = try await send("/api/sources/inspect")
        return res.sources
    }

    func saveAnnotation(_ annotation: AnnotationView, profile: String) async throws -> OkResponse {
        try await send(
            "/api/annotations",
            method: "POST",
            query: [("profile", profile)],
            bodyData: encodeJSON(annotation)
        )
    }

    func nodeTransforms(profile: String) async throws -> NodeTransformsResponse {
        try await send("/api/node-transforms", query: [("profile", profile)])
    }

    func saveNodeTransforms(_ transforms: [NodeTransformView], profile: String) async throws -> NodeTransformsResponse {
        struct Body: Encodable { let transforms: [NodeTransformView] }
        return try await send(
            "/api/node-transforms",
            method: "PUT",
            query: [("profile", profile)],
            bodyData: encodeJSON(Body(transforms: transforms))
        )
    }

    // MARK: - Sources & Collections & Profiles

    func addSource(_ payload: SourceInputPayload) async throws -> AddSourceResponse {
        try await send("/api/sources", method: "POST", bodyData: encodeJSON(payload))
    }

    private static let pathSegmentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private func seg(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: Self.pathSegmentAllowed) ?? value
    }

    func sourceDetail(id: String) async throws -> SourceDetailResponse {
        try await send("/api/sources/\(seg(id))")
    }

    func sourcePreview(id: String) async throws -> SourceStatView {
        try await send("/api/sources/\(seg(id))/preview")
    }

    func updateSource(id: String, payload: SourceInputPayload) async throws -> OkResponse {
        try await send("/api/sources/\(seg(id))", method: "PUT", bodyData: encodeJSON(payload))
    }

    func refreshSource(id: String) async throws -> RefreshSourceResponse {
        try await send("/api/sources/\(seg(id))/refresh", method: "POST", bodyData: Data("{}".utf8))
    }

    func refreshRemote() async throws -> RefreshRemoteResponse {
        try await send("/api/refresh", method: "POST", bodyData: Data("{}".utf8))
    }

    func removeSource(id: String) async throws -> RemoveSourceResponse {
        try await send("/api/sources/\(seg(id))", method: "DELETE")
    }

    func saveCollection(
        id: String? = nil,
        name: String,
        members: [CollectionMemberView],
        dedupe: DedupeMode
    ) async throws -> SaveCollectionResponse {
        struct Body: Encodable {
            let id: String?
            let name: String
            let members: [CollectionMemberView]
            let dedupe: DedupeMode
        }
        return try await send(
            "/api/collections",
            method: "POST",
            bodyData: encodeJSON(Body(id: id, name: name, members: members, dedupe: dedupe))
        )
    }

    func removeCollection(id: String) async throws -> OkResponse {
        try await send("/api/collections/\(seg(id))", method: "DELETE")
    }

    func saveProfile(id: String? = nil, entries: [ProfileEntryView], profile: String) async throws -> SaveProfileResponse {
        struct Body: Encodable {
            let id: String
            let name: String
            let entries: [ProfileEntryView]
        }
        return try await send(
            "/api/profiles",
            method: "POST",
            bodyData: encodeJSON(Body(id: id ?? profile, name: profile, entries: entries))
        )
    }

    func createProfile(name: String) async throws -> SaveProfileResponse {
        try await saveProfile(entries: [], profile: name)
    }

    func removeProfile(name: String) async throws -> RemoveProfileResponse {
        try await send("/api/profiles/\(seg(name))", method: "DELETE")
    }

    // MARK: - Policy Groups, Rules, Runtime

    func policyGroups(profile: String) async throws -> PolicyGroupsResponse {
        try await send("/api/policy-groups", query: [("profile", profile)])
    }

    func savePolicyGroups(
        mode: OverlayMode,
        groupIcons: String,
        groups: [GroupView],
        profile: String
    ) async throws -> [String: Int] {
        struct Body: Encodable {
            let mode: OverlayMode
            let groupIcons: String
            let groups: [GroupView]
        }
        return try await send(
            "/api/policy-groups",
            method: "POST",
            query: [("profile", profile)],
            bodyData: encodeJSON(Body(mode: mode, groupIcons: groupIcons, groups: groups))
        )
    }

    func rules(profile: String) async throws -> RulesResponse {
        try await send("/api/rules", query: [("profile", profile)])
    }

    func saveRules(
        rules: [RuleItem],
        mode: OverlayMode,
        placement: String,
        profile: String
    ) async throws -> [String: Int] {
        struct Body: Encodable {
            let rules: [RuleItem]
            let mode: OverlayMode
            let placement: String
        }
        return try await send(
            "/api/rules",
            method: "POST",
            query: [("profile", profile)],
            bodyData: encodeJSON(Body(rules: rules, mode: mode, placement: placement))
        )
    }

    func runtime(profile: String) async throws -> RuntimeResponse {
        try await send("/api/runtime", query: [("profile", profile)])
    }

    func saveRuntime(
        _ runtime: RuntimePolicyView?,
        profile: String,
        dnsMode: OverlayMode? = nil
    ) async throws -> OkResponse {
        struct Body: Encodable {
            let runtime: RuntimePolicyView?
            let dnsMode: OverlayMode?
        }
        return try await send(
            "/api/runtime",
            method: "PUT",
            query: [("profile", profile)],
            bodyData: encodeJSON(Body(runtime: runtime, dnsMode: dnsMode))
        )
    }

    // MARK: - Tokens

    func createToken(target: String, profile: String) async throws -> CreateTokenResponse {
        struct Body: Encodable { let profile: String; let target: String }
        return try await send("/api/tokens", method: "POST", bodyData: encodeJSON(Body(profile: profile, target: target)))
    }

    func revokeToken(id: String) async throws -> OkResponse {
        try await send("/api/tokens/\(seg(id))", method: "DELETE")
    }

    // MARK: - Probe, Geo, Diagnostics, Ops

    func probe(profile: String) async throws -> ProbeResponse {
        struct Body: Encodable { let profile: String }
        return try await send("/api/probe", method: "POST", bodyData: encodeJSON(Body(profile: profile)))
    }

    func geoStatus() async throws -> GeoStatusView {
        try await send("/api/geo/status")
    }

    func updateGeo() async throws -> GeoUpdateResponse {
        try await send("/api/geo/update", method: "POST", bodyData: Data("{}".utf8))
    }

    func diagnostics() async throws -> [HistoryEntry] {
        struct Wrapper: Decodable { let reports: [HistoryEntry] }
        let res: Wrapper = try await send("/api/diagnostics")
        return res.reports
    }

    func buildReport(buildId: String) async throws -> BuildReportView {
        try await send("/api/diagnostics", query: [("buildId", buildId)])
    }

    func capabilities() async throws -> [EvidenceView] {
        struct Wrapper: Decodable { let evidence: [EvidenceView] }
        let res: Wrapper = try await send("/api/capabilities")
        return res.evidence
    }

    func ops() async throws -> OpsView {
        try await send("/api/ops")
    }

    func notifySettings() async throws -> NotifySettingsResponse {
        try await send("/api/settings/notify")
    }

    func saveNotify(_ notify: NotifyConfigView?) async throws -> OkResponse {
        struct Body: Encodable { let notify: NotifyConfigView? }
        return try await send("/api/settings/notify", method: "PUT", bodyData: encodeJSON(Body(notify: notify)))
    }

    func testNotify(_ notify: NotifyConfigView? = nil) async throws -> NotifyTestResponse {
        struct Body: Encodable { let notify: NotifyConfigView? }
        return try await send(
            "/api/settings/notify/test",
            method: "POST",
            bodyData: encodeJSON(Body(notify: notify)),
            softErrorDecoding: true
        )
    }

    func webdavSettings() async throws -> WebDavSettingsResponse {
        try await send("/api/settings/webdav")
    }

    func saveWebdav(_ webdav: WebDavConfigPayload?) async throws -> OkResponse {
        struct Body: Encodable { let webdav: WebDavConfigPayload? }
        return try await send("/api/settings/webdav", method: "PUT", bodyData: encodeJSON(Body(webdav: webdav)))
    }

    func testWebdav(_ webdav: WebDavConfigPayload? = nil) async throws -> WebDavProbeResponse {
        struct Body: Encodable { let webdav: WebDavConfigPayload? }
        return try await send(
            "/api/settings/webdav/test",
            method: "POST",
            bodyData: encodeJSON(Body(webdav: webdav)),
            softErrorDecoding: true
        )
    }

    func fetchDefaults() async throws -> FetchDefaultsResponse {
        try await send("/api/settings/fetch-defaults")
    }

    func saveFetchDefaults(_ defaults: FetchDefaultsView?) async throws -> FetchDefaultsResponse {
        struct Body: Encodable { let defaults: FetchDefaultsView? }
        return try await send("/api/settings/fetch-defaults", method: "PUT", bodyData: encodeJSON(Body(defaults: defaults)))
    }

    func backupLocal() async throws -> BackupResponse {
        try await send("/api/backup", method: "POST", bodyData: Data("{}".utf8))
    }

    func backupRemote() async throws -> RemoteBackupResponse {
        try await send("/api/backup/remote", method: "POST", bodyData: Data("{}".utf8))
    }
}
