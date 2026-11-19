import SwiftUI
import UIKit

enum ClientDialect: String, CaseIterable, Sendable {
    case surgeIni = "surge-ini"
    case clashYaml = "clash-yaml"
    case singBoxJson = "sing-box-json"
    case loonIni = "loon-ini"
    case quanxIni = "quanx-ini"
    case egernYaml = "egern-yaml"
    case uriList = "uri-list"
    case auto = "auto"

    var displayName: String {
        switch self {
        case .surgeIni: return "Surge INI"
        case .clashYaml: return "Clash / mihomo YAML"
        case .singBoxJson: return "sing-box JSON"
        case .loonIni: return "Loon INI"
        case .quanxIni: return "Quantumult X INI"
        case .egernYaml: return "Egern YAML"
        case .uriList: return "节点 URI 列表"
        case .auto: return "UA 自动识别"
        }
    }

    var tint: Color {
        switch self {
        case .surgeIni: return Color(red: 0.23, green: 0.51, blue: 0.96)
        case .clashYaml: return Color(red: 0.08, green: 0.65, blue: 0.56)
        case .singBoxJson: return Color(red: 0.55, green: 0.36, blue: 0.96)
        case .loonIni: return Color(red: 0.96, green: 0.50, blue: 0.14)
        case .quanxIni: return Color(red: 0.90, green: 0.25, blue: 0.45)
        case .egernYaml: return Color(red: 0.18, green: 0.68, blue: 0.38)
        case .uriList: return Color(red: 0.85, green: 0.38, blue: 0.18)
        case .auto: return Color(red: 0.35, green: 0.42, blue: 0.54)
        }
    }
}

enum ClientImportScheme {
    private static let rfc3986Unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func encodeRFC3986(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: rfc3986Unreserved) ?? value
    }

    /// 精确对齐服务端 `src/core/import-url.ts` 的客户端一键导入 Scheme 规则。
    static func importURL(
        target: String,
        subscriptionURL: String,
        name: String = "Startrails",
        revision: String = "1"
    ) -> URL? {
        let trimmed = subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Startrails"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)

        let encodedURL = encodeRFC3986(trimmed)
        let encodedName = encodeRFC3986(displayName)

        let rawScheme: String?
        switch target {
        case "surge":
            rawScheme = "surge:///install-config?url=\(encodedURL)"
        case "surge-mac":
            rawScheme = "surgeconfig:///install-config?url=\(encodedURL)"
        case "clash":
            rawScheme = "stash://install-config?url=\(encodedURL)"
        case "clash-verge":
            rawScheme = "clash-verge://install-config?url=\(encodedURL)"
        case "mihomo-party":
            rawScheme = "mihomo://install-config?url=\(encodedURL)&name=\(encodedName)"
        case "flclash":
            rawScheme = "flclash://install-config?url=\(encodedURL)"
        case "clash-apple":
            rawScheme = "clashmeta://install-config?url=\(encodedURL)"
        case "clash-mi":
            rawScheme = "clashmi://install-config?url=\(encodedURL)&name=\(encodedName)"
        case "karing":
            let rev = revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "1" : revision
            let uniqueURL = appendQuery(trimmed, key: "st-import", value: rev)
            let suffix = String(rev.suffix(6))
            let uniqueName = "\(displayName) \(suffix)"
            rawScheme = "karing://install-config?url=\(encodeRFC3986(uniqueURL))&name=\(encodeRFC3986(uniqueName))"
        case "sing-box":
            rawScheme = "sing-box://import-remote-profile?url=\(encodedURL)#\(encodedName)"
        case "hiddify":
            rawScheme = "hiddify://import/\(trimmed)"
        case "loon":
            rawScheme = "loon://import?sub=\(encodedURL)"
        case "egern":
            rawScheme = "egern:/profiles/new?url=\(encodedURL)&name=\(encodedName)"
        case "shadowrocket":
            rawScheme = "shadowrocket://add/\(trimmed)#\(encodedName)"
        case "v2box":
            rawScheme = "v2box://install-sub?url=\(encodedURL)&name=\(encodedName)"
        case "anywhere":
            rawScheme = "anywhere://add-proxy?link=\(encodedURL)"
        case "quanx", "mihomo", "clashmac", "auto":
            rawScheme = nil
        default:
            rawScheme = nil
        }

        guard let rawScheme else { return nil }
        return URL(string: rawScheme)
    }

    static func hint(for target: String) -> String? {
        switch target {
        case "quanx":
            return "Quantumult X 一键链接只支持节点资源，完整配置请复制订阅地址或导出配置文件导入"
        case "clashmac":
            return "ClashMac 暂无官方 URL Scheme 一键导入，请复制订阅地址手动添加"
        case "mihomo":
            return "通用 mihomo 地址请复制填入客户端；若用 Clash Verge / Clash Party / Clash Mi，可签发对应客户端地址直接一键导入"
        case "auto":
            return "UA 自识别链接用于客户端主动拉取订阅；签发具体客户端地址可启用一键导入"
        default:
            return nil
        }
    }

    static func detectionScheme(for target: String) -> String? {
        switch target {
        case "surge": return "surge://"
        case "surge-mac": return "surgeconfig://"
        case "clash": return "stash://"
        case "clash-apple": return "clashmeta://"
        case "clash-verge": return "clash-verge://"
        case "mihomo-party": return "mihomo://"
        case "flclash": return "flclash://"
        case "clash-mi": return "clashmi://"
        case "karing": return "karing://"
        case "sing-box": return "sing-box://"
        case "hiddify": return "hiddify://"
        case "loon": return "loon://"
        case "quanx": return "quantumult-x://"
        case "egern": return "egern://"
        case "shadowrocket": return "shadowrocket://"
        case "v2box": return "v2box://"
        case "anywhere": return "anywhere://"
        default: return nil
        }
    }

    @MainActor
    static func isInstalled(target: String) -> Bool {
        guard let scheme = detectionScheme(for: target),
              let url = URL(string: scheme) else {
            return false
        }
        return UIApplication.shared.canOpenURL(url)
    }

    static func symbolName(for target: String) -> String {
        switch target {
        case "auto": return "sparkles"
        case "surge", "surge-mac": return "waveform.path.ecg"
        case "clash": return "square.stack.3d.up"
        case "flclash": return "bolt.fill"
        case "mihomo-party": return "flag.fill"
        case "karing": return "diamond"
        case "sing-box", "hiddify": return "shippingbox"
        case "loon": return "balloon"
        case "quanx": return "xmark.circle"
        case "egern": return "leaf.fill"
        case "shadowrocket": return "paperplane.fill"
        case "v2box": return "cube.transparent"
        case "anywhere": return "safari"
        default: return "shield.lefthalf.filled"
        }
    }

    static func dialect(for targetDialect: String, id: String) -> ClientDialect {
        if id == "auto" { return .auto }
        return ClientDialect(rawValue: targetDialect) ?? .clashYaml
    }

    private static func appendQuery(_ rawURL: String, key: String, value: String) -> String {
        if var components = URLComponents(string: rawURL) {
            var items = components.queryItems ?? []
            items.removeAll { $0.name == key }
            items.append(URLQueryItem(name: key, value: value))
            components.queryItems = items
            if let built = components.url?.absoluteString {
                return built
            }
        }
        let sep = rawURL.contains("?") ? "&" : "?"
        return "\(rawURL)\(sep)\(encodeRFC3986(key))=\(encodeRFC3986(value))"
    }
}

/// 对应 Web 控制台 `web/src/client-icons.ts` 的 24×24 线性矢量品牌徽标，
/// 替代泛用 SF Symbols（如避免 Quantumult X 借用关闭符号 `xmark.circle`）。
struct ClientBrandIcon: View {
    let targetId: String
    var dialect: String = ""
    var size: CGFloat = 20
    var tintOverride: Color? = nil
    var isSelected: Bool = false
    var bare: Bool = false

    private var tint: Color {
        if let tintOverride { return tintOverride }
        let resolved = ClientImportScheme.dialect(for: dialect.isEmpty ? defaultDialect(for: targetId) : dialect, id: targetId)
        return resolved.tint
    }

    private func defaultDialect(for id: String) -> String {
        switch id {
        case "auto": return "auto"
        case "surge", "surge-mac": return "surge-ini"
        case "sing-box", "hiddify": return "sing-box-json"
        case "loon": return "loon-ini"
        case "quanx": return "quanx-ini"
        case "egern": return "egern-yaml"
        case "shadowrocket", "v2box", "anywhere": return "uri-list"
        default: return "clash-yaml"
        }
    }

    var body: some View {
        let fg: Color = isSelected ? .white : tint
        ClientGlyphShape(targetId: targetId)
            .stroke(
                fg,
                style: StrokeStyle(
                    lineWidth: max(1.3, size * (bare ? 0.085 : 0.075)),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: size * (bare ? 0.85 : 0.64), height: size * (bare ? 0.85 : 0.64))
            .frame(width: size, height: size)
            .background {
                if !bare {
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.18) : tint.opacity(0.13))
                }
            }
            .overlay {
                if !bare {
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                        .strokeBorder(isSelected ? Color.white.opacity(0.32) : tint.opacity(0.22), lineWidth: 0.7)
                }
            }
    }
}

private struct ClientGlyphShape: Shape {
    let targetId: String

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let ox = rect.midX - side * 0.5
        let oy = rect.midY - side * 0.5
        let s = side / 24.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }
        var p = Path()

        switch targetId {
        case "surge":
            for yOffset in [CGFloat(9), CGFloat(15)] {
                p.move(to: pt(2, yOffset))
                p.addCurve(to: pt(8.6, yOffset), control1: pt(4.2, yOffset - 2.8), control2: pt(6.4, yOffset + 2.8))
                p.addCurve(to: pt(15.2, yOffset), control1: pt(10.8, yOffset - 2.8), control2: pt(13.0, yOffset + 2.8))
                p.addCurve(to: pt(22, yOffset), control1: pt(17.4, yOffset - 2.8), control2: pt(19.6, yOffset + 2.8))
            }
        case "surge-mac":
            p.addRoundedRect(in: CGRect(x: ox + 4 * s, y: oy + 3.5 * s, width: 16 * s, height: 17 * s), cornerSize: CGSize(width: 2 * s, height: 2 * s))
            p.move(to: pt(4, 8))
            p.addLine(to: pt(20, 8))
            p.move(to: pt(7.5, 14))
            p.addCurve(to: pt(12, 14), control1: pt(9, 12.1), control2: pt(10.5, 15.9))
            p.addCurve(to: pt(16.5, 14), control1: pt(13.5, 12.1), control2: pt(15, 15.9))
        case "mihomo":
            // Cat ears & head
            p.move(to: pt(5, 10))
            p.addLine(to: pt(4.5, 4))
            p.addLine(to: pt(9.2, 6.6))
            p.move(to: pt(19, 10))
            p.addLine(to: pt(19.5, 4))
            p.addLine(to: pt(14.8, 6.6))
            p.move(to: pt(4.5, 10.5))
            p.addCurve(to: pt(12, 18), control1: pt(4.5, 14.9), control2: pt(7.9, 18))
            p.addCurve(to: pt(19.5, 10.5), control1: pt(16.1, 18), control2: pt(19.5, 14.9))
            p.addEllipse(in: CGRect(x: ox + 9 * s, y: oy + 12.5 * s, width: 1.0 * s, height: 1.0 * s))
            p.addEllipse(in: CGRect(x: ox + 14 * s, y: oy + 12.5 * s, width: 1.0 * s, height: 1.0 * s))
        case "clash":
            p.addRoundedRect(in: CGRect(x: ox + 3.5 * s, y: oy + 8.5 * s, width: 12 * s, height: 12 * s), cornerSize: CGSize(width: 1.5 * s, height: 1.5 * s))
            p.move(to: pt(8.5, 5.5))
            p.addLine(to: pt(8.5, 3.5))
            p.addLine(to: pt(19.5, 3.5))
            p.addLine(to: pt(19.5, 14.5))
            p.addLine(to: pt(17.5, 14.5))
        case "clash-apple":
            p.addEllipse(in: CGRect(x: ox + 3 * s, y: oy + 3 * s, width: 18 * s, height: 18 * s))
            p.addArc(center: pt(12.2, 12), radius: 4.4 * s, startAngle: .degrees(40), endAngle: .degrees(320), clockwise: false)
        case "clashmac":
            p.addRoundedRect(in: CGRect(x: ox + 4 * s, y: oy + 4 * s, width: 16 * s, height: 16 * s), cornerSize: CGSize(width: 2.5 * s, height: 2.5 * s))
            p.addArc(center: pt(12.2, 12), radius: 4.0 * s, startAngle: .degrees(42), endAngle: .degrees(318), clockwise: false)
        case "clash-verge":
            p.move(to: pt(3.5, 6.5))
            p.addLine(to: pt(12, 19.5))
            p.addLine(to: pt(20.5, 6.5))
            p.move(to: pt(3.5, 6.5))
            p.addLine(to: pt(6.7, 6.5))
            p.move(to: pt(17.3, 6.5))
            p.addLine(to: pt(20.5, 6.5))
        case "flclash":
            p.move(to: pt(13.5, 2.5))
            p.addLine(to: pt(5, 13.5))
            p.addLine(to: pt(10.5, 13.5))
            p.addLine(to: pt(9.5, 21.5))
            p.addLine(to: pt(19, 10.5))
            p.addLine(to: pt(13.5, 10.5))
            p.closeSubpath()
        case "mihomo-party":
            p.move(to: pt(5, 21))
            p.addLine(to: pt(5, 3.5))
            p.move(to: pt(5, 4))
            p.addLine(to: pt(18, 4))
            p.addLine(to: pt(15.4, 8))
            p.addLine(to: pt(18, 12))
            p.addLine(to: pt(5, 12))
        case "clash-mi":
            p.move(to: pt(3.5, 18.5))
            p.addLine(to: pt(3.5, 5.5))
            p.addLine(to: pt(7.7, 12.5))
            p.addLine(to: pt(12, 5.5))
            p.addLine(to: pt(16.3, 12.5))
            p.addLine(to: pt(20.5, 5.5))
            p.addLine(to: pt(20.5, 18.5))
        case "karing":
            p.move(to: pt(12, 2.5))
            p.addLine(to: pt(21.5, 12))
            p.addLine(to: pt(12, 21.5))
            p.addLine(to: pt(2.5, 12))
            p.closeSubpath()
            p.move(to: pt(12, 8.5))
            p.addLine(to: pt(12, 15.5))
            p.move(to: pt(8.5, 12))
            p.addLine(to: pt(15.5, 12))
        case "sing-box":
            p.move(to: pt(12, 2.8))
            p.addLine(to: pt(20.5, 7.5))
            p.addLine(to: pt(20.5, 16.5))
            p.addLine(to: pt(12, 21.2))
            p.addLine(to: pt(3.5, 16.5))
            p.addLine(to: pt(3.5, 7.5))
            p.closeSubpath()
            p.move(to: pt(3.5, 7.5))
            p.addLine(to: pt(12, 12.2))
            p.addLine(to: pt(20.5, 7.5))
            p.move(to: pt(12, 12.2))
            p.addLine(to: pt(12, 21.2))
        case "hiddify":
            p.move(to: pt(2.5, 12))
            p.addQuadCurve(to: pt(21.5, 12), control: pt(12, 5))
            p.addQuadCurve(to: pt(2.5, 12), control: pt(12, 19))
            p.addEllipse(in: CGRect(x: ox + 9.2 * s, y: oy + 9.2 * s, width: 5.6 * s, height: 5.6 * s))
            p.move(to: pt(4, 20))
            p.addLine(to: pt(20, 4))
        case "loon":
            p.addEllipse(in: CGRect(x: ox + 5.6 * s, y: oy + 2.8 * s, width: 12.8 * s, height: 13.6 * s))
            p.move(to: pt(12, 16.4))
            p.addLine(to: pt(12, 21.2))
            p.move(to: pt(9.5, 21.2))
            p.addLine(to: pt(14.5, 21.2))
        case "quanx":
            p.addEllipse(in: CGRect(x: ox + 2.5 * s, y: oy + 2.5 * s, width: 19 * s, height: 19 * s))
            p.move(to: pt(7.8, 7.8))
            p.addLine(to: pt(16.2, 16.2))
            p.move(to: pt(16.2, 7.8))
            p.addLine(to: pt(7.8, 16.2))
        case "egern":
            p.move(to: pt(4.5, 20))
            p.addCurve(to: pt(20, 4), control1: pt(4.5, 11), control2: pt(9.5, 4.8))
            p.addCurve(to: pt(4.5, 20), control1: pt(19.4, 14.2), control2: pt(14, 19.5))
            p.move(to: pt(4.5, 20))
            p.addQuadCurve(to: pt(15.5, 11), control: pt(8.5, 15.5))
        case "shadowrocket":
            p.move(to: pt(12, 2.5))
            p.addCurve(to: pt(17.4, 13.3), control1: pt(15.4, 5.1), control2: pt(17.4, 9))
            p.addLine(to: pt(15, 16.5))
            p.addLine(to: pt(9, 16.5))
            p.addLine(to: pt(6.6, 13.3))
            p.addCurve(to: pt(12, 2.5), control1: pt(6.6, 9), control2: pt(8.6, 5.1))
            p.move(to: pt(9, 16.5))
            p.addLine(to: pt(6.6, 19))
            p.addLine(to: pt(7, 15))
            p.move(to: pt(15, 16.5))
            p.addLine(to: pt(17.4, 19))
            p.addLine(to: pt(17, 15))
            p.addEllipse(in: CGRect(x: ox + 10.4 * s, y: oy + 9.4 * s, width: 3.2 * s, height: 3.2 * s))
            p.move(to: pt(9.4, 19.4))
            p.addQuadCurve(to: pt(14.6, 19.4), control: pt(12, 22.8))
        case "v2box":
            p.move(to: pt(3.5, 7.5))
            p.addLine(to: pt(12, 3))
            p.addLine(to: pt(20.5, 7.5))
            p.addLine(to: pt(20.5, 16.5))
            p.addLine(to: pt(12, 21))
            p.addLine(to: pt(3.5, 16.5))
            p.closeSubpath()
            p.move(to: pt(8.2, 9.4))
            p.addLine(to: pt(12, 15))
            p.addLine(to: pt(15.8, 9.4))
            p.move(to: pt(12, 15))
            p.addLine(to: pt(12, 21))
        case "anywhere":
            p.addEllipse(in: CGRect(x: ox + 2.5 * s, y: oy + 2.5 * s, width: 19 * s, height: 19 * s))
            p.move(to: pt(15.6, 8.4))
            p.addLine(to: pt(13.5, 13.5))
            p.addLine(to: pt(8.4, 15.6))
            p.addLine(to: pt(10.5, 10.5))
            p.closeSubpath()
        case "auto":
            p.move(to: pt(12, 2.5))
            p.addLine(to: pt(14, 9.3))
            p.addLine(to: pt(20.8, 12))
            p.addLine(to: pt(14, 14.7))
            p.addLine(to: pt(12, 21.5))
            p.addLine(to: pt(10, 14.7))
            p.addLine(to: pt(3.2, 12))
            p.addLine(to: pt(10, 9.3))
            p.closeSubpath()
        default:
            p.addEllipse(in: CGRect(x: ox + 3 * s, y: oy + 3 * s, width: 18 * s, height: 18 * s))
            p.move(to: pt(12, 8))
            p.addLine(to: pt(12, 16))
            p.move(to: pt(8, 12))
            p.addLine(to: pt(16, 12))
        }

        return p
    }
}
