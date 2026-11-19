import SwiftUI

struct WorkspaceToolbarModifier: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var showSettings: Bool
    @Binding var showCreateProfile: Bool
    @Binding var showRenameProfile: Bool
    @Binding var showDeleteProfile: Bool
    @Binding var newProfileName: String

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Section("切换配置") {
                        ForEach(store.workspaceState?.profiles ?? []) { profile in
                            Button {
                                Task { await store.switchProfile(profile.name) }
                            } label: {
                                HStack {
                                    Text(profile.name)
                                    if profile.name == store.activeProfile {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        newProfileName = ""
                        showCreateProfile = true
                    } label: {
                        Label("新建配置...", systemImage: "plus.circle")
                    }
                    Button {
                        newProfileName = store.activeProfile
                        showRenameProfile = true
                    } label: {
                        Label("重命名「\(store.activeProfile)」...", systemImage: "pencil")
                    }
                    if (store.workspaceState?.profiles.count ?? 0) > 1 {
                        Button(role: .destructive) {
                            showDeleteProfile = true
                        } label: {
                            Label("删除当前配置「\(store.activeProfile)」", systemImage: "trash")
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text(store.activeProfile)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await store.reloadAll() }
                } label: {
                    if store.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .accessibilityLabel("刷新状态")

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("控制台设置")
            }
        }
    }
}

extension View {
    func workspaceToolbar(
        showSettings: Binding<Bool>,
        showCreateProfile: Binding<Bool>,
        showRenameProfile: Binding<Bool> = .constant(false),
        showDeleteProfile: Binding<Bool>,
        newProfileName: Binding<String>
    ) -> some View {
        modifier(WorkspaceToolbarModifier(
            showSettings: showSettings,
            showCreateProfile: showCreateProfile,
            showRenameProfile: showRenameProfile,
            showDeleteProfile: showDeleteProfile,
            newProfileName: newProfileName
        ))
    }
}
