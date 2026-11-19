import SwiftUI
import UIKit

enum Formatters {
    static func bytes(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = value
        var idx = 0
        while v >= 1024 && idx < units.count - 1 {
            v /= 1024
            idx += 1
        }
        return idx == 0 ? "\(Int(v)) B" : String(format: "%.2f %@", v, units[idx])
    }

    static func age(ms: Double?) -> String {
        guard let ms, ms >= 0 else { return "未知" }
        let sec = Int(ms / 1000)
        if sec < 60 { return "\(sec)s" }
        let min = sec / 60
        if min < 60 { return "\(min)m" }
        let hrs = min / 60
        if hrs < 24 { return min % 60 == 0 ? "\(hrs)h" : "\(hrs)h\(min % 60)m" }
        let days = hrs / 24
        return hrs % 24 == 0 ? "\(days)d" : "\(days)d\(hrs % 24)h"
    }

    static func expiryBadge(expireTimestamp: Double?) -> (text: String, tint: Color)? {
        guard let ts = expireTimestamp, ts > 0 else { return nil }
        let date = Date(timeIntervalSince1970: ts)
        let days = Int(ceil(date.timeIntervalSinceNow / 86_400))
        if days < 0 {
            return ("已过期 \(abs(days)) 天", .red)
        } else if days == 0 {
            return ("今日到期", .red)
        } else if days <= 7 {
            return ("剩余 \(days) 天", .orange)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return ("\(formatter.string(from: date)) 到期", .secondary)
        }
    }

    static func isoShort(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "-" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let fmt = RelativeDateTimeFormatter()
            fmt.locale = Locale(identifier: "zh_CN")
            fmt.unitsStyle = .short
            return fmt.localizedString(for: date, relativeTo: Date())
        }
        return String(iso.prefix(16))
    }

    static func latencyColor(_ ms: Int?) -> Color {
        guard let ms else { return .secondary }
        if ms < 100 { return Color(red: 0.22, green: 0.65, blue: 0.36) }
        if ms < 250 { return Color(red: 0.85, green: 0.54, blue: 0.08) }
        return Color(red: 0.85, green: 0.24, blue: 0.20)
    }
}

enum Haptics {
    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    @MainActor
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @MainActor
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

struct SurfaceCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 14
    var accentBorder: Color? = nil

    func body(content: Content) -> some View {
        let strokeColor: Color = accentBorder?.opacity(0.45)
            ?? (colorScheme == .dark ? Color.white.opacity(0.09) : Color(.separator).opacity(0.28))

        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: accentBorder != nil ? 1.1 : 0.6)
            )
    }
}

extension View {
    func surfaceCard(cornerRadius: CGFloat = 16, padding: CGFloat = 14, accentBorder: Color? = nil) -> some View {
        modifier(SurfaceCardModifier(cornerRadius: cornerRadius, padding: padding, accentBorder: accentBorder))
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GradientQuotaBar: View {
    let ratio: Double

    private var clamped: Double {
        min(1.0, max(0.0, ratio))
    }

    private var gradientColors: [Color] {
        if clamped > 0.9 {
            return [Color(red: 0.95, green: 0.42, blue: 0.25), Color(red: 0.88, green: 0.18, blue: 0.28)]
        }
        if clamped > 0.72 {
            return [Color(red: 0.25, green: 0.62, blue: 0.98), Color(red: 0.95, green: 0.60, blue: 0.14)]
        }
        return [Color(red: 0.16, green: 0.74, blue: 0.68), Color(red: 0.22, green: 0.50, blue: 0.98)]
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width * CGFloat(clamped))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                if clamped > 0 {
                    Capsule()
                        .fill(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.height, width))
                        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: clamped)
                }
            }
        }
        .frame(height: 6)
    }
}

struct StarTrailsEmblem: View {
    var size: CGFloat = 78

    // 与 AppIcon V2 / Web BrandMark 同源的收尖双弧星迹矢量点集（48×48 坐标系）
    private static let outerArcPoints: [(CGFloat, CGFloat)] = [
        (38.36, 16.79), (38.72, 17.27), (39.05, 17.77), (39.33, 18.29), (39.58, 18.83), (39.79, 19.38),
        (39.95, 19.95), (40.07, 20.52), (40.15, 21.11), (40.19, 21.71), (40.19, 22.32), (40.15, 22.93),
        (40.06, 23.55), (39.93, 24.17), (39.76, 24.79), (39.55, 25.42), (39.30, 26.04), (39.01, 26.66),
        (38.69, 27.27), (38.32, 27.87), (37.92, 28.47), (37.48, 29.06), (37.01, 29.64), (36.50, 30.20),
        (35.97, 30.75), (35.40, 31.29), (34.80, 31.80), (34.18, 32.30), (33.53, 32.78), (32.85, 33.24),
        (32.16, 33.68), (31.44, 34.10), (30.71, 34.49), (29.96, 34.85), (29.19, 35.19), (28.41, 35.51),
        (27.62, 35.79), (26.82, 36.05), (26.02, 36.28), (25.21, 36.48), (24.40, 36.65), (23.59, 36.79),
        (22.78, 36.89), (21.98, 36.97), (21.18, 37.02), (20.39, 37.03), (19.60, 37.02), (18.84, 36.97),
        (18.08, 36.89), (17.34, 36.78), (16.62, 36.64), (15.92, 36.47), (15.25, 36.27), (14.59, 36.05),
        (13.96, 35.79), (13.36, 35.51), (12.78, 35.20), (12.24, 34.86), (11.72, 34.50), (11.24, 34.11),
        (10.79, 33.70), (10.38, 33.27), (10.00, 32.82), (9.66, 32.34), (9.35, 31.85), (9.09, 31.35),
        (8.86, 30.82), (8.67, 30.28), (8.53, 29.73), (8.42, 29.17), (8.35, 28.60), (8.33, 28.01),
        (8.34, 27.42), (8.40, 26.83), (8.49, 26.23), (8.63, 25.63), (8.80, 25.03), (9.02, 24.42),
        (9.27, 23.82), (9.56, 23.23), (9.89, 22.64), (10.25, 22.05), (10.65, 21.48), (11.08, 20.91),
        (11.55, 20.36), (12.05, 19.82), (12.58, 19.29), (13.14, 18.77), (13.72, 18.28), (14.33, 17.80),
        (14.97, 17.34), (15.63, 16.90), (16.30, 16.48), (17.00, 16.09), (17.72, 15.72), (18.45, 15.37),
        (19.19, 15.05), (18.48, 15.44), (17.78, 15.85), (17.11, 16.29), (16.46, 16.74), (15.83, 17.22),
        (15.23, 17.71), (14.65, 18.22), (14.11, 18.74), (13.59, 19.28), (13.10, 19.83), (12.65, 20.38),
        (12.23, 20.94), (11.85, 21.51), (11.50, 22.08), (11.19, 22.66), (10.91, 23.23), (10.67, 23.79),
        (10.47, 24.36), (10.31, 24.91), (10.19, 25.45), (10.10, 25.99), (10.04, 26.51), (10.02, 27.01),
        (10.04, 27.50), (10.09, 27.97), (10.16, 28.42), (10.27, 28.86), (10.41, 29.27), (10.57, 29.67),
        (10.76, 30.05), (10.97, 30.41), (11.21, 30.76), (11.47, 31.09), (11.76, 31.40), (12.08, 31.70),
        (12.41, 31.99), (12.78, 32.26), (13.17, 32.51), (13.59, 32.75), (14.03, 32.98), (14.50, 33.18),
        (14.99, 33.37), (15.51, 33.53), (16.05, 33.68), (16.61, 33.80), (17.19, 33.90), (17.79, 33.98),
        (18.41, 34.04), (19.05, 34.07), (19.70, 34.07), (20.36, 34.05), (21.04, 34.01), (21.72, 33.94),
        (22.41, 33.84), (23.10, 33.72), (23.79, 33.57), (24.49, 33.40), (25.18, 33.20), (25.87, 32.98),
        (26.55, 32.73), (27.22, 32.46), (27.89, 32.17), (28.54, 31.86), (29.17, 31.53), (29.79, 31.17),
        (30.39, 30.80), (30.97, 30.42), (31.53, 30.02), (32.06, 29.60), (32.57, 29.17), (33.05, 28.74),
        (33.51, 28.29), (33.93, 27.84), (34.33, 27.38), (34.69, 26.92), (35.02, 26.46), (35.32, 26.00),
        (35.59, 25.55), (35.82, 25.10), (36.02, 24.65), (36.19, 24.22), (36.33, 23.80), (36.44, 23.38),
        (36.52, 22.99), (36.57, 22.60), (36.60, 22.23), (36.60, 21.87), (36.58, 21.53), (36.54, 21.20),
        (36.47, 20.87), (36.38, 20.56), (36.34, 20.23), (36.30, 19.87), (36.24, 19.51), (36.17, 19.11),
        (36.20, 18.59),
    ]

    private static let innerArcPoints: [(CGFloat, CGFloat)] = [
        (34.46, 20.46), (34.61, 20.80), (34.75, 21.16), (34.85, 21.52), (34.93, 21.88), (34.99, 22.26),
        (35.02, 22.64), (35.03, 23.02), (35.01, 23.41), (34.97, 23.81), (34.90, 24.20), (34.81, 24.60),
        (34.69, 24.99), (34.55, 25.39), (34.38, 25.78), (34.19, 26.18), (33.98, 26.57), (33.75, 26.95),
        (33.49, 27.33), (33.22, 27.71), (32.92, 28.08), (32.60, 28.44), (32.27, 28.79), (31.91, 29.14),
        (31.54, 29.47), (31.15, 29.79), (30.74, 30.11), (30.32, 30.41), (29.89, 30.70), (29.44, 30.97),
        (28.99, 31.23), (28.52, 31.48), (28.04, 31.71), (27.55, 31.93), (27.05, 32.13), (26.55, 32.31),
        (26.05, 32.48), (25.53, 32.63), (25.02, 32.76), (24.51, 32.88), (23.99, 32.97), (23.47, 33.05),
        (22.96, 33.11), (22.45, 33.15), (21.94, 33.18), (21.44, 33.18), (20.94, 33.17), (20.46, 33.14),
        (19.98, 33.09), (19.51, 33.02), (19.05, 32.93), (18.60, 32.82), (18.16, 32.70), (17.74, 32.56),
        (17.34, 32.41), (16.95, 32.23), (16.57, 32.04), (16.22, 31.84), (15.88, 31.62), (15.56, 31.38),
        (15.25, 31.13), (14.97, 30.87), (14.71, 30.59), (14.48, 30.30), (14.26, 30.00), (14.06, 29.69),
        (13.89, 29.37), (13.74, 29.04), (13.62, 28.70), (13.52, 28.35), (13.44, 27.99), (13.39, 27.63),
        (13.36, 27.26), (13.35, 26.89), (13.37, 26.51), (13.41, 26.14), (13.48, 25.75), (13.57, 25.37),
        (13.69, 24.99), (13.82, 24.61), (13.98, 24.23), (14.17, 23.85), (14.37, 23.47), (14.60, 23.10),
        (14.85, 22.73), (15.12, 22.37), (15.40, 22.01), (15.71, 21.66), (16.04, 21.32), (16.38, 20.99),
        (16.74, 20.67), (17.12, 20.36), (17.51, 20.06), (17.91, 19.77), (18.33, 19.49), (18.77, 19.23),
        (19.21, 18.97), (18.79, 19.26), (18.38, 19.57), (17.99, 19.88), (17.62, 20.21), (17.26, 20.54),
        (16.92, 20.88), (16.60, 21.23), (16.30, 21.59), (16.02, 21.95), (15.76, 22.31), (15.52, 22.68),
        (15.30, 23.05), (15.11, 23.42), (14.93, 23.78), (14.78, 24.15), (14.65, 24.52), (14.54, 24.88),
        (14.46, 25.23), (14.40, 25.58), (14.36, 25.92), (14.34, 26.26), (14.34, 26.58), (14.36, 26.89),
        (14.40, 27.20), (14.46, 27.49), (14.54, 27.77), (14.63, 28.04), (14.75, 28.30), (14.87, 28.55),
        (15.02, 28.79), (15.18, 29.02), (15.35, 29.24), (15.54, 29.45), (15.74, 29.65), (15.96, 29.85),
        (16.20, 30.03), (16.45, 30.20), (16.72, 30.36), (17.00, 30.51), (17.30, 30.65), (17.61, 30.78),
        (17.94, 30.90), (18.28, 31.01), (18.64, 31.10), (19.01, 31.18), (19.39, 31.24), (19.78, 31.29),
        (20.18, 31.33), (20.59, 31.35), (21.01, 31.36), (21.44, 31.35), (21.87, 31.33), (22.31, 31.29),
        (22.76, 31.23), (23.20, 31.16), (23.65, 31.08), (24.10, 30.98), (24.55, 30.86), (24.99, 30.73),
        (25.44, 30.58), (25.88, 30.42), (26.31, 30.25), (26.74, 30.06), (27.16, 29.86), (27.57, 29.65),
        (27.98, 29.42), (28.37, 29.19), (28.75, 28.94), (29.12, 28.69), (29.47, 28.42), (29.81, 28.15),
        (30.13, 27.87), (30.44, 27.58), (30.73, 27.29), (31.00, 27.00), (31.25, 26.70), (31.49, 26.40),
        (31.71, 26.10), (31.90, 25.80), (32.08, 25.50), (32.24, 25.21), (32.38, 24.91), (32.50, 24.62),
        (32.60, 24.34), (32.68, 24.06), (32.74, 23.79), (32.79, 23.53), (32.82, 23.27), (32.83, 23.02),
        (32.83, 22.78), (32.85, 22.54), (32.86, 22.30), (32.87, 22.06), (32.87, 21.81), (32.87, 21.56),
        (32.93, 21.25),
    ]

    private static func makeTrailPath(
        points: [(CGFloat, CGFloat)],
        scale: CGFloat,
        offset: CGPoint
    ) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.0 * scale + offset.x, y: first.1 * scale + offset.y))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.0 * scale + offset.x, y: point.1 * scale + offset.y))
        }
        path.closeSubpath()
        return path
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.157, green: 0.220, blue: 0.408),
                            Color(red: 0.086, green: 0.129, blue: 0.251),
                            Color(red: 0.043, green: 0.067, blue: 0.133),
                        ],
                        startPoint: UnitPoint(x: 0.12, y: 0),
                        endPoint: UnitPoint(x: 0.88, y: 1)
                    )
                )

            Canvas { context, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height
                let side = min(w, h)
                let scale = side * 21.6 / 1024.0
                let offset = CGPoint(x: side * (-12.02 / 1024.0), y: side * (81.99 / 1024.0))

                // 天顶星云光晕与四芒星柔和光圈
                let zenithCenter = CGPoint(x: w * 0.63, y: h * 0.28)
                context.fill(
                    Path(CGRect(x: 0, y: 0, width: w, height: h)),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 0.235, green: 0.341, blue: 0.600).opacity(0.45),
                            Color(red: 0.133, green: 0.200, blue: 0.376).opacity(0.18),
                            Color.clear,
                        ]),
                        center: zenithCenter,
                        startRadius: 0,
                        endRadius: side * 0.60
                    )
                )

                let starCenter = CGPoint(x: 30.44 * scale + offset.x, y: 9.63 * scale + offset.y)
                let haloRadius = side * (195.0 / 1024.0)
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: starCenter.x - haloRadius,
                            y: starCenter.y - haloRadius,
                            width: haloRadius * 2,
                            height: haloRadius * 2
                        )
                    ),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 1.0, green: 0.812, blue: 0.420).opacity(0.44),
                            Color(red: 0.949, green: 0.663, blue: 0.231).opacity(0.15),
                            Color.clear,
                        ]),
                        center: starCenter,
                        startRadius: 0,
                        endRadius: haloRadius
                    )
                )

                // 外主轨（高亮白蓝彗尾渐变）
                let outerPath = Self.makeTrailPath(points: Self.outerArcPoints, scale: scale, offset: offset)
                context.fill(
                    outerPath,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .white, location: 0.0),
                            .init(color: Color(red: 0.933, green: 0.953, blue: 0.988), location: 0.48),
                            .init(color: Color(red: 0.749, green: 0.816, blue: 0.925), location: 1.0),
                        ]),
                        startPoint: CGPoint(x: w * 0.80, y: h * 0.12),
                        endPoint: CGPoint(x: w * 0.18, y: h * 0.88)
                    )
                )

                // 内辅轨（柔和银蓝渐变）
                let innerPath = Self.makeTrailPath(points: Self.innerArcPoints, scale: scale, offset: offset)
                context.fill(
                    innerPath,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 0.765, green: 0.812, blue: 0.902), location: 0.0),
                            .init(color: Color(red: 0.604, green: 0.663, blue: 0.788), location: 0.58),
                            .init(color: Color(red: 0.463, green: 0.529, blue: 0.667), location: 1.0),
                        ]),
                        startPoint: CGPoint(x: w * 0.78, y: h * 0.18),
                        endPoint: CGPoint(x: w * 0.22, y: h * 0.85)
                    )
                )

                // 缺口上方暖琥珀金四芒星（与 SVG 贝塞尔控制点一致）
                let starScale = 1.16 * scale
                var star = Path()
                star.move(to: CGPoint(x: starCenter.x, y: starCenter.y - 5.9 * starScale))
                star.addCurve(
                    to: CGPoint(x: starCenter.x + 5.9 * starScale, y: starCenter.y),
                    control1: CGPoint(x: starCenter.x + 0.77 * starScale, y: starCenter.y - 2.24 * starScale),
                    control2: CGPoint(x: starCenter.x + 2.24 * starScale, y: starCenter.y - 0.77 * starScale)
                )
                star.addCurve(
                    to: CGPoint(x: starCenter.x, y: starCenter.y + 5.9 * starScale),
                    control1: CGPoint(x: starCenter.x + 2.24 * starScale, y: starCenter.y + 0.77 * starScale),
                    control2: CGPoint(x: starCenter.x + 0.77 * starScale, y: starCenter.y + 2.24 * starScale)
                )
                star.addCurve(
                    to: CGPoint(x: starCenter.x - 5.9 * starScale, y: starCenter.y),
                    control1: CGPoint(x: starCenter.x - 0.77 * starScale, y: starCenter.y + 2.24 * starScale),
                    control2: CGPoint(x: starCenter.x - 2.24 * starScale, y: starCenter.y + 0.77 * starScale)
                )
                star.addCurve(
                    to: CGPoint(x: starCenter.x, y: starCenter.y - 5.9 * starScale),
                    control1: CGPoint(x: starCenter.x - 2.24 * starScale, y: starCenter.y - 0.77 * starScale),
                    control2: CGPoint(x: starCenter.x - 0.77 * starScale, y: starCenter.y - 2.24 * starScale)
                )
                star.closeSubpath()

                let starOuter = 5.9 * starScale
                context.fill(
                    star,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 1.0, green: 0.945, blue: 0.729), location: 0.0),
                            .init(color: Color(red: 0.973, green: 0.757, blue: 0.322), location: 0.45),
                            .init(color: Color(red: 0.863, green: 0.533, blue: 0.114), location: 1.0),
                        ]),
                        startPoint: CGPoint(x: starCenter.x - starOuter * 0.56, y: starCenter.y - starOuter * 0.84),
                        endPoint: CGPoint(x: starCenter.x + starOuter * 0.64, y: starCenter.y + starOuter * 0.84)
                    )
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
        )
        .shadow(color: Color(red: 0.08, green: 0.12, blue: 0.25).opacity(0.32), radius: 14, y: 6)
    }
}

struct BadgePill: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

struct SettingsRowIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
    }
}

struct RegionFlagBadge: View {
    let code: String
    var font: Font = .title3
    var monogramWidth: CGFloat = 24
    var monogramHeight: CGFloat = 20

    private var meta: RegionMeta {
        RegionCatalog.meta(for: code)
    }

    var body: some View {
        if RegionCatalog.canRenderFlag(for: code) {
            Text(meta.flag)
                .font(font)
        } else {
            Text(meta.code)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.indigo)
                .frame(width: monogramWidth, height: monogramHeight)
                .background(Color.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

struct StickySaveBar: View {
    let title: String
    var subtitle: String? = nil
    var isSaving: Bool = false
    var isDisabled: Bool = false
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onSave) {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                                .controlSize(.small)
                        }
                        Text(isSaving ? "保存中..." : "保存更改")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(isSaving || isDisabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}
