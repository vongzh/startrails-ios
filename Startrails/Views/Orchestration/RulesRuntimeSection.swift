import SwiftUI
import UIKit

private enum TriBool: String, CaseIterable, Hashable {
    case unset
    case on
    case off

    var label: String {
        switch self {
        case .unset: return "不写"
        case .on: return "开启"
        case .off: return "关闭"
        }
    }

    init(from optionalBool: Bool?) {
        switch optionalBool {
        case .some(true): self = .on
        case .some(false): self = .off
        case .none: self = .unset
        }
    }

    var boolValue: Bool? {
        switch self {
        case .unset: return nil
        case .on: return true
        case .off: return false
        }
    }
}

struct RulesRuntimeSection: View {
    @Environment(AppStore.self) private var store

    // Rules state
    @State private var ruleMode: OverlayMode = .inherit
    @State private var rulePlacement: String = "before"
    @State private var rules: [RuleItem] = []
    @State private var rulesDirty = false
    @State private var showAddRuleSheet = false
    @State private var showBatchTextSheet = false

    // Runtime DNS/TUN state
    @State private var dnsMode: OverlayMode = .inherit
    @State private var dnsModeValue: String = "unset"
    @State private var nameserverText: String = ""
    @State private var proxyNameserverText: String = ""
    @State private var proxyNameserverEmpty: Bool = false
    @State private var directNameserverText: String = ""
    @State private var fallbackText: String = ""
    @State private var nameserverPolicyText: String = ""
    @State private var ecsText: String = ""
    @State private var fakeIpRange: String = ""
    @State private var ipv6Tri: TriBool = .unset

    // Advanced mihomo DNS fields
    @State private var showAdvancedDns: Bool = false
    @State private var defaultNameserverText: String = ""
    @State private var fakeIpFilterText: String = ""
    @State private var fallbackFilterGeoip: TriBool = .unset
    @State private var fallbackFilterGeoipCode: String = ""
    @State private var fallbackFilterIpCidrText: String = ""
    @State private var fallbackFilterDomainText: String = ""
    @State private var useHostsTri: TriBool = .unset
    @State private var useSystemHostsTri: TriBool = .unset
    @State private var respectRulesTri: TriBool = .unset

    // TUN state
    @State private var tunEnabled: Bool = false
    @State private var tunStack: String = "gvisor"
    @State private var tunStrictRoute: TriBool = .unset
    @State private var tunMtuText: String = ""

    @State private var runtimeDirty = false
    @State private var isSaving = false

    private var invalidPolicyLines: [String] {
        splitLines(nameserverPolicyText).filter { line in
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            return parts.count < 2
        }
    }

    private var capabilitySummary: (dnsYes: [String], dnsNo: [String], fakeIpYes: [String], tunYes: [String]) {
        let entries = (store.runtimeResponse?.targets ?? [:]).sorted { $0.key < $1.key }
        let dnsYes = entries.filter { $0.value.dns == "support" }.map(\.key)
        let dnsNo = entries.filter { $0.value.dns != "support" }.map(\.key)
        let fakeIpYes = entries.filter { $0.value.fakeIp == "support" }.map(\.key)
        let tunYes = entries.filter { $0.value.tun == "support" }.map(\.key)
        return (dnsYes, dnsNo, fakeIpYes, tunYes)
    }

    private var hasAnyRuntimeDraft: Bool {
        dnsMode != .inherit ||
            dnsModeValue != "unset" ||
            !splitLines(nameserverText).isEmpty ||
            !splitLines(proxyNameserverText).isEmpty ||
            proxyNameserverEmpty ||
            !splitLines(directNameserverText).isEmpty ||
            !splitLines(fallbackText).isEmpty ||
            !splitLines(nameserverPolicyText).isEmpty ||
            !ecsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !fakeIpRange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            ipv6Tri != .unset ||
            !splitLines(defaultNameserverText).isEmpty ||
            !splitLines(fakeIpFilterText).isEmpty ||
            fallbackFilterGeoip != .unset ||
            !fallbackFilterGeoipCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !splitLines(fallbackFilterIpCidrText).isEmpty ||
            !splitLines(fallbackFilterDomainText).isEmpty ||
            useHostsTri != .unset ||
            useSystemHostsTri != .unset ||
            respectRulesTri != .unset ||
            tunEnabled
    }

    var body: some View {
        List {
            // MARK: - Rules Overlay
            Section {
                Picker("规则覆盖方式", selection: $ruleMode) {
                    ForEach(OverlayMode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .onChange(of: ruleMode) { _, _ in rulesDirty = true }

                if ruleMode == .merge {
                    Picker("合并位置", selection: $rulePlacement) {
                        Text("置前 (优先匹配)").tag("before")
                        Text("置后 (兜底前匹配)").tag("after")
                    }
                    .onChange(of: rulePlacement) { _, _ in rulesDirty = true }
                }
            } header: {
                Text("分流规则覆盖")
            }

            if ruleMode != .inherit {
                Section {
                    if rules.isEmpty {
                        Text("暂无自定义规则，可单条添加或批量文本导入")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rules) { rule in
                            RuleRowView(rule: rule)
                        }
                        .onDelete { offsets in
                            rules.remove(atOffsets: offsets)
                            rulesDirty = true
                        }
                        .onMove { from, to in
                            rules.move(fromOffsets: from, toOffset: to)
                            rulesDirty = true
                        }
                    }

                    Button {
                        showAddRuleSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "plus", tint: .teal)
                            Text("添加规则 / Rule-Set")
                                .foregroundStyle(.primary)
                            Spacer()
                            RowChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showBatchTextSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "doc.text.magnifyingglass", tint: .indigo)
                            Text("批量文本导入 / 编辑（支持 AND / OR / NOT）")
                                .foregroundStyle(.primary)
                            Spacer()
                            RowChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    HStack {
                        Text("自定义规则 (\(rules.count))")
                        Spacer()
                        EditButton().font(.caption).textCase(nil)
                    }
                }
            }

            // MARK: - DNS & TUN
            Section {
                Picker("DNS / TUN 覆盖", selection: $dnsMode) {
                    ForEach(OverlayMode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .onChange(of: dnsMode) { _, _ in runtimeDirty = true }

                if dnsMode == .inherit {
                    Text("当前为「自动继承」：构建产物沿用订阅自带 DNS；切换到「完全覆盖」或「合并增强」后下述 DNS 策略将写入产物。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Picker("DNS 模式", selection: $dnsModeValue) {
                    Text("不写").tag("unset")
                    Text("system").tag("system")
                    Text("redir-host").tag("redir-host")
                    Text("fake-ip").tag("fake-ip")
                }
                .onChange(of: dnsModeValue) { _, _ in runtimeDirty = true }

                multilineField(
                    title: "Nameserver（每行一条）",
                    placeholder: "https://dns.alidns.com/dns-query",
                    text: $nameserverText,
                    height: 54
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("按域名指定解析器（nameserver-policy：<域名> <解析器>）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $nameserverPolicyText)
                        .font(.caption.monospaced())
                        .frame(minHeight: 54)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: nameserverPolicyText) { _, _ in runtimeDirty = true }
                    if !invalidPolicyLines.isEmpty {
                        Text("格式无效（需「域名 空格 解析器」）：\(invalidPolicyLines[0])")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                multilineField(
                    title: "Fallback（每行一条）",
                    placeholder: "tls://8.8.4.4",
                    text: $fallbackText,
                    height: 48
                )

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("节点域名解析器显式留空 []", isOn: $proxyNameserverEmpty)
                        .font(.subheadline)
                        .onChange(of: proxyNameserverEmpty) { _, _ in runtimeDirty = true }

                    if !proxyNameserverEmpty {
                        multilineField(
                            title: "节点域名解析器（proxy-server-nameserver）",
                            placeholder: "解析节点域名用；留空走默认",
                            text: $proxyNameserverText,
                            height: 46
                        )
                    }
                }

                multilineField(
                    title: "直连域名解析器（direct-nameserver）",
                    placeholder: "https://doh.pub/dns-query",
                    text: $directNameserverText,
                    height: 46
                )

                TextField("Fake-IP 网段（如 198.18.0.1/16）", text: $fakeIpRange)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: fakeIpRange) { _, _ in runtimeDirty = true }

                TextField("ECS 子网（如 1.2.3.0/24）", text: $ecsText)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: ecsText) { _, _ in runtimeDirty = true }

                triPicker("IPv6 解析", selection: $ipv6Tri)

                DisclosureGroup("mihomo 高级 DNS 字段", isExpanded: $showAdvancedDns) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("仅 mihomo / clash-yaml 系客户端支持以下字段；导出到 Surge、sing-box 等客户端时会自动剥离并记录诊断。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        multilineField(
                            title: "default-nameserver（引导 DNS）",
                            placeholder: "223.5.5.5\n119.29.29.29",
                            text: $defaultNameserverText,
                            height: 48
                        )

                        multilineField(
                            title: "fake-ip-filter（每行一条）",
                            placeholder: "*.lan\n+.msftconnecttest.com",
                            text: $fakeIpFilterText,
                            height: 60
                        )

                        triPicker("fallback-filter · geoip", selection: $fallbackFilterGeoip)

                        TextField("fallback-filter · geoip-code（如 CN）", text: $fallbackFilterGeoipCode)
                            .font(.footnote.monospaced())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onChange(of: fallbackFilterGeoipCode) { _, _ in runtimeDirty = true }

                        multilineField(
                            title: "fallback-filter · ipcidr",
                            placeholder: "0.0.0.0/8\n10.0.0.0/8",
                            text: $fallbackFilterIpCidrText,
                            height: 48
                        )

                        multilineField(
                            title: "fallback-filter · domain",
                            placeholder: "+.google.com\n+.youtube.com",
                            text: $fallbackFilterDomainText,
                            height: 48
                        )

                        triPicker("use-hosts", selection: $useHostsTri)
                        triPicker("use-system-hosts", selection: $useSystemHostsTri)
                        triPicker("respect-rules", selection: $respectRulesTri)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("DNS 策略")
            }

            Section {
                Toggle("启用 TUN 虚拟网卡", isOn: $tunEnabled)
                    .onChange(of: tunEnabled) { _, _ in runtimeDirty = true }

                if tunEnabled {
                    Picker("TUN 协议栈", selection: $tunStack) {
                        Text("gvisor（最稳）").tag("gvisor")
                        Text("system（内核栈）").tag("system")
                        Text("mixed（混合）").tag("mixed")
                    }
                    .onChange(of: tunStack) { _, _ in runtimeDirty = true }

                    triPicker("Strict Route", selection: $tunStrictRoute)

                    TextField("MTU（默认留空，如 9000）", text: $tunMtuText)
                        .keyboardType(.numberPad)
                        .onChange(of: tunMtuText) { _, _ in runtimeDirty = true }
                }

                if hasAnyRuntimeDraft {
                    Button(role: .destructive) {
                        Task { await clearRuntime() }
                    } label: {
                        HStack {
                            Spacer()
                            Text("清空 DNS / TUN 策略")
                            Spacer()
                        }
                    }
                    .disabled(isSaving)
                }
            } header: {
                Text("TUN 入站")
            }

            if !(store.runtimeResponse?.targets.isEmpty ?? true) {
                Section("目标客户端运行时支持矩阵") {
                    let cap = capabilitySummary
                    CapabilityRow(title: "写入 DNS 段", targets: cap.dnsYes, tint: .green)
                    if !cap.dnsNo.isEmpty {
                        CapabilityRow(title: "跳过 DNS 段", targets: cap.dnsNo, tint: .orange)
                    }
                    CapabilityRow(title: "支持 Fake-IP", targets: cap.fakeIpYes, tint: .blue)
                    CapabilityRow(title: "支持 TUN", targets: cap.tunYes, tint: .indigo)
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.snappy(duration: 0.24), value: rulesDirty || runtimeDirty)
        .safeAreaInset(edge: .bottom) {
            if rulesDirty || runtimeDirty {
                StickySaveBar(
                    title: saveBarTitle,
                    subtitle: "作用于配置「\(store.activeProfile)」",
                    isSaving: isSaving,
                    isDisabled: runtimeDirty && !invalidPolicyLines.isEmpty
                ) {
                    Task { await savePendingChanges() }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear { syncFromStore() }
        .onChange(of: store.activeProfile) { _, _ in syncFromStore() }
        .sheet(isPresented: $showAddRuleSheet) {
            AddRuleSheet(availablePolicies: policySuggestions) { item in
                rules.append(item)
                rulesDirty = true
            }
        }
        .sheet(isPresented: $showBatchTextSheet) {
            RuleBatchTextSheet(initialRules: rules) { parsedRules in
                rules = parsedRules
                rulesDirty = true
            }
        }
    }

    private func multilineField(title: String, placeholder: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }
                TextEditor(text: text)
                    .font(.caption.monospaced())
                    .frame(minHeight: height)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: text.wrappedValue) { _, _ in runtimeDirty = true }
            }
        }
    }

    private func triPicker(_ title: String, selection: Binding<TriBool>) -> some View {
        Picker(title, selection: selection) {
            ForEach(TriBool.allCases, id: \.self) { state in
                Text(state.label).tag(state)
            }
        }
        .onChange(of: selection.wrappedValue) { _, _ in runtimeDirty = true }
    }

    private var policySuggestions: [String] {
        var set = ["DIRECT", "REJECT", "PROXY"]
        for grp in store.policyGroupsResponse?.groups ?? [] {
            set.append(grp.name)
        }
        for grp in store.policyGroupsResponse?.base ?? [] {
            if !set.contains(grp.name) { set.append(grp.name) }
        }
        return set
    }

    private func splitLines(_ raw: String) -> [String] {
        raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func syncFromStore() {
        if let res = store.rulesResponse {
            ruleMode = res.mode
            rulePlacement = res.placement
            rules = res.rules
            rulesDirty = false
        }
        if let rtRes = store.runtimeResponse {
            dnsMode = rtRes.dnsMode ?? .inherit
            let dns = rtRes.runtime?.dns
            dnsModeValue = dns?.mode ?? "unset"
            nameserverText = (dns?.nameserver ?? []).joined(separator: "\n")
            proxyNameserverEmpty = (dns?.proxyNameserver != nil && (dns?.proxyNameserver?.isEmpty == true))
            proxyNameserverText = (dns?.proxyNameserver ?? []).joined(separator: "\n")
            directNameserverText = (dns?.directNameserver ?? []).joined(separator: "\n")
            fallbackText = (dns?.fallback ?? []).joined(separator: "\n")
            nameserverPolicyText = (dns?.nameserverPolicy ?? [:])
                .sorted { $0.key < $1.key }
                .map { "\($0.key) \($0.value)" }
                .joined(separator: "\n")
            ecsText = dns?.ecs ?? ""
            fakeIpRange = dns?.fakeIpRange ?? ""
            ipv6Tri = TriBool(from: dns?.ipv6)

            defaultNameserverText = (dns?.defaultNameserver ?? []).joined(separator: "\n")
            fakeIpFilterText = (dns?.fakeIpFilter ?? []).joined(separator: "\n")
            fallbackFilterGeoip = TriBool(from: dns?.fallbackFilter?.geoip)
            fallbackFilterGeoipCode = dns?.fallbackFilter?.geoipCode ?? ""
            fallbackFilterIpCidrText = (dns?.fallbackFilter?.ipCidr ?? []).joined(separator: "\n")
            fallbackFilterDomainText = (dns?.fallbackFilter?.domain ?? []).joined(separator: "\n")
            useHostsTri = TriBool(from: dns?.useHosts)
            useSystemHostsTri = TriBool(from: dns?.useSystemHosts)
            respectRulesTri = TriBool(from: dns?.respectRules)

            let tun = rtRes.runtime?.tun
            tunEnabled = tun?.enabled == true
            tunStack = tun?.stack ?? "gvisor"
            tunStrictRoute = TriBool(from: tun?.strictRoute)
            tunMtuText = tun?.mtu.map(String.init) ?? ""
            runtimeDirty = false
        }
    }

    private var saveBarTitle: String {
        if rulesDirty && runtimeDirty { return "分流规则与 DNS / TUN 已修改" }
        if rulesDirty { return "分流规则已修改（\(rules.count) 条）" }
        return "DNS / TUN 策略已修改"
    }

    private func savePendingChanges() async {
        if rulesDirty {
            await saveRules(reloadAfter: !runtimeDirty)
        }
        if runtimeDirty {
            await saveRuntime()
        }
    }

    private func saveRules(reloadAfter: Bool = true) async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await store.client.saveRules(
                rules: rules,
                mode: ruleMode,
                placement: rulePlacement,
                profile: store.activeProfile
            )
            rulesDirty = false
            if reloadAfter {
                await store.reloadAll()
                store.showToast("分流规则已保存")
                Haptics.notify(.success)
            }
        } catch {
            store.handleError(error)
        }
    }

    private func saveRuntime() async {
        guard invalidPolicyLines.isEmpty else {
            store.showToast("按域名指定解析器格式须为「域名 空格 解析器地址」", isError: true)
            return
        }
        isSaving = true
        defer { isSaving = false }

        let ns = splitLines(nameserverText)
        let proxyNs = splitLines(proxyNameserverText)
        let directNs = splitLines(directNameserverText)
        let fb = splitLines(fallbackText)
        var policyMap = [String: String]()
        for line in splitLines(nameserverPolicyText) {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            if parts.count == 2 {
                policyMap[String(parts[0])] = String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        let defaultNs = splitLines(defaultNameserverText)
        let fakeFilter = splitLines(fakeIpFilterText)
        let ffIpCidr = splitLines(fallbackFilterIpCidrText)
        let ffDomain = splitLines(fallbackFilterDomainText)
        let ffCode = fallbackFilterGeoipCode.trimmingCharacters(in: .whitespacesAndNewlines)

        let hasFallbackFilter = fallbackFilterGeoip != .unset || !ffCode.isEmpty || !ffIpCidr.isEmpty || !ffDomain.isEmpty
        let fallbackFilter: FallbackFilterView? = hasFallbackFilter
            ? FallbackFilterView(
                geoip: fallbackFilterGeoip.boolValue,
                geoipCode: ffCode.isEmpty ? nil : ffCode,
                ipCidr: ffIpCidr.isEmpty ? nil : ffIpCidr,
                domain: ffDomain.isEmpty ? nil : ffDomain
            )
            : nil

        let ecsTrimmed = ecsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fakeIpTrimmed = fakeIpRange.trimmingCharacters(in: .whitespacesAndNewlines)

        let dnsEmpty = dnsModeValue == "unset" &&
            ns.isEmpty &&
            proxyNs.isEmpty &&
            !proxyNameserverEmpty &&
            directNs.isEmpty &&
            fb.isEmpty &&
            policyMap.isEmpty &&
            ecsTrimmed.isEmpty &&
            fakeIpTrimmed.isEmpty &&
            ipv6Tri == .unset &&
            defaultNs.isEmpty &&
            fakeFilter.isEmpty &&
            fallbackFilter == nil &&
            useHostsTri == .unset &&
            useSystemHostsTri == .unset &&
            respectRulesTri == .unset

        let dns: DnsPolicyView? = dnsEmpty
            ? nil
            : DnsPolicyView(
                mode: dnsModeValue == "unset" ? "system" : dnsModeValue,
                nameserver: ns.isEmpty ? nil : ns,
                proxyNameserver: proxyNameserverEmpty ? [] : (proxyNs.isEmpty ? nil : proxyNs),
                directNameserver: directNs.isEmpty ? nil : directNs,
                fallback: fb.isEmpty ? nil : fb,
                nameserverPolicy: policyMap.isEmpty ? nil : policyMap,
                ecs: ecsTrimmed.isEmpty ? nil : ecsTrimmed,
                fakeIpRange: fakeIpTrimmed.isEmpty ? nil : fakeIpTrimmed,
                ipv6: ipv6Tri.boolValue,
                defaultNameserver: defaultNs.isEmpty ? nil : defaultNs,
                fallbackFilter: fallbackFilter,
                fakeIpFilter: fakeFilter.isEmpty ? nil : fakeFilter,
                useHosts: useHostsTri.boolValue,
                useSystemHosts: useSystemHostsTri.boolValue,
                respectRules: respectRulesTri.boolValue
            )

        let mtuVal = Int(tunMtuText.trimmingCharacters(in: .whitespaces))
        let tun: TunPolicyView? = tunEnabled
            ? TunPolicyView(
                enabled: true,
                stack: tunStack,
                strictRoute: tunStrictRoute.boolValue,
                mtu: (mtuVal ?? 0) > 0 ? mtuVal : nil
            )
            : nil

        let payload: RuntimePolicyView? = (dns == nil && tun == nil)
            ? nil
            : RuntimePolicyView(dns: dns, tun: tun)

        do {
            _ = try await store.client.saveRuntime(payload, profile: store.activeProfile, dnsMode: dnsMode)
            runtimeDirty = false
            await store.reloadAll()
            store.showToast(payload == nil ? "已清空 DNS / TUN 策略" : "DNS / TUN 已保存")
            Haptics.notify(.success)
        } catch {
            store.handleError(error)
        }
    }

    private func clearRuntime() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await store.client.saveRuntime(nil, profile: store.activeProfile, dnsMode: .inherit)
            await store.reloadAll()
            syncFromStore()
            store.showToast("已清空：产物不再写入 DNS / TUN 段")
            Haptics.notify(.success)
        } catch {
            store.handleError(error)
        }
    }
}

private struct CapabilityRow: View {
    let title: String
    let targets: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                BadgePill(text: "\(targets.count) 目标", tint: tint)
            }
            Text(targets.isEmpty ? "无" : targets.joined(separator: " · "))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct RuleRowView: View {
    let rule: RuleItem

    private func policyTint(_ policy: String) -> Color {
        switch policy.uppercased() {
        case "DIRECT": return .green
        case "REJECT", "REJECT-DROP": return .red
        default: return .blue
        }
    }

    var body: some View {
        switch rule {
        case .inline(let cond, let policy):
            HStack(spacing: 12) {
                SettingsRowIcon(systemName: "line.3.horizontal.decrease.circle", tint: .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cond.summaryText)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                    Text("内联规则")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                BadgePill(text: policy, tint: policyTint(policy))
            }
            .padding(.vertical, 2)
        case .external(let url, let policy, let shape, let format):
            HStack(spacing: 12) {
                SettingsRowIcon(systemName: "doc.text.fill", tint: .indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                    let fmtSuffix = format.map { " · \($0)" } ?? ""
                    Text("外部 Rule-Set (\(shape ?? "rules")\(fmtSuffix))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                BadgePill(text: policy, tint: policyTint(policy))
            }
            .padding(.vertical, 2)
        case .final(let policy):
            HStack(spacing: 12) {
                SettingsRowIcon(systemName: "flag.checkered", tint: .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FINAL / MATCH")
                        .font(.caption.monospaced().weight(.semibold))
                    Text("最终兜底策略")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                BadgePill(text: policy, tint: policyTint(policy))
            }
            .padding(.vertical, 2)
        }
    }
}

private struct AddRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let availablePolicies: [String]
    let onAdd: (RuleItem) -> Void

    @State private var kind: String = "inline"
    @State private var condType: String = "domainSuffix"
    @State private var condValue: String = ""
    @State private var noResolve: Bool = false
    @State private var externalURL: String = ""
    @State private var externalShape: String = "rules"
    @State private var externalFormat: String = ""
    @State private var policy: String = "PROXY"

    private let conditionTypes: [(label: String, type: String)] = [
        ("DOMAIN-SUFFIX 域名后缀", "domainSuffix"),
        ("DOMAIN 完整域名", "domain"),
        ("DOMAIN-KEYWORD 关键词", "domainKeyword"),
        ("IP-CIDR IPv4 网段", "ipCidr"),
        ("IP-CIDR6 IPv6 网段", "ipCidr6"),
        ("GEOIP 地区", "geoip"),
        ("GEOSITE 站点库", "geosite"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("规则类型") {
                    Picker("类型", selection: $kind) {
                        Text("单条内联规则").tag("inline")
                        Text("远程 Rule-Set 列表").tag("external")
                        Text("最终兜底 (FINAL)").tag("final")
                    }
                }

                if kind == "inline" {
                    Section("匹配条件") {
                        Picker("条件", selection: $condType) {
                            ForEach(conditionTypes, id: \.type) { item in
                                Text(item.label).tag(item.type)
                            }
                        }
                        TextField("匹配值（例如 openai.com 或 CN）", text: $condValue)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if condType == "ipCidr" || condType == "ipCidr6" || condType == "geoip" {
                            Toggle("no-resolve（不触发本地 DNS）", isOn: $noResolve)
                        }
                    }
                } else if kind == "external" {
                    Section("外部规则集地址") {
                        TextField("https://...", text: $externalURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Picker("列表形态", selection: $externalShape) {
                            Text("标准规则 (rules)").tag("rules")
                            Text("纯域名集 (domain)").tag("domain")
                            Text("IP CIDR 集 (ipcidr)").tag("ipcidr")
                        }
                        Picker("文件编码", selection: $externalFormat) {
                            Text("纯文本 / 自动").tag("")
                            Text("Text 列表").tag("text")
                            Text("YAML (payload:)").tag("yaml")
                        }
                    }
                }

                Section("命中策略") {
                    TextField("策略名（如 PROXY / DIRECT / REJECT）", text: $policy)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(availablePolicies, id: \.self) { p in
                                Button(p) { policy = p }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                            }
                        }
                    }
                }
            }
            .navigationTitle("添加分流规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        addRule()
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
    }

    private var canAdd: Bool {
        let p = policy.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return false }
        if kind == "inline" { return !condValue.trimmingCharacters(in: .whitespaces).isEmpty }
        if kind == "external" { return !externalURL.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private func addRule() {
        let p = policy.trimmingCharacters(in: .whitespaces)
        switch kind {
        case "external":
            onAdd(.external(
                url: externalURL.trimmingCharacters(in: .whitespaces),
                policy: p,
                shape: externalShape,
                format: externalFormat.isEmpty ? nil : externalFormat
            ))
        case "final":
            onAdd(.final(policy: p))
        default:
            let needsNoResolve = (condType == "ipCidr" || condType == "ipCidr6" || condType == "geoip") && noResolve
            let box = RuleConditionBox(
                type: condType,
                value: condValue.trimmingCharacters(in: .whitespaces),
                noResolve: needsNoResolve ? true : nil
            )
            onAdd(.inline(condition: box, policy: p))
        }
    }
}

private struct RuleBatchTextSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initialRules: [RuleItem]
    let onApply: ([RuleItem]) -> Void

    @State private var text: String = ""

    private var parsed: RuleTextParseResult {
        RuleTextCodec.parseText(text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.caption.monospaced())
                        .frame(minHeight: 240)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    HStack {
                        Text("规则文本（每行一条）")
                        Spacer()
                        Button("粘贴") {
                            if let clip = UIPasteboard.general.string {
                                text = text.isEmpty ? clip : "\(text)\n\(clip)"
                            }
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                } footer: {
                    Text("兼容 Surge / Clash / YAML 前缀 `- ` 与 `clash-domain:`，支持 `AND/OR/NOT` 嵌套逻辑与 `RULE-SET`。")
                }

                Section("实时解析预览") {
                    HStack {
                        BadgePill(text: "有效 \(parsed.rules.count) 条", tint: .green)
                        if !parsed.skipped.isEmpty {
                            BadgePill(text: "忽略 \(parsed.skipped.count) 行", tint: .orange)
                        }
                    }

                    ForEach(parsed.skipped) { skip in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("第 \(skip.line) 行：\(skip.reason)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(skip.text)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("批量文本导入 / 编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用 (\(parsed.rules.count))") {
                        onApply(parsed.rules)
                        dismiss()
                    }
                }
            }
            .onAppear {
                text = RuleTextCodec.formatText(initialRules)
            }
        }
    }
}
