import Foundation

struct ServerConnection: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var baseURL: String
    var activeProfile: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: String,
        activeProfile: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = Self.normalizeBaseURL(baseURL)
        self.activeProfile = activeProfile
        self.createdAt = createdAt
    }

    static func normalizeBaseURL(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") {
            text.removeLast()
        }
        if !text.isEmpty,
           !text.lowercased().hasPrefix("http://"),
           !text.lowercased().hasPrefix("https://") {
            text = "https://\(text)"
        }
        return text
    }

    var hostLabel: String {
        URL(string: baseURL)?.host ?? baseURL
    }
}

enum ServerProfileStore {
    private static let serversKey = "startrails.servers.v1"
    private static let activeServerIdKey = "startrails.activeServerId.v1"

    static func loadServers() -> [ServerConnection] {
        guard let data = UserDefaults.standard.data(forKey: serversKey),
              let decoded = try? JSONDecoder().decode([ServerConnection].self, from: data)
        else {
            return []
        }
        return decoded
    }

    static func saveServers(_ servers: [ServerConnection]) {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: serversKey)
    }

    static func loadActiveServerId() -> String? {
        UserDefaults.standard.string(forKey: activeServerIdKey)
    }

    static func saveActiveServerId(_ id: String?) {
        if let id {
            UserDefaults.standard.set(id, forKey: activeServerIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeServerIdKey)
        }
    }
}
