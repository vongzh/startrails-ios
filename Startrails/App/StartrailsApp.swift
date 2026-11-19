import SwiftUI

@main
struct StartrailsApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentRootView()
                .environment(store)
                .task {
                    await store.bootstrap()
                }
                .onChange(of: scenePhase) { _, nextPhase in
                    switch nextPhase {
                    case .active:
                        store.refreshInstalledClients()
                        if store.isConnected {
                            store.checkClipboard()
                        }
                    case .background:
                        store.lockManager.lockIfNeeded()
                    default:
                        break
                    }
                }
        }
    }
}

struct ContentRootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            Group {
                if store.isConnected {
                    RootTabView()
                        .transition(.opacity)
                } else {
                    OnboardingLoginView()
                        .transition(.opacity)
                }
            }

            if store.isBootstrapping && !store.isConnected {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    VStack(spacing: 16) {
                        StarTrailsEmblem(size: 64)
                        ProgressView()
                            .controlSize(.regular)
                        Text("正在连接 Startrails 控制台...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
            }

            if store.lockManager.isLocked && store.isConnected {
                LockOverlayView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: store.isConnected)
        .animation(.easeInOut(duration: 0.22), value: store.isBootstrapping)
        .animation(.easeInOut(duration: 0.22), value: store.lockManager.isLocked)
        .overlay(alignment: .top) {
            if let toast = store.toast {
                ToastBannerView(notice: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.2)) {
                            store.toast = nil
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onEnded { value in
                                if value.translation.height < -10 {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        store.toast = nil
                                    }
                                }
                            }
                    )
            }
        }
        .animation(.spring(duration: 0.25), value: store.toast)
    }
}

struct ToastBannerView: View {
    let notice: ToastNotice

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isError ? Color.red : Color.green)
            Text(notice.text)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 16)
    }
}

struct LockOverlayView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                StarTrailsEmblem(size: 72)
                VStack(spacing: 6) {
                    Text("Startrails 已锁定")
                        .font(.title3.weight(.semibold))
                    Text("通过生物识别或设备密码解锁以管理订阅与令牌")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let err = store.lockManager.authError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button {
                    Task { await store.lockManager.unlock() }
                } label: {
                    Label(store.lockManager.biometricLabel, systemImage: store.lockManager.biometricIcon)
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(28)
        }
        .task {
            await store.lockManager.unlock()
        }
    }
}
