import StoreKit
import SwiftUI
import UIKit

private struct TipTierMetadata: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let badge: String
    let title: String
    let subtitle: String
    let fallbackPrice: String
}

private let tipCatalog: [TipTierMetadata] = [
    TipTierMetadata(
        id: "com.vongzh.startrails.tip.coffee",
        icon: "cup.and.saucer.fill",
        tint: Color(red: 0.69, green: 0.33, blue: 0.19),
        badge: "日常心意",
        title: "请作者喝杯咖啡",
        subtitle: "一杯咖啡的能量，支持日常维护与问题修复",
        fallbackPrice: "¥6"
    ),
    TipTierMetadata(
        id: "com.vongzh.startrails.tip.support",
        icon: "heart.fill",
        tint: Color(red: 0.85, green: 0.48, blue: 0.14),
        badge: "推荐支持",
        title: "支持版本迭代",
        subtitle: "鼓励新客户端协议适配、测速与交互体验打磨",
        fallbackPrice: "¥18"
    ),
    TipTierMetadata(
        id: "com.vongzh.startrails.tip.sponsor",
        icon: "sparkles",
        tint: Color(red: 0.52, green: 0.35, blue: 0.82),
        badge: "深度赞助",
        title: "深度赞赏支持",
        subtitle: "感谢认可，助力 Startrails 长期稳定演进",
        fallbackPrice: "¥38"
    ),
]

private enum SupportLinks {
    static let afdianURL = URL(string: "https://afdian.com/a/vongzh")!
    static let afdianText = "https://afdian.com/a/vongzh"
    static let serverRepoURL = URL(string: "https://github.com/vongzh/startrails")!
    static let iosRepoURL = URL(string: "https://github.com/vongzh/startrails-ios")!
}

@Observable
@MainActor
final class TipJarModel {
    private(set) var productsById: [String: Product] = [:]
    private(set) var isLoading = false
    private(set) var hasCheckedStore = false
    private(set) var purchasingProductId: String?
    private(set) var purchaseError: String?
    var thankYouMessage: String?

    /// 是否成功从 App Store / TestFlight 获取到内购商品
    var isAppStoreAvailable: Bool {
        !productsById.isEmpty
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        purchaseError = nil
        defer {
            isLoading = false
            hasCheckedStore = true
        }
        do {
            let ids = tipCatalog.map(\.id)
            let fetched = try await Product.products(for: ids)
            var map: [String: Product] = [:]
            for product in fetched {
                map[product.id] = product
            }
            productsById = map
        } catch {
            productsById = [:]
        }
    }

    func purchase(productId: String, onSuccess: (String) -> Void) async {
        guard let product = productsById[productId] else { return }
        purchasingProductId = productId
        purchaseError = nil
        defer { purchasingProductId = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    Haptics.notify(.success)
                    let msg = "感谢支持！已收到你的心意（\(product.displayName)）。"
                    thankYouMessage = msg
                    onSuccess(msg)
                case .unverified(_, _):
                    purchaseError = "交易签名校验未通过，如已扣款请联系 Apple 客服处理。"
                }
            case .userCancelled:
                break
            case .pending:
                thankYouMessage = "订单已提交，等待系统确认后自动生效。"
            @unknown default:
                break
            }
        } catch {
            purchaseError = "发起购买失败：\(error.localizedDescription)"
        }
    }

    func observeTransactions() async {
        for await result in StoreKit.Transaction.updates {
            if case .verified(let transaction) = result {
                await transaction.finish()
            }
        }
    }
}

struct TipJarSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage("startrails.tip.count") private var tipCount = 0
    @State private var model = TipJarModel()
    @State private var selectedTierId = "com.vongzh.startrails.tip.support"

    var body: some View {
        NavigationStack {
            List {
                heroSection

                if let thanks = model.thankYouMessage {
                    Section {
                        HStack(spacing: 12) {
                            SettingsRowIcon(systemName: "heart.fill", tint: .pink)
                            Text(thanks)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if model.isAppStoreAvailable {
                    appStoreSection
                } else {
                    afdianSection
                }

                githubSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("请作者喝杯咖啡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                await model.loadProducts()
            }
            .task {
                await model.observeTransactions()
            }
        }
    }

    // MARK: - 顶部品牌卡片

    private var heroSection: some View {
        Section {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.orange.opacity(0.22),
                                    Color.brown.opacity(0.08),
                                    Color.clear,
                                ],
                                center: .center,
                                startRadius: 4,
                                endRadius: 44
                            )
                        )
                        .frame(width: 84, height: 84)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.16, green: 0.22, blue: 0.40),
                                    Color(red: 0.08, green: 0.12, blue: 0.24),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                        )
                        .shadow(color: Color.black.opacity(0.16), radius: 8, y: 4)

                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.92, blue: 0.70),
                                    Color(red: 0.94, green: 0.68, blue: 0.28),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                VStack(spacing: 6) {
                    Text("全部功能免费 · 感谢用爱发电")
                        .font(.headline)

                    Text("Startrails 客户端无任何功能限制、广告或订阅锁。如果它帮你省去了繁琐的订阅整理时间，欢迎请作者喝杯咖啡，或在 GitHub 点亮一颗 Star。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if tipCount > 0 {
                    BadgePill(
                        text: "已累计支持 \(tipCount) 次 · 衷心感谢陪伴",
                        tint: Color(red: 0.69, green: 0.33, blue: 0.19)
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    // MARK: - App Store 内购支持

    private var appStoreSection: some View {
        Section {
            ForEach(tipCatalog) { tier in
                let product = model.productsById[tier.id]
                let isBuying = model.purchasingProductId == tier.id

                HStack(spacing: 12) {
                    SettingsRowIcon(systemName: tier.icon, tint: tier.tint)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(product?.displayName ?? tier.title)
                                .font(.subheadline.weight(.semibold))
                            BadgePill(text: tier.badge, tint: tier.tint)
                        }
                        Text(product?.description.isEmpty == false ? (product?.description ?? tier.subtitle) : tier.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Button {
                        Haptics.impact(.light)
                        Task {
                            await model.purchase(productId: tier.id) { msg in
                                tipCount += 1
                                store.showToast(msg)
                            }
                        }
                    } label: {
                        if isBuying {
                            ProgressView()
                                .controlSize(.small)
                                .frame(minWidth: 54)
                        } else {
                            Text(product?.displayPrice ?? tier.fallbackPrice)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .frame(minWidth: 54)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(tier.tint)
                    .disabled(product == nil || model.purchasingProductId != nil)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("App Store 赞赏档位")
        } footer: {
            if let error = model.purchaseError {
                Text(error)
                    .foregroundStyle(.red)
            } else {
                Text("赞赏属于一次性消耗型 App 内购买，由 Apple 安全结算，不会产生自动续费。")
            }
        }
    }

    // MARK: - 爱发电赞赏支持

    private var afdianSection: some View {
        Section {
            ForEach(tipCatalog) { tier in
                let isSelected = selectedTierId == tier.id

                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                        selectedTierId = tier.id
                    }
                    Haptics.impact(.light)
                } label: {
                    HStack(spacing: 12) {
                        SettingsRowIcon(systemName: tier.icon, tint: tier.tint)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(tier.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                BadgePill(text: tier.badge, tint: tier.tint)
                            }
                            Text(tier.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 8)

                        HStack(spacing: 6) {
                            Text(tier.fallbackPrice)
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(tier.tint)
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(isSelected ? tier.tint : Color(.tertiaryLabel))
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 10) {
                Button {
                    Haptics.impact(.medium)
                    tipCount += 1
                    openURL(SupportLinks.afdianURL)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.heart.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("前往爱发电支持作者")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.58, green: 0.38, blue: 0.88),
                                Color(red: 0.76, green: 0.36, blue: 0.62),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    UIPasteboard.general.string = SupportLinks.afdianText
                    Haptics.notify(.success)
                    store.showToast("已复制爱发电主页链接")
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                        Text("复制链接：afdian.com/a/vongzh")
                            .font(.caption.monospaced())
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)
        } header: {
            HStack {
                Text("通过爱发电支持")
                Spacer()
                if model.isLoading {
                    ProgressView().controlSize(.mini)
                }
            }
        } footer: {
            Text("点击上方按钮可在浏览器打开爱发电主页（afdian.com/a/vongzh），支持自选档位或任意金额赞赏。")
        }
    }

    // MARK: - GitHub Star 开源社区支持

    private var githubSection: some View {
        Section {
            Button {
                Haptics.impact(.light)
                openURL(SupportLinks.serverRepoURL)
            } label: {
                HStack(spacing: 12) {
                    SettingsRowIcon(systemName: "star.fill", tint: Color.amberStar)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("为 Startrails 核心仓库点亮 Star")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("github.com/vongzh/startrails")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Haptics.impact(.light)
                openURL(SupportLinks.iosRepoURL)
            } label: {
                HStack(spacing: 12) {
                    SettingsRowIcon(systemName: "iphone.gen3", tint: .indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("为 Startrails iOS 仓库点亮 Star")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("github.com/vongzh/startrails-ios")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("开源与社区支持")
        } footer: {
            Text("在 GitHub 点亮一颗 Star 或提交反馈，同样是对项目最有力的支持。")
        }
    }
}

private extension Color {
    static let amberStar = Color(red: 0.88, green: 0.58, blue: 0.14)
}
