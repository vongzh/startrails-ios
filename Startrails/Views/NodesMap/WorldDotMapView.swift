import SwiftUI

struct RegionSummaryRow: Identifiable, Hashable {
    let code: String
    let meta: RegionMeta
    let count: Int
    let avgLatencyMs: Int?

    var id: String { code }
}

struct WorldDotMapView: View {
    let regionRows: [RegionSummaryRow]
    @Binding var selectedRegion: String
    var isProbing: Bool = false
    var hasProbeData: Bool = false
    var probeEngineLabel: String = "本机直连"
    var onRunProbe: (() -> Void)? = nil
    var onOpenListForRegion: (String) -> Void

    @State private var scale: CGFloat = 1.0
    @GestureState private var gestureScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @GestureState private var dragDelta: CGSize = .zero

    private var mapData: WorldDotMapData { WorldDotMapData.shared }

    private var rowByCode: [String: RegionSummaryRow] {
        Dictionary(uniqueKeysWithValues: regionRows.map { ($0.code, $0) })
    }

    private var coveredCellCountry: [Int: String] {
        var out = [Int: String]()
        for row in regionRows where row.code != "OTHER" {
            if let cells = mapData.countryCells[row.code], !cells.isEmpty {
                for cell in cells {
                    out[cell.index] = row.code
                }
            } else if let coords = mapData.anchors[row.code] {
                let unit = mapData.projectAnchorUnit(lat: coords.lat, lon: coords.lon)
                if let nearest = mapData.nearestLandCell(xUnit: Double(unit.x), yUnit: Double(unit.y)),
                   out[nearest.index] == nil {
                    out[nearest.index] = row.code
                }
            }
        }
        return out
    }

    private var activeAnchors: [(row: RegionSummaryRow, unit: CGPoint)] {
        regionRows.compactMap { row in
            guard row.code != "OTHER", let coords = mapData.anchors[row.code] else { return nil }
            let unit = mapData.projectAnchorUnit(lat: coords.lat, lon: coords.lon)
            return (row, unit)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("地区分布")
                        .font(.subheadline.weight(.semibold))
                    let totalCount = regionRows.reduce(0) { $0 + $1.count }
                    Text("\(regionRows.count) 个地区 · \(totalCount) 个节点")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if scale > 1.05 || abs(panOffset.width) > 2 || abs(panOffset.height) > 2 {
                    Button("还原视图") {
                        withAnimation(.spring(duration: 0.25)) {
                            scale = 1.0
                            panOffset = .zero
                        }
                    }
                    .font(.caption.weight(.medium))
                } else if let onRunProbe {
                    Button(action: onRunProbe) {
                        HStack(spacing: 4) {
                            if isProbing {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            Text(isProbing ? "测速中" : (hasProbeData ? "重测 (\(probeEngineLabel))" : "测延迟 · \(probeEngineLabel)"))
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .foregroundStyle(isProbing ? Color.secondary : Color.accentColor)
                        .background(
                            Capsule()
                                .fill(isProbing ? Color(.tertiarySystemFill) : Color.accentColor.opacity(0.11))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isProbing)
                } else {
                    Text("双指缩放 · 点击高亮节点地区")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            GeometryReader { geo in
                let effectiveScale = min(max(scale * gestureScale, 1.0), 3.0)
                let totalOffset = clampedOffset(
                    CGSize(width: panOffset.width + dragDelta.width, height: panOffset.height + dragDelta.height),
                    boxSize: geo.size,
                    scale: effectiveScale
                )
                ZStack {
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: activeAnchors.isEmpty)) { timeline in
                        let elapsed = timeline.date.timeIntervalSinceReferenceDate
                        Canvas { context, size in
                            context.translateBy(x: totalOffset.width, y: totalOffset.height)
                            context.scaleBy(x: effectiveScale, y: effectiveScale)

                            let cellW = size.width / CGFloat(mapData.cols)
                            let cellH = size.height / CGFloat(mapData.rows)
                            let radius = max(0.85, min(cellW, cellH) * 0.36)
                            let covered = coveredCellCountry
                            let focus = selectedRegion
                            let hasFocus = !focus.isEmpty
                            let rowsMap = rowByCode
                            let anchors = activeAnchors

                            // 1) Base land dots
                            var landPath = Path()
                            for cell in mapData.landCells where covered[cell.index] == nil {
                                let cx = (CGFloat(cell.col) + 0.5) * cellW
                                let cy = (CGFloat(cell.row) + 0.5) * cellH
                                landPath.addEllipse(in: CGRect(
                                    x: cx - radius,
                                    y: cy - radius,
                                    width: radius * 2,
                                    height: radius * 2
                                ))
                            }
                            context.fill(landPath, with: .color(Color(.tertiaryLabel).opacity(0.32)))

                            // 2) Active node countries grouped by color
                            var groupedPaths = [String: (color: Color, isFocused: Bool, path: Path)]()
                            for (index, code) in covered {
                                let col = index % mapData.cols
                                let rowIdx = index / mapData.cols
                                let cx = (CGFloat(col) + 0.5) * cellW
                                let cy = (CGFloat(rowIdx) + 0.5) * cellH
                                let isFocused = !hasFocus || focus == code
                                let r = isFocused ? radius * 1.15 : radius
                                let latency = rowsMap[code]?.avgLatencyMs
                                let tint: Color = latency == nil ? .accentColor : Formatters.latencyColor(latency)
                                let key = "\(code)-\(isFocused)"
                                var entry = groupedPaths[key] ?? (tint, isFocused, Path())
                                entry.path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                                groupedPaths[key] = entry
                            }

                            for item in groupedPaths.values {
                                let alpha = item.isFocused ? 0.92 : 0.24
                                context.fill(item.path, with: .color(item.color.opacity(alpha)))
                            }

                            // 3) Star-Trail Constellation Arcs from focused hub (or between top 4 hubs)
                            if let focusAnchor = anchors.first(where: { $0.row.code == focus }) {
                                let fx = focusAnchor.unit.x * size.width
                                let fy = focusAnchor.unit.y * size.height
                                let focusTint = focusAnchor.row.avgLatencyMs == nil
                                    ? Color.accentColor
                                    : Formatters.latencyColor(focusAnchor.row.avgLatencyMs)
                                for targetAnchor in anchors where targetAnchor.row.code != focus {
                                    let tx = targetAnchor.unit.x * size.width
                                    let ty = targetAnchor.unit.y * size.height
                                    let dist = hypot(tx - fx, ty - fy)
                                    let lift = min(44.0, dist * 0.24)
                                    let mid = CGPoint(x: (fx + tx) * 0.5, y: (fy + ty) * 0.5 - lift)
                                    var arc = Path()
                                    arc.move(to: CGPoint(x: fx, y: fy))
                                    arc.addQuadCurve(to: CGPoint(x: tx, y: ty), control: mid)
                                    context.stroke(
                                        arc,
                                        with: .color(focusTint.opacity(0.36)),
                                        style: StrokeStyle(
                                            lineWidth: 1.05 / sqrt(effectiveScale),
                                            lineCap: .round,
                                            dash: [4 / sqrt(effectiveScale), 4 / sqrt(effectiveScale)],
                                            dashPhase: -CGFloat(elapsed * 16)
                                        )
                                    )
                                }
                            }

                            // 4) Pulsing Star Beacons
                            let pulseSpeed = isProbing ? 1.35 : 0.55
                            for (idx, anchor) in anchors.enumerated() {
                                let px = anchor.unit.x * size.width
                                let py = anchor.unit.y * size.height
                                let tint = anchor.row.avgLatencyMs == nil
                                    ? Color.accentColor
                                    : Formatters.latencyColor(anchor.row.avgLatencyMs)
                                let active = !hasFocus || focus == anchor.row.code
                                let phase = (elapsed * pulseSpeed + Double(idx) * 0.23).truncatingRemainder(dividingBy: 1.0)

                                if active {
                                    let expandR = (3.4 + CGFloat(phase) * (focus == anchor.row.code ? 11.5 : 7.0)) / sqrt(effectiveScale)
                                    let ringRect = CGRect(x: px - expandR, y: py - expandR, width: expandR * 2, height: expandR * 2)
                                    context.stroke(
                                        Path(ellipseIn: ringRect),
                                        with: .color(tint.opacity((1.0 - phase) * (focus == anchor.row.code ? 0.85 : 0.45))),
                                        lineWidth: 1.2 / sqrt(effectiveScale)
                                    )
                                }

                                let r: CGFloat = (focus == anchor.row.code ? 4.0 : 3.0) / sqrt(effectiveScale)
                                let beaconRect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                                context.fill(Path(ellipseIn: beaconRect), with: .color(tint.opacity(active ? 1.0 : 0.35)))
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        Haptics.impact(.light)
                        withAnimation(.spring(duration: 0.3)) {
                            if scale > 1.15 {
                                scale = 1.0
                                panOffset = .zero
                            } else {
                                scale = 2.2
                                panOffset = clampedOffset(
                                    CGSize(width: -geo.size.width * 0.55, height: -geo.size.height * 0.55),
                                    boxSize: geo.size,
                                    scale: 2.2
                                )
                            }
                        }
                    }
                    .onTapGesture { location in
                        let adjusted = CGPoint(
                            x: (location.x - totalOffset.width) / effectiveScale,
                            y: (location.y - totalOffset.height) / effectiveScale
                        )
                        handleTap(at: adjusted, canvasSize: geo.size)
                    }
                    .gesture(
                        MagnificationGesture()
                            .updating($gestureScale) { value, state, _ in
                                state = value
                            }
                            .onEnded { value in
                                scale = min(max(scale * value, 1.0), 3.0)
                                if scale <= 1.02 {
                                    scale = 1.0
                                    panOffset = .zero
                                } else {
                                    panOffset = clampedOffset(panOffset, boxSize: geo.size, scale: scale)
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 6)
                            .updating($dragDelta) { value, state, _ in
                                guard effectiveScale > 1.02 else { return }
                                state = value.translation
                            }
                            .onEnded { value in
                                guard scale > 1.02 else { return }
                                panOffset = clampedOffset(
                                    CGSize(width: panOffset.width + value.translation.width, height: panOffset.height + value.translation.height),
                                    boxSize: geo.size,
                                    scale: scale
                                )
                            }
                    )
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
            .aspectRatio(160.0 / 88.0, contentMode: .fit)
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 10) {
                legendDot(color: Color(red: 0.22, green: 0.65, blue: 0.36), label: "<100ms")
                legendDot(color: Color(red: 0.85, green: 0.54, blue: 0.08), label: "<250ms")
                legendDot(color: Color(red: 0.85, green: 0.24, blue: 0.20), label: "偏慢")
                legendDot(color: .accentColor, label: "待测速")
                Spacer()
                Text("双击缩放")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            if let selectedRow = regionRows.first(where: { $0.code == selectedRegion }) {
                HStack(spacing: 8) {
                    RegionFlagBadge(code: selectedRow.code, font: .headline, monogramWidth: 24, monogramHeight: 18)
                    Text(selectedRow.meta.fullName)
                        .font(.subheadline.weight(.semibold))
                    BadgePill(text: "\(selectedRow.count) 节点", tint: .blue)
                    if let avg = selectedRow.avgLatencyMs {
                        BadgePill(text: "均值 \(avg) ms", tint: Formatters.latencyColor(avg))
                    }
                    Spacer()
                    Button("查看列表") {
                        onOpenListForRegion(selectedRow.code)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.top, 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: selectedRegion)
        .surfaceCard(cornerRadius: 16, padding: 14)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func clampedOffset(_ raw: CGSize, boxSize: CGSize, scale: CGFloat) -> CGSize {
        let maxX = max(0, boxSize.width * (scale - 1))
        let maxY = max(0, boxSize.height * (scale - 1))
        return CGSize(
            width: min(0, max(-maxX, raw.width)),
            height: min(0, max(-maxY, raw.height))
        )
    }

    private func handleTap(at point: CGPoint, canvasSize: CGSize) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let nx = point.x / canvasSize.width
        let ny = point.y / canvasSize.height

        var closestCode: String?
        var closestDist = CGFloat.infinity
        for anchor in activeAnchors {
            let dx = anchor.unit.x - nx
            let dy = anchor.unit.y - ny
            let dist = hypot(dx, dy)
            if dist < 0.08 && dist < closestDist {
                closestDist = dist
                closestCode = anchor.row.code
            }
        }

        if let hit = closestCode {
            Haptics.impact(.light)
            selectedRegion = (selectedRegion == hit) ? "" : hit
        } else if !selectedRegion.isEmpty {
            selectedRegion = ""
        }
    }
}
