import Foundation
import Observation
import SwiftUI
import UIKit
import WidgetKit

enum ProbeEngine: String, CaseIterable, Sendable {
    case localDirect = "local"
    case server = "server"

    var label: String {
        switch self {
        case .localDirect: return "本机直连"
        case .server: return "服务端"
        }
    }
}

enum NodeLatencyStatus: Hashable, Sendable {
    case untested
    case udpOnly
    case intercepted(ms: Int?)
    case unreachable(reason: String?)
    case measured(ms: Int)

    var measuredMs: Int? {
        if case .measured(let ms) = self { return ms }
        return nil
    }

    var sortRank: Int {
        switch self {
        case .measured: return 0
        case .intercepted: return 1
        case .udpOnly: return 2
        case .unreachable: return 3
        case .untested: return 4
        }
    }
}

struct ToastNotice: Equatable, Sendable {
    let id: UUID = UUID()
    let text: String
    let isError: Bool
}

@Observable
@MainActor
final class AppStore {
    let client = APIClient()
    let lockManager = AppLockManager()

    var servers: [ServerConnection] = []
    var activeServerId: String?
    var activeProfile: String = "default"
    var isConnected: Bool = false
    var isBootstrapping: Bool = false
    var isBusy: Bool = false

    // Workspace state
    var workspaceState: StateView?
    var sourceStatsById: [String: SourceStatView] = [:]
    var nodes: [NodeView] = []
    var nodeDiagnostics: [DiagnosticView] = []
    var collections: [CollectionView] = []
    var nodeTransforms: [NodeTransformView] = []
    var policyGroupsResponse: PolicyGroupsResponse?
    var rulesResponse: RulesResponse?
    var runtimeResponse: RuntimeResponse?
    var geoStatus: GeoStatusView?
    var opsStatus: OpsView?
    var healthInfo: HealthResponse?
    var recentBuilds: [HistoryEntry] = []
    var refreshingSourceIds: Set<String> = []

    // Preview & Probe & Clipboard
    var selectedTarget: String = "surge"
    var preview: PreviewView?
    var isLoadingPreview: Bool = false
    var installedTargets: Set<String> = []

    var probeEngine: ProbeEngine = .localDirect
    var isProbing: Bool = false
    var probeProgress: (done: Int, total: Int)?
    var localProbeResults: [String: LocalProbeResult] = [:]
    var serverProbeResults: [String: ProbeSampleView] = [:]
    var probeNote: String?
    var lastProbeAt: Date?

    var clipboardCandidate: ClipboardCandidate?
    var toast: ToastNotice?
    var authFailureReason: String?

    var activeServer: ServerConnection? {
        servers.first(where: { $0.id == activeServerId }) ?? servers.first
    }

    var currentProfileDef: ProfileView? {
        workspaceState?.profiles.first(where: { $0.name == activeProfile })
            ?? workspaceState?.profiles.first
    }

    var annotationByKey: [String: AnnotationView] {
        var map = [String: AnnotationView]()
        for ann in workspaceState?.annotations ?? [] {
            map[ann.nodeKey] = ann
        }
        return map
    }

    init() {
        self.servers = ServerProfileStore.loadServers()
        self.activeServerId = ServerProfileStore.loadActiveServerId() ?? servers.first?.id
    }

    func refreshInstalledClients() {
        var installed = Set<String>()
        let candidateIds = workspaceState?.targets ?? [
            "surge", "surge-mac", "clash", "clash-apple", "clash-verge", "mihomo-party",
            "flclash", "clash-mi", "karing", "sing-box", "hiddify", "loon", "quanx",
            "egern", "shadowrocket", "v2box", "anywhere"
        ]
        for targetId in candidateIds {
            if ClientImportScheme.isInstalled(target: targetId) {
                installed.insert(targetId)
            }
        }
        installedTargets = installed
    }

    func bootstrap() async {
        refreshInstalledClients()
        guard let server = activeServer,
              let token = KeychainStore.loadToken(forServerId: server.id),
              !token.isEmpty
        else {
            isConnected = false
            return
        }

        isBootstrapping = true
        defer { isBootstrapping = false }

        if let savedProfile = server.activeProfile, !savedProfile.isEmpty {
            activeProfile = savedProfile
        }

        await client.configure(baseURL: server.baseURL, adminToken: token)
        await reloadAll()
    }

    func connectAndSave(
        name: String,
        baseURL: String,
        adminToken: String,
        existingServerId: String? = nil
    ) async throws {
        let normalizedURL = ServerConnection.normalizeBaseURL(baseURL)
        let trimmedToken = adminToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        await client.configure(baseURL: normalizedURL, adminToken: trimmedToken)
        let state = try await client.state(profile: nil)
        let health = try? await client.health()

        let serverId = existingServerId ?? UUID().uuidString
        let resolvedName = trimmedName.isEmpty ? (URL(string: normalizedURL)?.host ?? "Startrails") : trimmedName
        let firstProfile = state.profiles.first?.name ?? "default"

        let connection = ServerConnection(
            id: serverId,
            name: resolvedName,
            baseURL: normalizedURL,
            activeProfile: firstProfile
        )

        KeychainStore.saveToken(trimmedToken, forServerId: serverId)
        if let idx = servers.firstIndex(where: { $0.id == serverId }) {
            servers[idx] = connection
        } else {
            servers.append(connection)
        }
        activeServerId = serverId
        activeProfile = firstProfile
        ServerProfileStore.saveServers(servers)
        ServerProfileStore.saveActiveServerId(serverId)

        self.workspaceState = state
        self.healthInfo = health
        self.isConnected = true
        self.authFailureReason = nil
        refreshInstalledClients()
        await reloadProfileDetails()
        syncWidgetSnapshot()
        Haptics.notify(.success)
    }

    func switchServer(_ server: ServerConnection) async {
        guard let token = KeychainStore.loadToken(forServerId: server.id), !token.isEmpty else {
            activeServerId = server.id
            ServerProfileStore.saveActiveServerId(server.id)
            isConnected = false
            authFailureReason = "该实例尚未保存管理令牌"
            return
        }
        activeServerId = server.id
        activeProfile = server.activeProfile ?? "default"
        ServerProfileStore.saveActiveServerId(server.id)
        localProbeResults = [:]
        serverProbeResults = [:]
        lastProbeAt = nil
        recentBuilds = []
        preview = nil
        await client.configure(baseURL: server.baseURL, adminToken: token)
        await reloadAll()
    }

    func removeServer(_ server: ServerConnection) {
        KeychainStore.deleteToken(forServerId: server.id)
        servers.removeAll { $0.id == server.id }
        ServerProfileStore.saveServers(servers)
        if activeServerId == server.id {
            activeServerId = servers.first?.id
            ServerProfileStore.saveActiveServerId(activeServerId)
            workspaceState = nil
            nodes = []
            isConnected = false
            WidgetSnapshotStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
            Task { await bootstrap() }
        }
    }

    func signOutCurrentServer() {
        if let id = activeServerId {
            KeychainStore.deleteToken(forServerId: id)
        }
        isConnected = false
        workspaceState = nil
        nodes = []
        preview = nil
        authFailureReason = nil
    }

    func switchProfile(_ name: String) async {
        guard name != activeProfile else { return }
        activeProfile = name
        if let id = activeServerId, let idx = servers.firstIndex(where: { $0.id == id }) {
            servers[idx].activeProfile = name
            ServerProfileStore.saveServers(servers)
        }
        preview = nil
        localProbeResults = [:]
        serverProbeResults = [:]
        lastProbeAt = nil
        await reloadAll()
    }

    func reloadAll() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let state = try await client.state(profile: activeProfile)
            self.workspaceState = state
            if !state.profiles.contains(where: { $0.name == activeProfile }),
               let fallback = state.profiles.first?.name {
                activeProfile = fallback
            }
            self.collections = state.collections
            self.healthInfo = try? await client.health()
            self.isConnected = true
            self.authFailureReason = nil
            await reloadProfileDetails()
            syncWidgetSnapshot()
            checkClipboard()
        } catch let error as APIError where error.isUnauthorized {
            self.authFailureReason = error.localizedDescription
            self.isConnected = false
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    func reloadProfileDetails() async {
        async let nodesTask = client.nodes(profile: activeProfile)
        async let inspectTask = client.inspectSources()
        async let transformsTask = client.nodeTransforms(profile: activeProfile)
        async let groupsTask = client.policyGroups(profile: activeProfile)
        async let rulesTask = client.rules(profile: activeProfile)
        async let runtimeTask = client.runtime(profile: activeProfile)
        async let geoTask = client.geoStatus()
        async let opsTask = client.ops()
        async let historyTask = client.diagnostics()

        if let res = try? await nodesTask {
            self.nodes = res.nodes
            self.nodeDiagnostics = res.diagnostics
        }
        if let stats = try? await inspectTask {
            self.sourceStatsById = Dictionary(uniqueKeysWithValues: stats.map { ($0.id, $0) })
        }
        if let res = try? await transformsTask {
            self.nodeTransforms = res.transforms
        }
        if let res = try? await groupsTask {
            self.policyGroupsResponse = res
        }
        if let res = try? await rulesTask {
            self.rulesResponse = res
        }
        if let res = try? await runtimeTask {
            self.runtimeResponse = res
        }
        if let res = try? await geoTask {
            self.geoStatus = res
        }
        if let res = try? await opsTask {
            self.opsStatus = res
        }
        if let builds = try? await historyTask {
            self.recentBuilds = builds
        }
    }

    func renameActiveProfile(to nextName: String) async {
        let trimmed = nextName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != activeProfile, let current = currentProfileDef else { return }
        do {
            _ = try await client.saveProfile(id: current.id, entries: current.entries, profile: trimmed)
            activeProfile = trimmed
            if let id = activeServerId, let idx = servers.firstIndex(where: { $0.id == id }) {
                servers[idx].activeProfile = trimmed
                ServerProfileStore.saveServers(servers)
            }
            await reloadAll()
            showToast("已重命名为「\(trimmed)」")
            Haptics.notify(.success)
        } catch {
            handleError(error)
        }
    }

    func deleteActiveProfile() async {
        let targetName = activeProfile
        do {
            let res = try await client.removeProfile(name: targetName)
            let state = try await client.state(profile: nil)
            self.workspaceState = state
            self.activeProfile = state.profiles.first?.name ?? "default"
            if let id = activeServerId, let idx = servers.firstIndex(where: { $0.id == id }) {
                servers[idx].activeProfile = activeProfile
                ServerProfileStore.saveServers(servers)
            }
            await reloadAll()
            showToast("已删除配置「\(targetName)」（吊销 \(res.revoked) 条订阅地址）")
            Haptics.notify(.success)
        } catch {
            handleError(error)
        }
    }

    func saveNodeOrder(_ orderedNodes: [NodeView]) async {
        do {
            let currentAnnotations = annotationByKey
            for (index, node) in orderedNodes.enumerated() {
                let existing = currentAnnotations[node.nodeKey]
                if existing?.order == index { continue }
                var next = existing ?? AnnotationView(nodeKey: node.nodeKey)
                next.order = index
                _ = try await client.saveAnnotation(next, profile: activeProfile)
            }
            await reloadAll()
            showToast("节点排序已保存")
            Haptics.notify(.success)
        } catch {
            handleError(error)
        }
    }

    func refreshAllRemoteSources() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let outcome = try await client.refreshRemote()
            await reloadAll()
            showToast("已刷新 \(outcome.refreshed) 个订阅源" + (outcome.failed > 0 ? "（\(outcome.failed) 失败）" : ""))
            Haptics.notify(outcome.failed > 0 ? .warning : .success)
        } catch {
            handleError(error)
        }
    }

    func refreshSingleSource(_ id: String) async {
        refreshingSourceIds.insert(id)
        defer { refreshingSourceIds.remove(id) }
        do {
            let outcome = try await client.refreshSource(id: id)
            await reloadAll()
            if let err = outcome.lastError, !err.isEmpty {
                showToast("刷新失败：\(err)", isError: true)
            } else {
                showToast("订阅源已更新")
                Haptics.notify(.success)
            }
        } catch {
            handleError(error)
        }
    }

    func runProbe(engine: ProbeEngine) async {
        guard !isProbing else { return }
        probeEngine = engine
        isProbing = true
        defer {
            isProbing = false
            probeProgress = nil
        }

        switch engine {
        case .localDirect:
            probeNote = "本机直连 TCP 握手探测（本机 -> 节点 server:port），不经过现有代理通道"
            let targetCount = min(nodes.count, 200)
            probeProgress = targetCount > 0 ? (0, targetCount) : nil
            localProbeResults = [:]
            let results = await LocalProbeService.probeAll(nodes) { [weak self] result, done, total in
                self?.localProbeResults[result.nodeKey] = result
                self?.probeProgress = (done, total)
            }
            localProbeResults = results
            lastProbeAt = Date()
            Haptics.impact(.medium)
        case .server:
            do {
                let res = try await client.probe(profile: activeProfile)
                probeNote = res.note
                var map = [String: ProbeSampleView]()
                for sample in res.samples {
                    map[sample.nodeKey] = sample
                }
                serverProbeResults = map
                lastProbeAt = Date()
                Haptics.impact(.medium)
            } catch {
                handleError(error)
            }
        }
    }

    func probeSingleNode(_ node: NodeView) async {
        probeEngine = .localDirect
        let result = await LocalProbeService.probeNode(node)
        localProbeResults[node.nodeKey] = result
        lastProbeAt = Date()
        Haptics.impact(.light)
        if let ms = result.latencyMs {
            showToast("\(effectiveName(for: node)) · \(ms) ms")
        } else if !result.applicable {
            showToast("\(effectiveName(for: node)) · 纯 UDP 协议")
        } else {
            showToast("\(effectiveName(for: node)) · \(result.error ?? "不可达")", isError: true)
        }
    }

    func latencyStatus(for nodeKey: String) -> NodeLatencyStatus {
        switch probeEngine {
        case .localDirect:
            guard let res = localProbeResults[nodeKey] else { return .untested }
            if !res.applicable { return .udpOnly }
            if let ms = res.latencyMs { return .measured(ms: ms) }
            return .unreachable(reason: res.error)
        case .server:
            guard let sample = serverProbeResults[nodeKey] else { return .untested }
            if sample.applicable == false { return .udpOnly }
            if sample.intercepted {
                return .intercepted(ms: sample.latencyMs.map { Int($0.rounded()) })
            }
            if let ms = sample.latencyMs {
                return .measured(ms: Int(ms.rounded()))
            }
            return .unreachable(reason: sample.error)
        }
    }

    func latency(for nodeKey: String) -> Int? {
        latencyStatus(for: nodeKey).measuredMs
    }

    var hasProbeData: Bool {
        switch probeEngine {
        case .localDirect: return !localProbeResults.isEmpty
        case .server: return !serverProbeResults.isEmpty
        }
    }

    func clearProbeResults() {
        switch probeEngine {
        case .localDirect: localProbeResults = [:]
        case .server: serverProbeResults = [:]
        }
        probeNote = nil
        lastProbeAt = nil
    }

    func effectiveRegion(for node: NodeView) -> String {
        if let manual = annotationByKey[node.nodeKey]?.region, !manual.isEmpty {
            return manual.uppercased()
        }
        if let country = node.geo?.country, !country.isEmpty {
            return country.uppercased()
        }
        return "OTHER"
    }

    func effectiveName(for node: NodeView) -> String {
        if let alias = annotationByKey[node.nodeKey]?.alias, !alias.isEmpty {
            return alias
        }
        return node.name
    }

    func isExcluded(_ nodeKey: String) -> Bool {
        annotationByKey[nodeKey]?.excluded == true
    }

    func saveAnnotation(_ annotation: AnnotationView) async {
        do {
            _ = try await client.saveAnnotation(annotation, profile: activeProfile)
            await reloadAll()
            Haptics.impact(.light)
        } catch {
            handleError(error)
        }
    }

    func loadPreview(target: String? = nil) async {
        let tgt = target ?? selectedTarget
        selectedTarget = tgt
        isLoadingPreview = true
        defer { isLoadingPreview = false }
        do {
            preview = try await client.preview(target: tgt, profile: activeProfile)
        } catch {
            handleError(error)
        }
    }

    func issueAndOpen(target: String, openInApp: Bool = true) async -> (token: CreateTokenResponse, openedInApp: Bool)? {
        do {
            let issued = try await client.createToken(target: target, profile: activeProfile)
            await reloadAll()
            Haptics.notify(.success)
            var opened = false
            if openInApp,
               let importURL = ClientImportScheme.importURL(
                   target: target,
                   subscriptionURL: issued.url,
                   name: "Startrails · \(activeProfile)",
                   revision: String(Int(Date().timeIntervalSince1970))
               ) {
                opened = await UIApplication.shared.open(importURL)
            }
            return (issued, opened)
        } catch {
            handleError(error)
            return nil
        }
    }

    func checkClipboard() {
        let existingURLs = Set((workspaceState?.sources ?? []).compactMap(\.url))
        clipboardCandidate = ClipboardDetector.detectCandidate(existingSourceURLs: existingURLs)
    }

    func dismissClipboard() {
        if let candidate = clipboardCandidate {
            ClipboardDetector.dismiss(candidate)
        }
        clipboardCandidate = nil
    }

    func showToast(_ text: String, isError: Bool = false) {
        let notice = ToastNotice(text: text, isError: isError)
        toast = notice
        Task {
            try? await Task.sleep(for: .seconds(3.2))
            if toast?.id == notice.id {
                toast = nil
            }
        }
    }

    func handleError(_ error: Error) {
        if let apiErr = error as? APIError, apiErr.isUnauthorized {
            authFailureReason = apiErr.localizedDescription
            isConnected = false
            return
        }
        showToast(error.localizedDescription, isError: true)
        Haptics.notify(.error)
    }

    func syncWidgetSnapshot() {
        guard let state = workspaceState, let server = activeServer else { return }
        let items: [WidgetSourceItem] = state.sources
            .filter { $0.kind == .remote && $0.enabled }
            .sorted { lhs, rhs in
                let lHasInfo = lhs.userinfo != nil
                let rHasInfo = rhs.userinfo != nil
                if lHasInfo != rHasInfo { return lHasInfo }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(6)
            .map { source in
                WidgetSourceItem(
                    id: source.id,
                    name: source.name,
                    uploadBytes: source.userinfo?.upload ?? 0,
                    downloadBytes: source.userinfo?.download ?? 0,
                    totalBytes: source.userinfo?.total ?? 0,
                    expireTimestamp: source.userinfo?.expire,
                    lastError: source.lastError,
                    snapshotStale: source.snapshotStale
                )
            }

        let snapshot = WidgetSnapshot(
            serverName: server.name,
            profileName: activeProfile,
            totalSources: state.sources.count,
            totalNodes: nodes.count,
            activeTokens: state.tokens.filter { $0.profile == activeProfile && !$0.revoked }.count,
            updatedAt: Date(),
            sources: items
        )
        WidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
