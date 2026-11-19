import CryptoKit
import Foundation
import UIKit

enum ClipboardCandidate: Equatable, Sendable {
    case remoteSubscription(url: String, digest: String)
    case inlineProxies(content: String, lineCount: Int, digest: String)

    var digest: String {
        switch self {
        case .remoteSubscription(_, let digest): return digest
        case .inlineProxies(_, _, let digest): return digest
        }
    }

    var title: String {
        switch self {
        case .remoteSubscription: return "检测到剪贴板订阅链接"
        case .inlineProxies(_, let count, _): return "检测到 \(count) 条代理节点链接"
        }
    }

    var subtitle: String {
        switch self {
        case .remoteSubscription(let url, _): return url
        case .inlineProxies(let content, _, _):
            return content.split(separator: "\n").first.map(String.init) ?? content
        }
    }
}

@MainActor
enum ClipboardDetector {
    private static var dismissedDigests = Set<String>()

    private static let proxySchemes = [
        "vless://", "vmess://", "trojan://", "ss://", "ssr://",
        "hy2://", "hysteria2://", "tuic://", "anytls://", "snell://", "wg://", "socks://", "http2://"
    ]

    static func detectCandidate(existingSourceURLs: Set<String>) -> ClipboardCandidate? {
        guard UIPasteboard.general.hasStrings,
              let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw.count <= 250_000
        else {
            return nil
        }

        let digest = sha256(raw)
        if dismissedDigests.contains(digest) { return nil }

        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count == 1,
           let single = lines.first,
           (single.lowercased().hasPrefix("http://") || single.lowercased().hasPrefix("https://")),
           URL(string: single) != nil,
           !existingSourceURLs.contains(single) {
            return .remoteSubscription(url: single, digest: digest)
        }

        let proxyLines = lines.filter { line in
            let lowered = line.lowercased()
            return proxySchemes.contains(where: { lowered.hasPrefix($0) })
        }
        if !proxyLines.isEmpty {
            return .inlineProxies(
                content: proxyLines.joined(separator: "\n"),
                lineCount: proxyLines.count,
                digest: digest
            )
        }

        return nil
    }

    static func dismiss(_ candidate: ClipboardCandidate) {
        dismissedDigests.insert(candidate.digest)
    }

    private static func sha256(_ text: String) -> String {
        let data = Data(text.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
