import CoreGraphics
import Foundation

struct WorldMapBounds: Decodable, Sendable {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
}

private struct RawWorldDotMapPayload: Decodable {
    let cols: Int
    let rows: Int
    let bounds: WorldMapBounds
    let anchors: [String: [Double]]
    let rle: String
}

struct WorldDotMapData: Sendable {
    struct CellPoint: Hashable, Sendable {
        let index: Int
        let col: Int
        let row: Int
        let code: String // "#" for unassigned land, or 2-letter region code
    }

    let cols: Int
    let rows: Int
    let bounds: WorldMapBounds
    let anchors: [String: (lat: Double, lon: Double)]
    let landCells: [CellPoint]
    let countryCells: [String: [CellPoint]]

    static let shared: WorldDotMapData = loadFromBundle()

    private static func loadFromBundle() -> WorldDotMapData {
        guard let url = Bundle.main.url(forResource: "world-dot-map", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode(RawWorldDotMapPayload.self, from: data)
        else {
            return WorldDotMapData(
                cols: 160,
                rows: 88,
                bounds: WorldMapBounds(minLat: -56, maxLat: 80, minLon: -180, maxLon: 180),
                anchors: [:],
                landCells: [],
                countryCells: [:]
            )
        }

        var decoded = [String]()
        decoded.reserveCapacity(raw.cols * raw.rows)
        for part in raw.rle.split(separator: ",") {
            var numStr = ""
            var tokenStr = ""
            for ch in part {
                if tokenStr.isEmpty && ch.isNumber {
                    numStr.append(ch)
                } else {
                    tokenStr.append(ch)
                }
            }
            let count = Int(numStr) ?? 1
            if !tokenStr.isEmpty {
                for _ in 0..<count where decoded.count < raw.cols * raw.rows {
                    decoded.append(tokenStr)
                }
            }
        }

        var landCells = [CellPoint]()
        var countryCells = [String: [CellPoint]]()
        for (idx, cell) in decoded.enumerated() where cell != "." {
            let point = CellPoint(
                index: idx,
                col: idx % raw.cols,
                row: idx / raw.cols,
                code: cell
            )
            landCells.append(point)
            if cell != "#" {
                countryCells[cell, default: []].append(point)
            }
        }

        var anchorMap = [String: (Double, Double)]()
        for (code, coords) in raw.anchors where coords.count >= 2 {
            anchorMap[code] = (coords[0], coords[1])
        }

        return WorldDotMapData(
            cols: raw.cols,
            rows: raw.rows,
            bounds: raw.bounds,
            anchors: anchorMap,
            landCells: landCells,
            countryCells: countryCells
        )
    }

    private static func mercatorY(_ latDeg: Double) -> Double {
        let clamped = min(max(latDeg, -85), 85)
        return log(tan(.pi / 4 + (clamped * .pi) / 360))
    }

    func projectAnchorUnit(lat: Double, lon: Double) -> CGPoint {
        let top = Self.mercatorY(bounds.maxLat)
        let bottom = Self.mercatorY(bounds.minLat)
        let x = (lon - bounds.minLon) / (bounds.maxLon - bounds.minLon)
        let y = (top - Self.mercatorY(lat)) / (top - bottom)
        return CGPoint(
            x: min(max(x, 0.01), 0.99),
            y: min(max(y, 0.02), 0.98)
        )
    }

    func nearestLandCell(xUnit: Double, yUnit: Double) -> CellPoint? {
        let targetCol = xUnit * Double(cols) - 0.5
        let targetRow = yUnit * Double(rows) - 0.5
        var best: CellPoint?
        var bestDist = Double.infinity
        for cell in landCells {
            let dx = Double(cell.col) - targetCol
            let dy = Double(cell.row) - targetRow
            let dist = dx * dx + dy * dy
            if dist < bestDist {
                bestDist = dist
                best = cell
            }
        }
        return best
    }
}
