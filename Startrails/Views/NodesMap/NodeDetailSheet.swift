import SwiftUI

struct NodeDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let node: NodeView

    @State private var alias: String = ""
    @State private var manualRegion: String = ""
    @State private var excluded: Bool = false
    @State private var tag: String = ""
    @State private var isSaving: Bool = false
    @State private var localSingleProbe: LocalProbeResult?
    @State private var probingSingle: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("节点信息") {
                    LabeledContent("原始名称", value: node.name)
                    LabeledContent("协议类型", value: node.kind.uppercased())
                    LabeledContent("服务器地址", value: node.address)
                    if let geo = node.geo {
                        if geo.conflict == true {
                            LabeledContent("Geo 解析", value: "多 IP 地区不一致，已跳过自动归属")
                        } else if let country = geo.country {
                            let srcLabel = geo.source == "manual" ? "人工覆盖" : (geo.source == "name" ? "节点名识别" : "离线 IP 库")
                            LabeledContent("Geo 归属", value: "\(RegionCatalog.displayLabel(for: country, full: true)) (\(srcLabel))")
                        }
                        if let asn = geo.asn {
                            LabeledContent("ASN / 组织", value: "AS\(asn) \(geo.org ?? "")")
                        }
                    }
                    if !node.sources.isEmpty {
                        LabeledContent("所属订阅源", value: node.sources.joined(separator: ", "))
                    }
                }

                Section {
                    HStack {
                        Text("本机直连延迟")
                        Spacer()
                        if probingSingle {
                            ProgressView().controlSize(.small)
                        } else if let res = localSingleProbe ?? store.localProbeResults[node.nodeKey] {
                            if !res.applicable {
                                BadgePill(text: "UDP 协议", tint: .secondary)
                            } else if let ms = res.latencyMs {
                                Text("\(ms) ms")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(Formatters.latencyColor(ms))
                            } else {
                                Text(res.error ?? "不可达")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        } else {
                            Text("未测试")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let srv = store.serverProbeResults[node.nodeKey] {
                        HStack {
                            Text("服务端探测")
                            Spacer()
                            if srv.applicable == false {
                                BadgePill(text: "UDP 协议", tint: .secondary)
                            } else if srv.intercepted {
                                BadgePill(text: "已被本机/Fake-IP 劫持", tint: .orange)
                            } else if let ms = srv.latencyMs {
                                let intMs = Int(ms.rounded())
                                Text("\(intMs) ms")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(Formatters.latencyColor(intMs))
                            } else {
                                Text(srv.error ?? "不可达")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    Button {
                        Task {
                            probingSingle = true
                            let result = await LocalProbeService.probeNode(node)
                            localSingleProbe = result
                            store.localProbeResults[node.nodeKey] = result
                            store.lastProbeAt = Date()
                            probingSingle = false
                        }
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "waveform.path.ecg", tint: .teal)
                            Text("测试此节点 TCP 握手")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("延迟检测")
                } footer: {
                    Text("Hysteria2 / TUIC / WireGuard 为纯 UDP 协议，不支持 TCP 握手测速。")
                }

                Section {
                    Toggle("从「\(store.activeProfile)」中排除", isOn: $excluded)
                    TextField("自定义别名（留空用原始名）", text: $alias)
                    Picker("人工指定地区", selection: $manualRegion) {
                        Text("自动识别（名称 / 离线 Geo IP）").tag("")
                        ForEach(RegionCatalog.pickerCodes, id: \.self) { code in
                            Text("\(RegionCatalog.displayLabel(for: code, full: true)) (\(code))").tag(code)
                        }
                        if !manualRegion.isEmpty && !RegionCatalog.pickerCodes.contains(manualRegion) {
                            Text("\(RegionCatalog.displayLabel(for: manualRegion, full: true)) (自定义)").tag(manualRegion)
                        }
                    }
                    TextField("或输入自定义 2 位地区码（如 BR / AR）", text: $manualRegion)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: manualRegion) { _, newValue in
                            let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                            if normalized != newValue {
                                manualRegion = normalized
                            }
                        }
                    TextField("分组标签 Tag（可选）", text: $tag)
                } header: {
                    Text("配置级标注（仅作用于 \(store.activeProfile)）")
                }
            }
            .navigationTitle("节点详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中..." : "保存") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                if let ann = store.annotationByKey[node.nodeKey] {
                    alias = ann.alias ?? ""
                    manualRegion = ann.region ?? ""
                    excluded = ann.excluded ?? false
                    tag = ann.tag ?? ""
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let existingOrder = store.annotationByKey[node.nodeKey]?.order
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = AnnotationView(
            nodeKey: node.nodeKey,
            excluded: excluded,
            alias: trimmedAlias.isEmpty ? "" : trimmedAlias,
            tag: trimmedTag.isEmpty ? "" : trimmedTag,
            order: existingOrder,
            region: manualRegion
        )
        await store.saveAnnotation(payload)
        dismiss()
    }
}
