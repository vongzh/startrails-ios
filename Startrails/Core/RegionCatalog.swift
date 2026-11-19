import Foundation
import SwiftUI
import UIKit

struct RegionMeta: Hashable, Sendable {
    let code: String
    let flag: String
    let shortName: String
    let fullName: String
}

enum RegionCatalog {
    static let order: [String] = ["HK", "TW", "CN", "JP", "KR", "SG", "DE", "UK", "US", "OTHER"]

    static let presets: [String: RegionMeta] = [
        "HK": RegionMeta(code: "HK", flag: "🇭🇰", shortName: "香港", fullName: "中国香港"),
        "TW": RegionMeta(code: "TW", flag: "🇹🇼", shortName: "台湾", fullName: "中国台湾"),
        "JP": RegionMeta(code: "JP", flag: "🇯🇵", shortName: "日本", fullName: "日本"),
        "SG": RegionMeta(code: "SG", flag: "🇸🇬", shortName: "新加坡", fullName: "新加坡"),
        "KR": RegionMeta(code: "KR", flag: "🇰🇷", shortName: "韩国", fullName: "韩国"),
        "CN": RegionMeta(code: "CN", flag: "🇨🇳", shortName: "大陆", fullName: "中国大陆"),
        "DE": RegionMeta(code: "DE", flag: "🇩🇪", shortName: "德国", fullName: "德国"),
        "UK": RegionMeta(code: "UK", flag: "🇬🇧", shortName: "英国", fullName: "英国"),
        "US": RegionMeta(code: "US", flag: "🇺🇸", shortName: "美国", fullName: "美国"),
        "FR": RegionMeta(code: "FR", flag: "🇫🇷", shortName: "法国", fullName: "法国"),
        "NL": RegionMeta(code: "NL", flag: "🇳🇱", shortName: "荷兰", fullName: "荷兰"),
        "CA": RegionMeta(code: "CA", flag: "🇨🇦", shortName: "加拿大", fullName: "加拿大"),
        "AU": RegionMeta(code: "AU", flag: "🇦🇺", shortName: "澳大利亚", fullName: "澳大利亚"),
        "RU": RegionMeta(code: "RU", flag: "🇷🇺", shortName: "俄罗斯", fullName: "俄罗斯"),
        "IN": RegionMeta(code: "IN", flag: "🇮🇳", shortName: "印度", fullName: "印度"),
        "TR": RegionMeta(code: "TR", flag: "🇹🇷", shortName: "土耳其", fullName: "土耳其"),
        "MY": RegionMeta(code: "MY", flag: "🇲🇾", shortName: "马来西亚", fullName: "马来西亚"),
        "TH": RegionMeta(code: "TH", flag: "🇹🇭", shortName: "泰国", fullName: "泰国"),
        "VN": RegionMeta(code: "VN", flag: "🇻🇳", shortName: "越南", fullName: "越南"),
        "PH": RegionMeta(code: "PH", flag: "🇵🇭", shortName: "菲律宾", fullName: "菲律宾"),
        "ID": RegionMeta(code: "ID", flag: "🇮🇩", shortName: "印度尼西亚", fullName: "印度尼西亚"),
        "OTHER": RegionMeta(code: "OTHER", flag: "🌐", shortName: "其他", fullName: "其他地区"),
    ]

    static let pickerCodes: [String] = [
        "HK", "TW", "JP", "SG", "KR", "US", "UK", "DE", "FR", "NL", "CA", "AU", "CN", "IN", "TR", "MY", "TH", "VN", "RU"
    ]

    static func meta(for rawCode: String) -> RegionMeta {
        let code = rawCode.uppercased()
        if let preset = presets[code] {
            return preset
        }
        return RegionMeta(
            code: code,
            flag: flagEmoji(of: code),
            shortName: code,
            fullName: code
        )
    }

    static func flagEmoji(of rawCode: String) -> String {
        let iso = rawCode.uppercased() == "UK" ? "GB" : rawCode.uppercased()
        let scalars = Array(iso.unicodeScalars)
        guard scalars.count == 2,
              scalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else {
            return "🌐"
        }
        let base: UInt32 = 0x1F1E6 - 65
        guard let first = UnicodeScalar(base + scalars[0].value),
              let second = UnicodeScalar(base + scalars[1].value) else {
            return "🌐"
        }
        return String(first) + String(second)
    }

    static func protocolTint(_ kind: String) -> Color {
        switch kind.lowercased() {
        case "vless", "vmess":
            return .blue
        case "trojan":
            return .indigo
        case "ss", "shadowsocks":
            return .teal
        case "hysteria2", "hy2", "tuic":
            return .orange
        case "anytls", "snell":
            return .purple
        case "wireguard", "wg":
            return .red
        default:
            return .secondary
        }
    }

    /// Detect at runtime whether Apple Color Emoji renders the Taiwan flag glyph or suppresses it as a `☒` tofu box (e.g. Mainland CN devices).
    static let canRenderTaiwanFlag: Bool = {
        func raster(_ text: String) -> Data? {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20))
            let img = renderer.image { _ in
                (text as NSString).draw(
                    at: CGPoint(x: 1, y: 1),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 16)]
                )
            }
            return img.pngData()
        }
        guard let tw = raster("🇹🇼"), let missing = raster("🇶🇶") else {
            return true
        }
        return tw != missing
    }()

    static func canRenderFlag(for rawCode: String) -> Bool {
        if rawCode.uppercased() == "TW" {
            return canRenderTaiwanFlag
        }
        return true
    }

    static func displayLabel(for rawCode: String, full: Bool = false) -> String {
        let meta = meta(for: rawCode)
        let title = full ? meta.fullName : meta.shortName
        if canRenderFlag(for: rawCode) {
            return "\(meta.flag) \(title)"
        }
        return "\(meta.code) · \(title)"
    }

    static func regionCode(fromEmoji emoji: String) -> String? {
        let scalars = Array(emoji.unicodeScalars)
        guard scalars.count == 2,
              scalars.allSatisfy({ $0.value >= 0x1F1E6 && $0.value <= 0x1F1FF }),
              let first = UnicodeScalar(scalars[0].value - 0x1F1E6 + 65),
              let second = UnicodeScalar(scalars[1].value - 0x1F1E6 + 65) else {
            return nil
        }
        let iso = String(first) + String(second)
        return iso == "GB" ? "UK" : iso
    }
}
