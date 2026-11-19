import SwiftUI

enum MainTab: Hashable {
    case overview
    case nodes
    case orchestration
    case exportPublish
}

struct RootTabView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedTab: MainTab = .overview
    @State private var showSettings: Bool = false
    @State private var showCreateProfile: Bool = false
    @State private var showRenameProfile: Bool = false
    @State private var showDeleteProfile: Bool = false
    @State private var newProfileName: String = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewSourcesView(
                selectedTab: $selectedTab,
                showSettings: $showSettings,
                showCreateProfile: $showCreateProfile,
                showRenameProfile: $showRenameProfile,
                showDeleteProfile: $showDeleteProfile,
                newProfileName: $newProfileName
            )
            .tabItem {
                Label("订阅概览", systemImage: "square.grid.2x2")
            }
            .tag(MainTab.overview)

            NodesMapView(
                showSettings: $showSettings,
                showCreateProfile: $showCreateProfile,
                showRenameProfile: $showRenameProfile,
                showDeleteProfile: $showDeleteProfile,
                newProfileName: $newProfileName
            )
            .tabItem {
                Label("节点", systemImage: "globe.asia.australia")
            }
            .tag(MainTab.nodes)

            OrchestrationView(
                showSettings: $showSettings,
                showCreateProfile: $showCreateProfile,
                showRenameProfile: $showRenameProfile,
                showDeleteProfile: $showDeleteProfile,
                newProfileName: $newProfileName
            )
            .tabItem {
                Label("编排与规则", systemImage: "slider.horizontal.3")
            }
            .tag(MainTab.orchestration)

            ExportPublishView(
                showSettings: $showSettings,
                showCreateProfile: $showCreateProfile,
                showRenameProfile: $showRenameProfile,
                showDeleteProfile: $showDeleteProfile,
                newProfileName: $newProfileName
            )
            .tabItem {
                Label("导出与发布", systemImage: "paperplane")
            }
            .tag(MainTab.exportPublish)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("新建配置", isPresented: $showCreateProfile) {
            TextField("配置名称（例如 mobile / home）", text: $newProfileName)
                .textInputAutocapitalization(.never)
            Button("取消", role: .cancel) {}
            Button("创建") {
                let trimmed = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Task {
                    do {
                        _ = try await store.client.createProfile(name: trimmed)
                        await store.switchProfile(trimmed)
                        store.showToast("已创建并切换到 \(trimmed)")
                    } catch {
                        store.handleError(error)
                    }
                }
            }
        } message: {
            Text("每份配置拥有独立的构成清单、节点标注、策略组与规则覆盖。")
        }
        .alert("重命名当前配置", isPresented: $showRenameProfile) {
            TextField("新的配置名称", text: $newProfileName)
                .textInputAutocapitalization(.never)
            Button("取消", role: .cancel) {}
            Button("保存") {
                let target = newProfileName
                Task { await store.renameActiveProfile(to: target) }
            }
        } message: {
            Text("该配置绑定过的已签发订阅地址会自动同步更新配置名称。")
        }
        .alert("删除当前配置「\(store.activeProfile)」？", isPresented: $showDeleteProfile) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) {
                Task { await store.deleteActiveProfile() }
            }
        } message: {
            Text("该配置下的单节点标注、策略组覆盖、自定义规则及绑定的订阅地址都会一并撤销。")
        }
    }
}
