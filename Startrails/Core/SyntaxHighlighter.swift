import SwiftUI

enum SyntaxHighlighter {
    private static func mapRange(
        _ strRange: Range<String.Index>,
        in target: AttributedString
    ) -> Range<AttributedString.Index>? {
        guard let low = AttributedString.Index(strRange.lowerBound, within: target),
              let high = AttributedString.Index(strRange.upperBound, within: target),
              low <= high else {
            return nil
        }
        return low..<high
    }

    static func highlight(_ line: String, dialect: ClientDialect) -> AttributedString {
        var result = AttributedString(line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return result }

        if trimmed.hasPrefix("#") || trimmed.hasPrefix(";") || trimmed.hasPrefix("//") {
            result.foregroundColor = Color(red: 0.44, green: 0.56, blue: 0.48)
            return result
        }

        switch dialect {
        case .clashYaml, .egernYaml:
            if trimmed.hasPrefix("- "),
               let dashRange = line.range(of: "- "),
               let attrDash = mapRange(dashRange, in: result) {
                result[attrDash].foregroundColor = Color.teal
            }
            if let colonRange = line.range(of: ":") {
                let keySlice = line[..<colonRange.lowerBound].trimmingCharacters(in: .whitespaces)
                if !keySlice.isEmpty && !keySlice.hasPrefix("http"),
                   let attrKey = mapRange(line.startIndex..<colonRange.lowerBound, in: result) {
                    result[attrKey].foregroundColor = Color(red: 0.22, green: 0.52, blue: 0.92)
                }
                let valSlice = line[colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
                if (valSlice == "true" || valSlice == "false" || Int(valSlice) != nil),
                   let valRange = line.range(of: valSlice, range: colonRange.upperBound..<line.endIndex),
                   let attrVal = mapRange(valRange, in: result) {
                    result[attrVal].foregroundColor = Color(red: 0.62, green: 0.38, blue: 0.90)
                }
            }
        case .surgeIni, .loonIni, .quanxIni:
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                result.foregroundColor = Color(red: 0.45, green: 0.38, blue: 0.92)
                return result
            }
            if let eqRange = line.range(of: "=") {
                if let attrKey = mapRange(line.startIndex..<eqRange.lowerBound, in: result) {
                    result[attrKey].foregroundColor = Color(red: 0.14, green: 0.58, blue: 0.80)
                }
            } else if let comma = line.firstIndex(of: ",") {
                if let attrHead = mapRange(line.startIndex..<comma, in: result) {
                    result[attrHead].foregroundColor = Color(red: 0.22, green: 0.52, blue: 0.92)
                }
            }
        case .singBoxJson:
            if let colon = line.range(of: "\":") {
                let keyEnd = line.index(after: colon.lowerBound)
                if let attrKey = mapRange(line.startIndex..<keyEnd, in: result) {
                    result[attrKey].foregroundColor = Color(red: 0.22, green: 0.52, blue: 0.92)
                }
            }
        case .uriList, .auto:
            if let schemeEnd = line.range(of: "://") {
                if let attrScheme = mapRange(line.startIndex..<schemeEnd.lowerBound, in: result) {
                    result[attrScheme].foregroundColor = Color.teal
                }
            }
        }

        return result
    }
}
