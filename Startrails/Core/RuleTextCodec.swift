import Foundation

struct ParsedRuleSkip: Identifiable, Hashable, Sendable {
    let line: Int
    let text: String
    let reason: String

    var id: String { "\(line):\(text)" }
}

struct RuleTextParseResult: Sendable {
    let rules: [RuleItem]
    let skipped: [ParsedRuleSkip]
}

/// 精确对齐 `web/src/rule-text.ts` 的双向文本规则编解码器（支持 Surge/Clash 规则行、`AND/OR/NOT`、`RULE-SET`、`FINAL/MATCH`）。
enum RuleTextCodec {
    private static let simpleRuleTypes: [String: String] = [
        "DOMAIN": "domain",
        "HOST": "domain",
        "DOMAIN-SUFFIX": "domainSuffix",
        "HOST-SUFFIX": "domainSuffix",
        "DOMAIN-KEYWORD": "domainKeyword",
        "HOST-KEYWORD": "domainKeyword",
        "GEOSITE": "geosite",
        "GEOIP": "geoip",
        "IP-CIDR": "ipCidr",
        "IP-CIDR6": "ipCidr6",
        "IP6-CIDR": "ipCidr6",
    ]

    private static let noResolveTypes: Set<String> = ["ipCidr", "ipCidr6", "geoip"]

    private static let subconverterPrefixes: [(prefix: String, shape: String)] = [
        ("clash-domain:", "domain"),
        ("clash-ipcidr:", "ipcidr"),
        ("clash-classic:", "rules"),
        ("surge:", "rules"),
        ("quanx:", "rules"),
    ]

    // MARK: - Formatting

    static func formatText(_ rules: [RuleItem]) -> String {
        rules.map(formatLine).joined(separator: "\n")
    }

    static func formatLine(_ rule: RuleItem) -> String {
        switch rule {
        case .final(let policy):
            return "MATCH,\(policy)"
        case .external(let url, let policy, let shape, let format):
            var parts = ["RULE-SET", url, policy]
            if let shape, !shape.isEmpty { parts.append(shape) }
            if let format, !format.isEmpty { parts.append(format) }
            return parts.joined(separator: ",")
        case .inline(let cond, let policy):
            if cond.type == "match" {
                return "MATCH,\(policy)"
            }
            let appendNoResolve = noResolveTypes.contains(cond.type) && cond.noResolve == true
            return "\(formatCondition(cond, nested: false)),\(policy)\(appendNoResolve ? ",no-resolve" : "")"
        }
    }

    private static func formatCondition(_ cond: RuleConditionBox, nested: Bool) -> String {
        let nr = (nested && noResolveTypes.contains(cond.type) && cond.noResolve == true) ? ",no-resolve" : ""
        switch cond.type {
        case "domain": return "DOMAIN,\(cond.value ?? "")"
        case "domainSuffix": return "DOMAIN-SUFFIX,\(cond.value ?? "")"
        case "domainKeyword": return "DOMAIN-KEYWORD,\(cond.value ?? "")"
        case "geosite": return "GEOSITE,\(cond.value ?? "")"
        case "geoip": return "GEOIP,\(cond.value ?? "")\(nr)"
        case "ipCidr": return "IP-CIDR,\(cond.value ?? "")\(nr)"
        case "ipCidr6": return "IP-CIDR6,\(cond.value ?? "")\(nr)"
        case "match": return "MATCH"
        case "and", "or":
            let children = (cond.children ?? []).map { "(\(formatCondition($0, nested: true)))" }.joined(separator: ",")
            return "\(cond.type.uppercased()),(\(children))"
        case "not":
            let inner = cond.child.map { formatCondition($0, nested: true) } ?? ""
            return "NOT,((\(inner)))"
        default:
            if let val = cond.value {
                return "\(cond.type),\(val)"
            }
            return cond.type
        }
    }

    // MARK: - Parsing

    static func parseText(_ text: String) -> RuleTextParseResult {
        var rules = [RuleItem]()
        var skipped = [ParsedRuleSkip]()
        let lines = text.components(separatedBy: .newlines)

        for (index, rawLine) in lines.enumerated() {
            let lineNum = index + 1
            let normalized = normalizeRuleLine(rawLine)
            if normalized.isEmpty { continue }

            let (parts, splitError) = splitTopLevelCsv(normalized)
            if let splitError {
                skipped.append(ParsedRuleSkip(line: lineNum, text: rawLine.trimmingCharacters(in: .whitespaces), reason: splitError))
                continue
            }

            let head = (parts.first ?? "").uppercased()

            if head == "MATCH" || head == "FINAL" {
                let policy = parts.count > 1 ? parts[1] : ""
                guard !policy.isEmpty else {
                    skipped.append(ParsedRuleSkip(line: lineNum, text: rawLine.trimmingCharacters(in: .whitespaces), reason: "\(head) 缺少策略名"))
                    continue
                }
                rules.append(.final(policy: policy))
                continue
            }

            if head == "RULE-SET" {
                let rawTarget = parts.count > 1 ? parts[1] : ""
                let policy = parts.count > 2 ? parts[2] : ""
                guard !rawTarget.isEmpty, !policy.isEmpty else {
                    skipped.append(ParsedRuleSkip(line: lineNum, text: rawLine.trimmingCharacters(in: .whitespaces), reason: "RULE-SET 缺少地址或策略名"))
                    continue
                }
                let (target, inferredShape) = stripSubconverterPrefix(rawTarget)
                guard target.lowercased().hasPrefix("http://") || target.lowercased().hasPrefix("https://") else {
                    skipped.append(ParsedRuleSkip(line: lineNum, text: rawLine.trimmingCharacters(in: .whitespaces), reason: "RULE-SET 需要 http(s) 规则集地址"))
                    continue
                }
                var shape = inferredShape ?? "domain"
                var format = "text"
                for extra in parts.dropFirst(3) {
                    let lower = extra.lowercased()
                    if lower == "domain" || lower == "ipcidr" || lower == "rules" {
                        shape = lower
                    } else if lower == "text" || lower == "yaml" {
                        format = lower
                    }
                }
                rules.append(.external(url: target, policy: policy, shape: shape, format: format))
                continue
            }

            if head == "AND" || head == "OR" || head == "NOT" {
                guard parts.count >= 3 else {
                    skipped.append(ParsedRuleSkip(line: lineNum, text: rawLine.trimmingCharacters(in: .whitespaces), reason: "\(head) 缺少条件或策略名"))
                    continue
                }
                let rawExpr = "\(parts[0]),\(parts[1])"
                let policy = parts[2]
                guard !policy.isEmpty else {
                    skipped.append(ParsedRuleSkip(line: lineNum, text: rawLine.trimmingCharacters(in: .whitespaces), reason: "\(head) 缺少策略名"))
                    continue
                }
                switch parseConditionExpr(rawExpr) {
                case .success(let cond):
                    rules.append(.inline(condition: cond, policy: policy))
                case .failure(let err):
                    skipped.append(ParsedRuleSkip(line: lineNum, text: rawLine.trimmingCharacters(in: .whitespaces), reason: err.message))
                }
                continue
            }

            guard let mappedType = simpleRuleTypes[head] else {
                skipped.append(ParsedRuleSkip(line: lineNum, text: rawLine.trimmingCharacters(in: .whitespaces), reason: "不支持的规则类型「\(parts.first ?? head)」"))
                continue
            }

            let value = parts.count > 1 ? parts[1] : ""
            let policy = parts.count > 2 ? parts[2] : ""
            guard !value.isEmpty, !policy.isEmpty else {
                skipped.append(ParsedRuleSkip(line: lineNum, text: rawLine.trimmingCharacters(in: .whitespaces), reason: "缺少匹配值或策略名"))
                continue
            }

            let noResolve = noResolveTypes.contains(mappedType) && parts.dropFirst(3).contains { $0.lowercased() == "no-resolve" }
            let box = RuleConditionBox(type: mappedType, value: value, noResolve: noResolve ? true : nil)
            rules.append(.inline(condition: box, policy: policy))
        }

        return RuleTextParseResult(rules: rules, skipped: skipped)
    }

    private struct ConditionParseError: Error {
        let message: String
    }

    private static func parseConditionExpr(_ expr: String) -> Result<RuleConditionBox, ConditionParseError> {
        let (parts, splitError) = splitTopLevelCsv(expr)
        if let splitError {
            return .failure(ConditionParseError(message: splitError))
        }
        let head = (parts.first ?? "").uppercased()

        if head == "AND" || head == "OR" || head == "NOT" {
            let rawGroup = parts.count > 1 ? parts[1] : ""
            guard let inner = unwrapOuterParens(rawGroup), !inner.isEmpty, parts.count == 2 else {
                return .failure(ConditionParseError(message: "\(head) 条件语法错误，需要 \(head),((...))"))
            }
            let (items, itemsError) = splitTopLevelCsv(inner)
            if let itemsError {
                return .failure(ConditionParseError(message: itemsError))
            }
            if head == "NOT" && !inner.hasPrefix("(") {
                switch parseConditionExpr(inner) {
                case .success(let child): return .success(RuleConditionBox(type: "not", child: child))
                case .failure(let err): return .failure(err)
                }
            }
            var children = [RuleConditionBox]()
            for rawChild in items {
                guard let unwrapped = unwrapOuterParens(rawChild), !unwrapped.isEmpty else {
                    return .failure(ConditionParseError(message: "\(head) 子条件需要用括号包裹"))
                }
                switch parseConditionExpr(unwrapped) {
                case .success(let child): children.append(child)
                case .failure(let err): return .failure(err)
                }
            }
            if head == "NOT" {
                guard children.count == 1, let only = children.first else {
                    return .failure(ConditionParseError(message: "NOT 条件只能包含 1 个子条件"))
                }
                return .success(RuleConditionBox(type: "not", child: only))
            }
            guard !children.isEmpty else {
                return .failure(ConditionParseError(message: "\(head) 至少需要 1 个子条件"))
            }
            return .success(RuleConditionBox(type: head.lowercased(), children: children))
        }

        guard let mappedType = simpleRuleTypes[head] else {
            return .failure(ConditionParseError(message: "不支持的子条件类型「\(parts.first ?? head)」"))
        }
        let value = parts.count > 1 ? parts[1] : ""
        guard !value.isEmpty else {
            return .failure(ConditionParseError(message: "\(head) 缺少匹配值"))
        }
        let noResolve = noResolveTypes.contains(mappedType) && parts.dropFirst(2).contains { $0.lowercased() == "no-resolve" }
        return .success(RuleConditionBox(type: mappedType, value: value, noResolve: noResolve ? true : nil))
    }

    private static func stripOuterQuotes(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2,
           (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    private static func normalizeRuleLine(_ original: String) -> String {
        var line = original.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") || line.hasPrefix("//") { return "" }
        if line.hasPrefix("- ") || line.hasPrefix("-\t") {
            line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        } else if line == "-" {
            return ""
        }
        if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") || line.hasPrefix("//") { return "" }
        line = stripTrailingComment(line)
        if line.hasSuffix(",") {
            line = String(line.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return stripOuterQuotes(line)
    }

    private static func stripTrailingComment(_ line: String) -> String {
        let chars = Array(line)
        var quote: Character?
        var depth = 0
        for i in chars.indices {
            let ch = chars[i]
            if let q = quote {
                if ch == q && (i == 0 || chars[i - 1] != "\\") { quote = nil }
                continue
            }
            if ch == "\"" || ch == "'" {
                quote = ch
                continue
            }
            if ch == "(" { depth += 1; continue }
            if ch == ")" && depth > 0 { depth -= 1; continue }
            if depth > 0 { continue }

            if (ch == "#" || ch == ";") && i > 0 && chars[i - 1].isWhitespace {
                return String(chars[0..<i]).trimmingCharacters(in: .whitespaces)
            }
            if ch == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                let prev = i > 0 ? chars[i - 1] : " "
                if prev != ":" && (i == 0 || prev.isWhitespace || prev == "," || prev == "'" || prev == "\"") {
                    return String(chars[0..<i]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    private static func splitTopLevelCsv(_ text: String) -> ([String], String?) {
        let chars = Array(text)
        var parts = [String]()
        var current = ""
        var quote: Character?
        var depth = 0

        for i in chars.indices {
            let ch = chars[i]
            if let q = quote {
                if ch == q && (i == 0 || chars[i - 1] != "\\") { quote = nil }
                current.append(ch)
                continue
            }
            if ch == "\"" || ch == "'" {
                quote = ch
                current.append(ch)
                continue
            }
            if ch == "(" {
                depth += 1
                current.append(ch)
                continue
            }
            if ch == ")" {
                depth -= 1
                if depth < 0 { return ([], "括号不匹配（多余右括号）") }
                current.append(ch)
                continue
            }
            if ch == "," && depth == 0 {
                parts.append(stripOuterQuotes(current))
                current = ""
                continue
            }
            current.append(ch)
        }
        if quote != nil { return ([], "引号未闭合") }
        if depth != 0 { return ([], "括号未闭合") }
        parts.append(stripOuterQuotes(current))
        return (parts, nil)
    }

    private static func unwrapOuterParens(_ expr: String) -> String? {
        let trimmed = expr.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("("), trimmed.hasSuffix(")") else { return nil }
        let chars = Array(trimmed)
        var quote: Character?
        var depth = 0
        for i in chars.indices {
            let ch = chars[i]
            if let q = quote {
                if ch == q && (i == 0 || chars[i - 1] != "\\") { quote = nil }
                continue
            }
            if ch == "\"" || ch == "'" { quote = ch; continue }
            if ch == "(" { depth += 1 }
            else if ch == ")" {
                depth -= 1
                if depth == 0 && i < chars.count - 1 { return nil }
            }
        }
        guard depth == 0 else { return nil }
        return String(chars.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    private static func stripSubconverterPrefix(_ rawTarget: String) -> (String, String?) {
        let lower = rawTarget.lowercased()
        for item in subconverterPrefixes where lower.hasPrefix(item.prefix) {
            return (String(rawTarget.dropFirst(item.prefix.count)).trimmingCharacters(in: .whitespaces), item.shape)
        }
        return (rawTarget, nil)
    }
}
