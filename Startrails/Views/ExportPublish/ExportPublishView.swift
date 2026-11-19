import SwiftUI
import UIKit

struct ExportPublishView: View {
    @Environment(AppStore.self) private var store
    @Binding var showSettings: Bool
    @Binding var showCreateProfile: Bool
    @Binding var showRenameProfile: Bool
    @Binding var showDeleteProfile: Bool
    @Binding var newProfileName: String

    @State private var isIssuing = false
    @State private var showFullPreview = false
    @State private var previewInspectorTab: PreviewInspectorTab = .code
    @State private var qrToken: TokenView?
    @State private var showRevoked = false

    private var allTargets: [ClientTargetView] {
        store.workspaceState?.clientTargets ?? []
    }

    private var installedTargetItems: [ClientTargetView] {
        allTargets.filter { store.installedTargets.contains($0.id) }
    }

    private var selectedTargetInfo: ClientTargetView? {
        allTargets.first { $0.id == store.selectedTarget }
    }

    private var selectedDialect: ClientDialect {
        guard let info = selectedTargetInfo else { return .clashYaml }
        return ClientImportScheme.dialect(for: info.dialect, id: info.id)
    }

    private var activeTokens: [TokenView] {
        let all = store.workspaceState?.tokens ?? []
        return all.filter { $0.profile == store.activeProfile && (showRevoked || !$0.revoked) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !installedTargetItems.isEmpty {
                    installedClientsSection
                }

                Section {
                    targetSelectorStrip
                } header: {
                    Text("全部导出目标 (\(allTargets.count + 1))")
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)

                Section {
                    selectedTargetCard
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                tokensSection
            }
            .listStyle(.insetGrouped)
            .animation(.snappy(duration: 0.22), value: showRevoked)
            .refreshable {
                store.refreshInstalledClients()
                await store.reloadAll()
                await store.loadPreview()
            }
            .navigationTitle("导出与发布")
            .workspaceToolbar(
                showSettings: $showSettings,
                showCreateProfile: $showCreateProfile,
                showRenameProfile: $showRenameProfile,
                showDeleteProfile: $showDeleteProfile,
                newProfileName: $newProfileName
            )
            .task {
                store.refreshInstalledClients()
                if store.selectedTarget != "auto" && store.preview == nil {
                    await store.loadPreview()
                }
            }
            .sheet(isPresented: $showFullPreview) {
                if let preview = store.preview {
                    CodePreviewSheet(
                        preview: preview,
                        dialect: selectedDialect,
                        initialTab: previewInspectorTab
                    )
                }
            }
            .sheet(item: $qrToken) { token in
                if let url = token.url {
                    QRCodeSheet(
                        title: "\(targetDisplayName(token.target)) · \(token.profile)",
                        subtitle: "使用支持该格式的客户端扫码订阅",
                        content: url
                    )
                }
            }
        }
    }

    private var installedClientsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(installedTargetItems) { target in
                        ClientChipCard(
                            id: target.id,
                            name: target.name,
                            dialect: target.dialect,
                            isSelected: store.selectedTarget == target.id,
                            isInstalled: true
                        ) {
                            selectTarget(target.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        } header: {
            Text("本机已安装客户端 (\(installedTargetItems.count))")
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear)
    }

    private var tokensSection: some View {
        Section {
            if activeTokens.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("暂无已签发的订阅地址")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("在上方选择目标客户端并点击「签发」即可生成独立订阅令牌。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(activeTokens) { token in
                    tokenRow(for: token)
                }
            }
        } header: {
            HStack {
                Text("已签发订阅地址 (\(activeTokens.count))")
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        showRevoked.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showRevoked ? "checkmark.circle.fill" : "circle")
                            .font(.caption2)
                        Text("含已吊销")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(showRevoked ? Color.accentColor : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(showRevoked ? Color.accentColor.opacity(0.14) : Color(.tertiarySystemFill))
                    )
                }
                .buttonStyle(.plain)
                .textCase(nil)
            }
        }
    }

    private func tokenRow(for token: TokenView) -> some View {
        TokenRowView(
            token: token,
            targetName: targetDisplayName(token.target),
            dialectTint: targetColor(token.target),
            onOpenQR: { qrToken = token },
            onCopy: {
                guard let url = token.url else { return }
                UIPasteboard.general.string = url
                store.showToast("已复制 \(token.target) 订阅链接")
                Haptics.notify(.success)
            },
            onCopyExtra: { extraURL, label in
                UIPasteboard.general.string = extraURL
                store.showToast("已复制\(label)")
                Haptics.notify(.success)
            },
            onOneTapImport: {
                guard let url = token.url,
                      let schemeURL = ClientImportScheme.importURL(
                          target: token.target,
                          subscriptionURL: url,
                          name: "Startrails · \(token.profile)",
                          revision: String(Int(Date().timeIntervalSince1970))
                      ) else { return }
                Task { @MainActor in
                    _ = await UIApplication.shared.open(schemeURL)
                }
            }
        )
        .swipeActions(edge: .trailing) {
            if !token.revoked {
                Button(role: .destructive) {
                    Task { await revoke(token) }
                } label: {
                    Label("吊销", systemImage: "xmark.shield")
                }
            }
        }
        .contextMenu {
            if let url = token.url, !token.revoked {
                Button {
                    UIPasteboard.general.string = url
                    store.showToast("已复制 \(token.target) 订阅链接")
                    Haptics.notify(.success)
                } label: {
                    Label("复制订阅链接", systemImage: "doc.on.doc")
                }
                Button {
                    qrToken = token
                } label: {
                    Label("展示订阅二维码", systemImage: "qrcode")
                }
                if !token.revoked {
                    Divider()
                    Button(role: .destructive) {
                        Task { await revoke(token) }
                    } label: {
                        Label("吊销该地址", systemImage: "xmark.shield")
                    }
                }
            }
        }
    }

    private var targetSelectorStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ClientChipCard(
                    id: "auto",
                    name: "UA 自动识别",
                    dialect: "auto",
                    isSelected: store.selectedTarget == "auto",
                    isInstalled: false
                ) {
                    selectTarget("auto")
                }

                ForEach(allTargets) { target in
                    ClientChipCard(
                        id: target.id,
                        name: target.name,
                        dialect: target.dialect,
                        isSelected: store.selectedTarget == target.id,
                        isInstalled: store.installedTargets.contains(target.id)
                    ) {
                        selectTarget(target.id)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var selectedTargetCard: some View {
        let targetId = store.selectedTarget
        let targetName = targetDisplayName(targetId)
        let hint = ClientImportScheme.hint(for: targetId)
        let canLaunchScheme = ClientImportScheme.importURL(
            target: targetId,
            subscriptionURL: "https://example.com/sub",
            name: "Startrails"
        ) != nil
        let matchingPreview = (store.preview?.target == targetId) ? store.preview : nil

        return VStack(alignment: .leading, spacing: 12) {
            targetHeaderRow(targetId: targetId, targetName: targetName)

            if targetId != "auto" {
                if store.isLoadingPreview {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在实时构建产物预览...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let preview = matchingPreview {
                    PreviewSummarySnippetView(
                        preview: preview,
                        dialect: selectedDialect,
                        onOpenTab: { tab in
                            previewInspectorTab = tab
                            showFullPreview = true
                        }
                    )
                }
            }

            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.nodes.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("当前配置节点池为空，建议先在「订阅概览」导入来源后再签发订阅。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            targetActionBar(targetId: targetId, canLaunchScheme: canLaunchScheme, preview: matchingPreview)
        }
        .surfaceCard(cornerRadius: 16, padding: 14, accentBorder: targetColor(targetId))
    }

    private func targetHeaderRow(targetId: String, targetName: String) -> some View {
        HStack(spacing: 10) {
            ClientBrandIcon(
                targetId: targetId,
                dialect: selectedTargetInfo?.dialect ?? (targetId == "auto" ? "auto" : "clash-yaml"),
                size: 36,
                tintOverride: targetColor(targetId)
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(targetName)
                        .font(.headline)
                    if store.installedTargets.contains(targetId) {
                        BadgePill(text: "已安装", tint: .green)
                    }
                    if let info = selectedTargetInfo, info.contentMode == "nodes-only" {
                        BadgePill(text: "仅节点列表", tint: .orange)
                    }
                }
                Text(selectedTargetInfo.map { "\($0.dialect) · \($0.id).\($0.fileExtension)" } ?? "服务端按客户端 User-Agent 自动匹配格式")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func targetActionBar(targetId: String, canLaunchScheme: Bool, preview: PreviewView?) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await issuePrimaryAction(targetId: targetId, canLaunchScheme: canLaunchScheme) }
            } label: {
                HStack {
                    if isIssuing { ProgressView().tint(.white).controlSize(.small) }
                    Image(systemName: canLaunchScheme ? "arrow.up.forward.app.fill" : "plus.circle.fill")
                    Text(canLaunchScheme ? "签发并一键导入" : "签发并复制地址")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isIssuing)

            if let preview,
               let fileURL = writeTempExportFile(filename: preview.filename, content: preview.content) {
                ShareLink(item: fileURL) {
                    Image(systemName: "square.and.arrow.up")
                        .padding(10)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("导出配置文件")
            }
        }
    }

    private func selectTarget(_ id: String) {
        Haptics.impact(.light)
        withAnimation(.snappy(duration: 0.22)) {
            store.selectedTarget = id
        }
        if id != "auto" {
            Task { await store.loadPreview(target: id) }
        }
    }

    private func issuePrimaryAction(targetId: String, canLaunchScheme: Bool) async {
        isIssuing = true
        defer { isIssuing = false }
        if let outcome = await store.issueAndOpen(target: targetId, openInApp: canLaunchScheme) {
            UIPasteboard.general.string = outcome.token.url
            if !canLaunchScheme {
                store.showToast("已签发并复制 \(targetDisplayName(targetId)) 订阅地址")
            } else if !outcome.openedInApp {
                store.showToast("已签发并复制地址（未检测到客户端，请粘贴导入）")
            }
        }
    }

    private func revoke(_ token: TokenView) async {
        do {
            _ = try await store.client.revokeToken(id: token.id)
            await store.reloadAll()
            store.showToast("已吊销该订阅地址")
            Haptics.notify(.success)
        } catch {
            store.handleError(error)
        }
    }

    private func targetDisplayName(_ id: String) -> String {
        if id == "auto" { return "自动识别" }
        return allTargets.first(where: { $0.id == id })?.name ?? id
    }

    private func targetColor(_ id: String) -> Color {
        let dialect = allTargets.first(where: { $0.id == id })?.dialect ?? "auto"
        return ClientImportScheme.dialect(for: dialect, id: id).tint
    }

    private func writeTempExportFile(filename: String, content: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(filename)
        let data = Data(content.utf8)
        if let existing = try? Data(contentsOf: url), existing == data {
            return url
        }
        try? data.write(to: url, options: .atomic)
        return url
    }
}

private struct PreviewSummarySnippetView: View {
    let preview: PreviewView
    let dialect: ClientDialect
    let onOpenTab: (PreviewInspectorTab) -> Void

    private var lineCount: Int {
        preview.content.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private var snippetLines: [String] {
        preview.content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(6)
            .map { String($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                BadgePill(text: "\(preview.report.passed) 通过", tint: .green)
                if preview.report.skipped > 0 {
                    Button { onOpenTab(.diagnostics) } label: {
                        BadgePill(text: "\(preview.report.skipped) 跳过", tint: .orange)
                    }
                    .buttonStyle(.plain)
                }
                if !preview.trace.steps.isEmpty {
                    Button { onOpenTab(.trace) } label: {
                        BadgePill(text: "轨迹 \(preview.trace.steps.count) 步", tint: .indigo)
                    }
                    .buttonStyle(.plain)
                }
                Text("\(lineCount) 行 · \(Formatters.bytes(Double(preview.content.utf8.count)))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("展开全文") { onOpenTab(.code) }
                    .font(.caption.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(snippetLines.enumerated()), id: \.offset) { _, line in
                    Text(SyntaxHighlighter.highlight(line, dialect: dialect))
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            .onTapGesture { onOpenTab(.code) }
        }
    }
}

private struct ClientChipCard: View {
    let id: String
    let name: String
    let dialect: String
    let isSelected: Bool
    let isInstalled: Bool
    let onTap: () -> Void

    private var tint: Color {
        ClientImportScheme.dialect(for: dialect, id: id).tint
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                ClientBrandIcon(
                    targetId: id,
                    dialect: dialect,
                    size: 22,
                    tintOverride: tint,
                    isSelected: isSelected,
                    bare: true
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)
                    if isInstalled {
                        Text("已安装")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(isSelected ? .white.opacity(0.85) : .green)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? tint : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? tint : Color(.separator).opacity(0.28), lineWidth: isSelected ? 1.2 : 0.5)
            )
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.95))
    }
}

private struct TokenRowView: View {
    let token: TokenView
    let targetName: String
    let dialectTint: Color
    let onOpenQR: () -> Void
    let onCopy: () -> Void
    let onCopyExtra: (String, String) -> Void
    let onOneTapImport: () -> Void

    private func appendedURL(_ base: String, suffixPath: String?, query: (String, String)? = nil) -> String {
        guard var components = URLComponents(string: base) else {
            if let suffixPath { return base + suffixPath }
            if let query { return base + (base.contains("?") ? "&" : "?") + "\(query.0)=\(query.1)" }
            return base
        }
        if let suffixPath {
            components.path += suffixPath
        }
        if let query {
            var items = components.queryItems ?? []
            items.removeAll { $0.name == query.0 }
            items.append(URLQueryItem(name: query.0, value: query.1))
            components.queryItems = items
        }
        return components.url?.absoluteString ?? base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ClientBrandIcon(
                    targetId: token.target,
                    size: 20,
                    tintOverride: token.revoked ? .secondary : dialectTint
                )
                Text(targetName)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(token.revoked)
                BadgePill(text: token.profile, tint: .indigo)
                if token.revoked {
                    BadgePill(text: "已吊销", tint: .red)
                }
                Spacer()
                Text(Formatters.isoShort(token.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let url = token.url, !token.revoked {
                Text(url)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Button(action: onCopy) {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button(action: onOpenQR) {
                        Label("二维码", systemImage: "qrcode")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    if ClientImportScheme.importURL(target: token.target, subscriptionURL: url) != nil {
                        Button(action: onOneTapImport) {
                            Label("一键导入", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(dialectTint)
                        .controlSize(.mini)
                    }

                    Spacer(minLength: 0)

                    Menu {
                        if token.target == "v2box" || token.target == "auto" {
                            Button {
                                onCopyExtra(appendedURL(url, suffixPath: nil, query: ("format", "base64")), "Base64 订阅链接")
                            } label: {
                                Label("复制 Base64 链接 (?format=base64)", systemImage: "textformat.abc")
                            }
                        }
                        Button {
                            onCopyExtra(appendedURL(url, suffixPath: "/diagnostics"), "构建诊断回执链接")
                        } label: {
                            Label("复制构建诊断地址 (/diagnostics)", systemImage: "stethoscope")
                        }
                        ShareLink(item: url) {
                            Label("系统分享链接", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
            } else if !token.revoked {
                Text("早期只存哈希的历史令牌无法回显 URL，请重新签发。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

private enum PreviewInspectorTab: String, CaseIterable {
    case code
    case diagnostics
    case trace
}

private struct PreviewLineItem: Identifiable {
    let number: Int
    let text: String
    var id: Int { number }
}

private struct CodePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preview: PreviewView
    let dialect: ClientDialect
    let initialTab: PreviewInspectorTab

    @State private var tab: PreviewInspectorTab = .code
    @State private var query: String = ""

    private var filteredLines: [PreviewLineItem] {
        let all = preview.content.components(separatedBy: "\n").enumerated().map {
            PreviewLineItem(number: $0.offset + 1, text: $0.element)
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.text.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("视图", selection: $tab) {
                    Text("代码").tag(PreviewInspectorTab.code)
                    Text("诊断 (\(preview.report.diagnostics.count))").tag(PreviewInspectorTab.diagnostics)
                    Text("轨迹 (\(preview.trace.steps.count))").tag(PreviewInspectorTab.trace)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))

                switch tab {
                case .code:
                    PreviewCodeTabView(lines: filteredLines, dialect: dialect)
                case .diagnostics:
                    PreviewDiagnosticsTabView(report: preview.report)
                case .trace:
                    PreviewTraceTabView(steps: preview.trace.steps)
                }
            }
            .animation(.snappy(duration: 0.2), value: tab)
            .navigationTitle(preview.filename)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "在产物中检索关键词...")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = preview.content
                        Haptics.notify(.success)
                    } label: {
                        Label("复制全文", systemImage: "doc.on.doc")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                tab = initialTab
            }
        }
    }
}

private struct PreviewCodeTabView: View {
    let lines: [PreviewLineItem]
    let dialect: ClientDialect

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(lines) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Text(String(format: "%4d", line.number))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 34, alignment: .trailing)
                        Text(SyntaxHighlighter.highlight(line.text, dialect: dialect))
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(14)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct PreviewDiagnosticsTabView: View {
    let report: PreviewView.ReportWrapper

    var body: some View {
        List {
            Section {
                HStack {
                    BadgePill(text: "\(report.passed) 通过", tint: .green)
                    BadgePill(text: "\(report.skipped) 跳过", tint: report.skipped > 0 ? .orange : .secondary)
                }
            }
            Section("诊断条目 (\(report.diagnostics.count))") {
                if report.diagnostics.isEmpty {
                    Text("本次构建无警告或能力降级")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.diagnostics) { diag in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                BadgePill(text: diag.stage, tint: .orange)
                                if let t = diag.target {
                                    BadgePill(text: t, tint: .blue)
                                }
                            }
                            Text(diag.subject)
                                .font(.subheadline.weight(.medium))
                            Text(diag.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct PreviewTraceTabView: View {
    let steps: [TraceStepView]

    var body: some View {
        List {
            if steps.isEmpty {
                Text("当前配置没有可追踪的构建步骤")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(steps, id: \.index) { step in
                    Section("步骤 #\(step.index + 1) · 节点 \(step.nodesBefore) → \(step.nodesAfter)") {
                        if step.diff.isEmpty && step.diagnostics.isEmpty {
                            Text("本步无变更")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(step.diff.enumerated()), id: \.offset) { _, diff in
                            HStack(alignment: .top, spacing: 8) {
                                BadgePill(text: diff.kind, tint: diffTint(diff.kind))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(diff.ref)
                                        .font(.caption.weight(.semibold))
                                    if !diff.detail.isEmpty {
                                        Text(diff.detail)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        ForEach(step.diagnostics) { diag in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("[\(diag.stage)] \(diag.subject)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                Text(diag.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func diffTint(_ kind: String) -> Color {
        switch kind.lowercased() {
        case "remove", "exclude", "drop": return .red
        case "add", "keep": return .green
        case "rename", "modify": return .blue
        default: return .indigo
        }
    }
}
