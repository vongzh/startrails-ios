import Foundation

// MARK: - Generic JSON Value

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var displayText: String {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let v): return v ? "true" : "false"
        case .array(let v): return v.map(\.displayText).joined(separator: ", ")
        case .object(let v):
            return v.map { "\($0.key)=\($0.value.displayText)" }.sorted().joined(separator: ", ")
        case .null: return "null"
        }
    }
}

// MARK: - Setup & Health

struct SetupStatusResponse: Codable, Sendable {
    let required: Bool
    let secretRequired: Bool
}

struct HealthResponse: Codable, Sendable {
    let ok: Bool
    let version: String
    let coreVersion: String
}

struct OkResponse: Codable, Sendable {
    let ok: Bool
}

// MARK: - Sources, Collections, Profiles

enum SourceKind: String, Codable, CaseIterable, Sendable {
    case remote
    case file
    case inline

    var label: String {
        switch self {
        case .remote: return "远程订阅"
        case .file: return "文件导入"
        case .inline: return "内联节点"
        }
    }
}

struct SourceUserinfoView: Codable, Hashable, Sendable {
    let upload: Double?
    let download: Double?
    let total: Double?
    let expire: Double?
}

struct SourceView: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: SourceKind
    let enabled: Bool
    let url: String?
    let format: String?
    let ua: String?
    let refreshPolicy: String?
    let refreshIntervalMs: Double?
    let proxy: String?
    let lastFetchedAt: String?
    let lastError: String?
    let snapshotAgeMs: Double?
    let snapshotStale: Bool
    let userinfo: SourceUserinfoView?
    let suggestedRefreshHours: Double?
    let bytes: Int
    let updatedAt: String?
}

struct SourceInputPayload: Codable, Sendable {
    let kind: SourceKind
    var name: String?
    var url: String?
    var content: String?
    var format: String?
    var ua: String?
    var refreshPolicy: String?
    var proxy: String?
    var profile: String?
    var enabled: Bool?
}

struct AddSourceResponse: Codable, Sendable {
    let id: String
    let name: String
    let kind: SourceKind
    let url: String?
    let attached: Bool
}

struct SourceDetailResponse: Codable, Sendable {
    let source: SourceView
    let content: String?
}

struct RefreshSourceResponse: Codable, Sendable {
    let refreshed: Int
    let failed: Int
    let lastError: String?
    let lastFetchedAt: String?
}

struct RefreshRemoteResponse: Codable, Sendable {
    let refreshed: Int
    let failed: Int
}

struct DetachView: Codable, Sendable {
    let collections: Int
    let profiles: Int
    let removedCollections: [String]?
}

struct RemoveSourceResponse: Codable, Sendable {
    let ok: Bool
    let detached: DetachView
}

enum ProcessStep: Codable, Hashable, Sendable, Identifiable {
    case filter(by: String, keep: Bool, value: [String]?)
    case rename(template: String)
    case prefix(value: String)
    case sort(by: String, order: String)
    case dedupe(strategy: String)
    case limit(count: Int)
    case setProperty(key: String, value: JSONValue)
    case flag(value: String)

    var id: String {
        switch self {
        case .filter(let by, let keep, let value):
            return "filter:\(by):\(keep):\(value?.joined(separator: ",") ?? "")"
        case .rename(let template): return "rename:\(template)"
        case .prefix(let value): return "prefix:\(value)"
        case .sort(let by, let order): return "sort:\(by):\(order)"
        case .dedupe(let strategy): return "dedupe:\(strategy)"
        case .limit(let count): return "limit:\(count)"
        case .setProperty(let key, let value): return "prop:\(key):\(value.displayText)"
        case .flag(let value): return "flag:\(value)"
        }
    }

    var summaryText: String {
        switch self {
        case .filter(let by, let keep, let value):
            let verb = keep ? "保留" : "排除"
            let detail = value?.joined(separator: ", ") ?? ""
            return detail.isEmpty ? "\(verb) [\(by)]" : "\(verb) [\(by)]: \(detail)"
        case .rename(let template): return "重命名: \(template)"
        case .prefix(let value): return "前缀: \(value)"
        case .sort(let by, let order): return "排序: \(by) (\(order))"
        case .dedupe(let strategy): return "去重: \(strategy)"
        case .limit(let count): return "限制前 \(count) 节点"
        case .setProperty(let key, let value): return "设属性 \(key) = \(value.displayText)"
        case .flag(let value): return "国旗: \(value)"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, by, keep, value, template, order, strategy, count, key
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "filter":
            let by = try c.decode(String.self, forKey: .by)
            let keep = try c.decodeIfPresent(Bool.self, forKey: .keep) ?? true
            let value = try c.decodeIfPresent([String].self, forKey: .value)
            self = .filter(by: by, keep: keep, value: value)
        case "rename":
            self = .rename(template: try c.decode(String.self, forKey: .template))
        case "prefix":
            self = .prefix(value: try c.decode(String.self, forKey: .value))
        case "sort":
            let by = try c.decode(String.self, forKey: .by)
            let order = try c.decodeIfPresent(String.self, forKey: .order) ?? "asc"
            self = .sort(by: by, order: order)
        case "dedupe":
            self = .dedupe(strategy: try c.decode(String.self, forKey: .strategy))
        case "limit":
            self = .limit(count: try c.decode(Int.self, forKey: .count))
        case "set-property":
            let key = try c.decode(String.self, forKey: .key)
            let value = try c.decode(JSONValue.self, forKey: .value)
            self = .setProperty(key: key, value: value)
        case "flag":
            self = .flag(value: try c.decode(String.self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown process type \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .filter(let by, let keep, let value):
            try c.encode("filter", forKey: .type)
            try c.encode(by, forKey: .by)
            try c.encode(keep, forKey: .keep)
            try c.encodeIfPresent(value, forKey: .value)
        case .rename(let template):
            try c.encode("rename", forKey: .type)
            try c.encode(template, forKey: .template)
        case .prefix(let value):
            try c.encode("prefix", forKey: .type)
            try c.encode(value, forKey: .value)
        case .sort(let by, let order):
            try c.encode("sort", forKey: .type)
            try c.encode(by, forKey: .by)
            try c.encode(order, forKey: .order)
        case .dedupe(let strategy):
            try c.encode("dedupe", forKey: .type)
            try c.encode(strategy, forKey: .strategy)
        case .limit(let count):
            try c.encode("limit", forKey: .type)
            try c.encode(count, forKey: .count)
        case .setProperty(let key, let value):
            try c.encode("set-property", forKey: .type)
            try c.encode(key, forKey: .key)
            try c.encode(value, forKey: .value)
        case .flag(let value):
            try c.encode("flag", forKey: .type)
            try c.encode(value, forKey: .value)
        }
    }
}

struct MemberFilterView: Codable, Hashable, Sendable {
    var enabled: Bool?
    var prefix: String?
    var include: [String]?
    var exclude: [String]?
    var limit: Int?
    var rename: String?
    var process: [ProcessStep]?
}

struct CollectionMemberView: Codable, Hashable, Sendable, Identifiable {
    var sourceId: String
    var filter: MemberFilterView?

    var id: String { sourceId }
}

enum DedupeMode: String, Codable, CaseIterable, Sendable {
    case nodeKey
    case name
    case none

    var label: String {
        switch self {
        case .nodeKey: return "按指纹去重"
        case .name: return "按名称去重"
        case .none: return "不去重"
        }
    }
}

struct CollectionView: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var members: [CollectionMemberView]
    var dedupe: DedupeMode
    var order: Int
    var previewCount: Int?
}

struct ProfileEntryView: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case source
        case collection
    }
    var kind: Kind
    var id: String
}

struct ProfileView: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var entries: [ProfileEntryView]
}

struct SaveProfileResponse: Codable, Sendable {
    let name: String
    let id: String
    let created: Bool
    let renamed: Bool?
}

struct SaveCollectionResponse: Codable, Sendable {
    let id: String
    let name: String
    let members: Int
}

struct RemoveProfileResponse: Codable, Sendable {
    struct DetachedCounts: Codable, Sendable {
        let rules: Int
        let annotations: Int
        let groupOverrides: Int
    }
    let ok: Bool
    let detached: DetachedCounts
    let revoked: Int
}

// MARK: - Nodes & Annotations

struct AnnotationView: Codable, Hashable, Sendable {
    let nodeKey: String
    var excluded: Bool?
    var alias: String?
    var tag: String?
    var order: Int?
    var region: String?
}

enum TransformAction: String, Codable, CaseIterable, Sendable {
    case exclude
    case keep
    case rename

    var label: String {
        switch self {
        case .exclude: return "移除匹配"
        case .keep: return "仅保留匹配"
        case .rename: return "批量改名"
        }
    }
}

struct NodeTransformView: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var order: Int
    var pattern: String
    var action: TransformAction
    var replacement: String?
}

struct NodeTransformsResponse: Codable, Sendable {
    let transforms: [NodeTransformView]
}

struct NodeGeoView: Codable, Hashable, Sendable {
    let country: String?
    let asn: Int?
    let org: String?
    let source: String?
    let conflict: Bool?
}

struct NodeView: Codable, Identifiable, Hashable, Sendable {
    let nodeKey: String
    let kind: String
    let name: String
    let address: String
    let options: [String: JSONValue]?
    let sources: [String]
    let geo: NodeGeoView?

    var id: String { nodeKey }

    var host: String {
        // Handle IPv6 `[host]:port` or `host:port`
        if address.hasPrefix("["), let close = address.lastIndex(of: "]") {
            return String(address[address.index(after: address.startIndex)..<close])
        }
        guard let lastColon = address.lastIndex(of: ":") else { return address }
        return String(address[..<lastColon])
    }

    var port: Int {
        guard let lastColon = address.lastIndex(of: ":") else { return 443 }
        return Int(address[address.index(after: lastColon)...]) ?? 443
    }
}

struct DiagnosticView: Codable, Hashable, Sendable, Identifiable {
    let stage: String
    let target: String?
    let subject: String
    let reason: String

    var id: String { "\(stage)|\(target ?? "")|\(subject)|\(reason)" }
}

struct SourceStatView: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let enabled: Bool
    let format: String?
    let nodes: Int
    let skipped: Int
    let sample: [String]
    let bytes: Int?
    let diagnostics: [DiagnosticView]
}

struct NodesResponse: Codable, Sendable {
    let nodes: [NodeView]
    let diagnostics: [DiagnosticView]
    let configVersion: String
}

// MARK: - Tokens & Targets

struct TokenView: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let profile: String
    let target: String
    let revoked: Bool
    let createdAt: String
    let url: String?
}

struct ClientTargetView: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let dialect: String
    let fileExtension: String
    let contentMode: String
    let basis: String
    let independentEvidence: Bool
}

struct CreateTokenResponse: Codable, Sendable {
    let id: String
    let url: String
    let token: String
    let target: String
    let profile: String
}

// MARK: - Full Workspace State

struct StateView: Codable, Sendable {
    let version: String
    let coreVersion: String
    let sources: [SourceView]
    let collections: [CollectionView]
    let profiles: [ProfileView]
    let annotations: [AnnotationView]
    let tokens: [TokenView]
    let targets: [String]
    let sourceFormats: [String]
    let clientTargets: [ClientTargetView]
}

// MARK: - Preview & Trace & Diagnostics

struct TraceDiffView: Codable, Hashable, Sendable {
    let kind: String
    let ref: String
    let detail: String
}

struct TraceStepView: Codable, Hashable, Sendable {
    let index: Int
    let diff: [TraceDiffView]
    let diagnostics: [DiagnosticView]
    let nodesBefore: Int
    let nodesAfter: Int
}

struct PreviewView: Codable, Sendable {
    struct TraceWrapper: Codable, Sendable {
        let steps: [TraceStepView]
    }
    struct ReportWrapper: Codable, Sendable {
        let skipped: Int
        let passed: Int
        let diagnostics: [DiagnosticView]
    }
    let target: String
    let filename: String
    let content: String
    let trace: TraceWrapper
    let report: ReportWrapper
}

struct HistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let buildId: String
    let target: String
    let createdAt: String
    let skipped: Int
    let passed: Int

    var id: String { buildId }
}

struct BuildReportView: Codable, Sendable {
    struct InnerReport: Codable, Sendable {
        let skipped: Int
        let passed: Int
        let diagnostics: [DiagnosticView]
    }
    let buildId: String
    let target: String
    let createdAt: String
    let report: InnerReport
}

struct EvidenceView: Codable, Hashable, Sendable, Identifiable {
    let target: String
    let scope: String
    let subject: String
    let value: String
    let source: String
    let note: String

    var id: String { "\(target)|\(scope)|\(subject)" }
}

// MARK: - Policy Groups, Rules, Runtime (DNS / TUN)

enum OverlayMode: String, Codable, CaseIterable, Sendable {
    case inherit
    case replace
    case merge

    var label: String {
        switch self {
        case .inherit: return "自动继承"
        case .replace: return "完全覆盖"
        case .merge: return "合并增强"
        }
    }
}

enum GroupMemberItem: Codable, Hashable, Sendable, Identifiable {
    case ref(String)
    case match(String)
    case region(String)
    case rest

    var id: String {
        switch self {
        case .ref(let name): return "ref:\(name)"
        case .match(let pattern): return "match:\(pattern)"
        case .region(let code): return "region:\(code)"
        case .rest: return "rest"
        }
    }

    var displayLabel: String {
        switch self {
        case .ref(let name): return name
        case .match(let pattern): return "匹配 \(pattern)"
        case .region(let code): return "地区 \(code)"
        case .rest: return "其余节点"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, name, pattern, code
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let str = try? single.decode(String.self) {
            self = .ref(str)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "ref":
            self = .ref(try c.decode(String.self, forKey: .name))
        case "match":
            self = .match(try c.decode(String.self, forKey: .pattern))
        case "region":
            self = .region(try c.decode(String.self, forKey: .code))
        case "rest":
            self = .rest
        default:
            self = .rest
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ref(let name):
            try c.encode("ref", forKey: .kind)
            try c.encode(name, forKey: .name)
        case .match(let pattern):
            try c.encode("match", forKey: .kind)
            try c.encode(pattern, forKey: .pattern)
        case .region(let code):
            try c.encode("region", forKey: .kind)
            try c.encode(code, forKey: .code)
        case .rest:
            try c.encode("rest", forKey: .kind)
        }
    }
}

enum GroupStrategy: String, Codable, CaseIterable, Sendable {
    case select
    case urlTest = "url-test"
    case fallback

    var label: String {
        switch self {
        case .select: return "手选 (select)"
        case .urlTest: return "测速 (url-test)"
        case .fallback: return "故转 (fallback)"
        }
    }
}

struct GroupView: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var members: [GroupMemberItem]
    var order: Int?
    var strategy: GroupStrategy?
    var testUrl: String?
    var interval: Int?
    var tolerance: Int?
    var lazy: Bool?
    var hidden: Bool?
    var icon: String?

    var id: String { name }
}

struct PolicyGroupBaseView: Codable, Hashable, Sendable, Identifiable {
    let name: String
    let members: [String]
    let strategy: GroupStrategy?
    let testUrl: String?
    let interval: Int?
    let tolerance: Int?
    let lazy: Bool?
    let hidden: Bool?
    let icon: String?

    var id: String { name }
}

struct PolicyGroupsResponse: Codable, Sendable {
    let mode: OverlayMode
    let groupIcons: String // "off" | "auto"
    let groups: [GroupView]
    let base: [PolicyGroupBaseView]
}

final class RuleConditionBox: @unchecked Sendable, Codable, Hashable {
    let type: String
    let value: String?
    let noResolve: Bool?
    let children: [RuleConditionBox]?
    let child: RuleConditionBox?

    init(
        type: String,
        value: String? = nil,
        noResolve: Bool? = nil,
        children: [RuleConditionBox]? = nil,
        child: RuleConditionBox? = nil
    ) {
        self.type = type
        self.value = value
        self.noResolve = noResolve
        self.children = children
        self.child = child
    }

    static func == (lhs: RuleConditionBox, rhs: RuleConditionBox) -> Bool {
        lhs.type == rhs.type &&
            lhs.value == rhs.value &&
            lhs.noResolve == rhs.noResolve &&
            lhs.children == rhs.children &&
            lhs.child == rhs.child
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(value)
        hasher.combine(noResolve)
        hasher.combine(children)
        hasher.combine(child)
    }

    var summaryText: String {
        switch type {
        case "domain": return "DOMAIN,\(value ?? "")"
        case "domainSuffix": return "DOMAIN-SUFFIX,\(value ?? "")"
        case "domainKeyword": return "DOMAIN-KEYWORD,\(value ?? "")"
        case "geosite": return "GEOSITE,\(value ?? "")"
        case "geoip": return noResolve == true ? "GEOIP,\(value ?? ""),no-resolve" : "GEOIP,\(value ?? "")"
        case "ipCidr": return noResolve == true ? "IP-CIDR,\(value ?? ""),no-resolve" : "IP-CIDR,\(value ?? "")"
        case "ipCidr6": return noResolve == true ? "IP-CIDR6,\(value ?? ""),no-resolve" : "IP-CIDR6,\(value ?? "")"
        case "match": return "MATCH"
        case "and", "or":
            let inner = (children ?? []).map { "(\($0.summaryText))" }.joined(separator: ",")
            return "\(type.uppercased()),(\(inner))"
        case "not":
            return "NOT,((\(child?.summaryText ?? "")))"
        default:
            let baseType = type.uppercased()
            if let value, !value.isEmpty {
                return noResolve == true ? "\(baseType),\(value),no-resolve" : "\(baseType),\(value)"
            }
            return baseType
        }
    }
}

enum RuleItem: Codable, Hashable, Sendable, Identifiable {
    case inline(condition: RuleConditionBox, policy: String)
    case external(url: String, policy: String, shape: String?, format: String?)
    case final(policy: String)

    var id: String {
        switch self {
        case .inline(let cond, let policy): return "inline:\(cond.summaryText):\(policy)"
        case .external(let url, let policy, let shape, _): return "ext:\(url):\(policy):\(shape ?? "")"
        case .final(let policy): return "final:\(policy)"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, condition, policy, url, shape, format
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "inline"
        switch kind {
        case "final":
            self = .final(policy: try c.decode(String.self, forKey: .policy))
        case "external":
            self = .external(
                url: try c.decode(String.self, forKey: .url),
                policy: try c.decode(String.self, forKey: .policy),
                shape: try c.decodeIfPresent(String.self, forKey: .shape),
                format: try c.decodeIfPresent(String.self, forKey: .format)
            )
        default:
            self = .inline(
                condition: try c.decode(RuleConditionBox.self, forKey: .condition),
                policy: try c.decode(String.self, forKey: .policy)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inline(let condition, let policy):
            try c.encode("inline", forKey: .kind)
            try c.encode(condition, forKey: .condition)
            try c.encode(policy, forKey: .policy)
        case .external(let url, let policy, let shape, let format):
            try c.encode("external", forKey: .kind)
            try c.encode(url, forKey: .url)
            try c.encode(policy, forKey: .policy)
            try c.encodeIfPresent(shape, forKey: .shape)
            try c.encodeIfPresent(format, forKey: .format)
        case .final(let policy):
            try c.encode("final", forKey: .kind)
            try c.encode(policy, forKey: .policy)
        }
    }
}

struct RulesResponse: Codable, Sendable {
    let rules: [RuleItem]
    let mode: OverlayMode
    let placement: String // "before" | "after"
}

struct FallbackFilterView: Codable, Hashable, Sendable {
    var geoip: Bool?
    var geoipCode: String?
    var ipCidr: [String]?
    var domain: [String]?
}

struct DnsPolicyView: Codable, Hashable, Sendable {
    var mode: String // "system" | "fake-ip" | "redir-host"
    var nameserver: [String]?
    var proxyNameserver: [String]?
    var directNameserver: [String]?
    var fallback: [String]?
    var nameserverPolicy: [String: String]?
    var ecs: String?
    var fakeIpRange: String?
    var ipv6: Bool?
    var defaultNameserver: [String]?
    var fallbackFilter: FallbackFilterView?
    var fakeIpFilter: [String]?
    var useHosts: Bool?
    var useSystemHosts: Bool?
    var respectRules: Bool?
}

struct TunPolicyView: Codable, Hashable, Sendable {
    var enabled: Bool
    var stack: String? // "gvisor" | "system" | "mixed"
    var strictRoute: Bool?
    var mtu: Int?
}

struct RuntimePolicyView: Codable, Hashable, Sendable {
    var dns: DnsPolicyView?
    var tun: TunPolicyView?
}

struct RuntimeCapabilityView: Codable, Hashable, Sendable {
    let dns: String
    let tun: String
    let fakeIp: String
    let ecs: String
    let enhancedMode: String
}

struct RuntimeResponse: Codable, Sendable {
    let runtime: RuntimePolicyView?
    let dnsMode: OverlayMode?
    let targets: [String: RuntimeCapabilityView]
}

// MARK: - Probe & Geo & Ops

struct ProbeSampleView: Codable, Hashable, Sendable {
    let nodeKey: String
    let name: String
    let server: String
    let port: Int
    let latencyMs: Double?
    let error: String?
    let intercepted: Bool
    let applicable: Bool?
}

struct ProbeResponse: Codable, Sendable {
    let note: String
    let samples: [ProbeSampleView]
}

struct GeoCountsView: Codable, Hashable, Sendable {
    let countryV4: Int
    let countryV6: Int
    let asnV4: Int
    let asnV6: Int
}

struct GeoStatusView: Codable, Hashable, Sendable {
    let available: Bool
    let geoDir: String
    let updatedAt: String?
    let source: String
    let counts: GeoCountsView
    let bytes: Int
    let filesPresent: [String]
}

struct GeoUpdateResponse: Codable, Sendable {
    let ok: Bool
    let status: GeoStatusView
}

struct OpsView: Codable, Sendable {
    struct NotifySummary: Codable, Sendable {
        let enabled: Bool
        let channels: [String]
    }
    struct WebDavSummary: Codable, Sendable {
        let configured: Bool
    }
    struct SchedulerSummary: Codable, Sendable {
        let intervalMs: Double
    }
    let notify: NotifySummary
    let webdav: WebDavSummary
    let scheduler: SchedulerSummary
}

struct NotifyConfigView: Codable, Hashable, Sendable {
    var enabled: Bool?
    var botToken: String?
    var chatId: String?
    var barkUrl: String?
}

struct NotifySettingsResponse: Codable, Sendable {
    let value: NotifyConfigView?
    let effective: NotifyConfigView?
}

struct NotifyTestResultView: Codable, Hashable, Sendable {
    let channel: String
    let ok: Bool
    let error: String?
}

struct NotifyTestResponse: Codable, Sendable {
    let ok: Bool?
    let results: [NotifyTestResultView]?
    let error: String?
    let hint: String?
}

struct WebDavConfigPayload: Codable, Sendable {
    var url: String
    var username: String?
    var password: String?
}

struct WebDavSettingsResponse: Codable, Sendable {
    struct ValueSummary: Codable, Sendable {
        let url: String
        let username: String?
        let hasPassword: Bool
    }
    struct EffectiveSummary: Codable, Sendable {
        let url: String
        let hasCredentials: Bool
    }
    let value: ValueSummary?
    let effective: EffectiveSummary?
}

struct WebDavProbeResponse: Codable, Sendable {
    let ok: Bool
    let status: Int
    let reason: String?
    let error: String?
    let hint: String?
}

struct FetchHeaderView: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var value: String
    var id: String { "\(name):\(value)" }
}

struct FetchDefaultsView: Codable, Hashable, Sendable {
    var ua: String?
    var proxy: String?
    var headers: [FetchHeaderView]
}

struct FetchDefaultsResponse: Codable, Sendable {
    let value: FetchDefaultsView?
}

struct BackupResponse: Codable, Sendable {
    let destination: String
}

struct RemoteBackupResponse: Codable, Sendable {
    let ok: Bool
    let remoteUrl: String
    let bytes: Int
    let local: String
}
