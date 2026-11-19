import Foundation
import Network

struct LocalProbeResult: Hashable, Sendable {
    let nodeKey: String
    let latencyMs: Int?
    let error: String?
    let applicable: Bool
}

enum LocalProbeService {
    private static let udpOnlyKinds: Set<String> = ["hysteria2", "hy2", "tuic", "wireguard", "wg"]

    private final class FinishFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    static func probeNode(_ node: NodeView, timeoutSeconds: TimeInterval = 2.0) async -> LocalProbeResult {
        if udpOnlyKinds.contains(node.kind.lowercased()) {
            return LocalProbeResult(
                nodeKey: node.nodeKey,
                latencyMs: nil,
                error: "纯 UDP 协议跳过本机 TCP 握手探测",
                applicable: false
            )
        }
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: node.port)), node.port > 0, !node.host.isEmpty else {
            return LocalProbeResult(nodeKey: node.nodeKey, latencyMs: nil, error: "无效地址", applicable: true)
        }

        let start = CFAbsoluteTimeGetCurrent()
        let host = NWEndpoint.Host(node.host)

        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.vongzh.startrails.probe.\(node.nodeKey.prefix(8))")
            let connection = NWConnection(host: host, port: port, using: .tcp)
            let flag = FinishFlag()

            let workItem = DispatchWorkItem {
                guard flag.claim() else { return }
                connection.cancel()
                continuation.resume(returning: LocalProbeResult(
                    nodeKey: node.nodeKey,
                    latencyMs: nil,
                    error: "超时",
                    applicable: true
                ))
            }
            queue.asyncAfter(deadline: .now() + timeoutSeconds, execute: workItem)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard flag.claim() else { return }
                    workItem.cancel()
                    let elapsedMs = max(1, Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))
                    connection.cancel()
                    continuation.resume(returning: LocalProbeResult(
                        nodeKey: node.nodeKey,
                        latencyMs: elapsedMs,
                        error: nil,
                        applicable: true
                    ))
                case .failed(let error):
                    guard flag.claim() else { return }
                    workItem.cancel()
                    connection.cancel()
                    continuation.resume(returning: LocalProbeResult(
                        nodeKey: node.nodeKey,
                        latencyMs: nil,
                        error: error.localizedDescription,
                        applicable: true
                    ))
                case .waiting(let error):
                    guard flag.claim() else { return }
                    workItem.cancel()
                    connection.cancel()
                    continuation.resume(returning: LocalProbeResult(
                        nodeKey: node.nodeKey,
                        latencyMs: nil,
                        error: error.localizedDescription,
                        applicable: true
                    ))
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }

    static func probeAll(
        _ nodes: [NodeView],
        concurrency: Int = 10,
        onProgress: (@MainActor @Sendable (LocalProbeResult, Int, Int) -> Void)? = nil
    ) async -> [String: LocalProbeResult] {
        var results = [String: LocalProbeResult]()
        let limitedNodes = Array(nodes.prefix(200))
        let total = limitedNodes.count

        await withTaskGroup(of: LocalProbeResult.self) { group in
            var index = 0
            while index < min(concurrency, total) {
                let node = limitedNodes[index]
                group.addTask { await probeNode(node) }
                index += 1
            }

            var completed = 0
            while let result = await group.next() {
                results[result.nodeKey] = result
                completed += 1
                if let onProgress {
                    await onProgress(result, completed, total)
                }
                if index < total {
                    let nextNode = limitedNodes[index]
                    group.addTask { await probeNode(nextNode) }
                    index += 1
                }
            }
        }
        return results
    }
}
