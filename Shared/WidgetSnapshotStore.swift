import Foundation

enum StartrailsSharedConstants {
    static let appGroupIdentifier = "group.com.vongzh.startrails"
    static let widgetSnapshotKey = "startrails.widget.snapshot.v1"
}

struct WidgetSourceItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let uploadBytes: Double
    let downloadBytes: Double
    let totalBytes: Double
    let expireTimestamp: Double?
    let lastError: String?
    let snapshotStale: Bool

    var usedBytes: Double {
        max(0, uploadBytes + downloadBytes)
    }

    var remainingBytes: Double {
        max(0, totalBytes - usedBytes)
    }

    var usageRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, usedBytes / totalBytes))
    }

    var expireDate: Date? {
        guard let ts = expireTimestamp, ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    var daysRemaining: Int? {
        guard let date = expireDate else { return nil }
        let seconds = date.timeIntervalSinceNow
        return Int(ceil(seconds / 86_400))
    }
}

struct WidgetSnapshot: Codable, Hashable, Sendable {
    let serverName: String
    let profileName: String
    let totalSources: Int
    let totalNodes: Int
    let activeTokens: Int
    let updatedAt: Date
    let sources: [WidgetSourceItem]
}

enum WidgetSnapshotStore {
    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: StartrailsSharedConstants.appGroupIdentifier),
              let data = defaults.data(forKey: StartrailsSharedConstants.widgetSnapshotKey)
        else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: StartrailsSharedConstants.appGroupIdentifier),
              let data = try? JSONEncoder().encode(snapshot)
        else {
            return
        }
        defaults.set(data, forKey: StartrailsSharedConstants.widgetSnapshotKey)
    }

    static func clear() {
        UserDefaults(suiteName: StartrailsSharedConstants.appGroupIdentifier)?
            .removeObject(forKey: StartrailsSharedConstants.widgetSnapshotKey)
    }
}
