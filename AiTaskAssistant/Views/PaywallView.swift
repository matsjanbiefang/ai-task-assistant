import SwiftUI
import RevenueCat

// Phase 1 (RevenueCat): native paywall styled with the app's own design system rather than
// RevenueCatUI's default, shown when a free-tier user hits the 5-task cap or taps a widget/Siri
// upsell, or opens it directly from Settings.
//
// Real-device feedback: restructured to match a reference paywall's layout order — feature
// checklist first, two stacked pricing cards (not a toggle) with a badge on the recommended one,
// then the trial CTA, fine print, legal links, and an explicit "Continue with free version" skip
// — while keeping TaskMind's own paper/ink/lime look rather than copying the reference's dark
// theme.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptions = SubscriptionService.shared

    @State private var selected: Package?
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var legalPage: LegalPage?

    private enum LegalPage: String, Identifiable {
        case privacy = "Privacy Policy", terms = "Terms of Use"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    featureList
                    packages
                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.Typography.meta)
                            .foregroundStyle(.red)
                    }
                    purchaseButton
                    finePrint
                    legalLinks
                    continueFreeLink
                }
                .padding(20)
            }
            .background(Theme.Color.paper)
            .navigationTitle("TaskMind Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $legalPage) { page in
                PaywallLegalPlaceholderView(title: page.rawValue)
            }
        }
        .task {
            await subscriptions.fetchOfferings()
            selected = subscriptions.offering?.availablePackages.first { $0.packageType == .annual }
                ?? subscriptions.offering?.availablePackages.first
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Unlock TaskMind Pro")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Color.ink)
            Text("Unlimited tasks and every widget, with a 1-week free trial.")
                .font(Theme.Typography.body(15))
                .foregroundStyle(Theme.Color.mutedGrey)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            featureRow("infinity", "Unlimited active tasks — free is capped at 5")
            featureRow("square.grid.2x2.fill", "Home Screen and Lock Screen widgets")
            featureRow("mic.fill", "Siri, speech-to-text, and every language stay free either way")
        }
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.Color.limeDeep)
                .frame(width: 20)
            Text(text)
                .font(Theme.Typography.body(14))
                .foregroundStyle(Theme.Color.ink)
        }
    }

    private var packages: some View {
        VStack(spacing: 10) {
            ForEach(sortedPackages, id: \.identifier) { package in
                packageCard(package)
            }
        }
    }

    // Annual first (it's the one carrying the "Best Value" badge), matching the reference's
    // top-to-bottom yearly-then-monthly order.
    private var sortedPackages: [Package] {
        (subscriptions.offering?.availablePackages ?? []).sorted {
            $0.packageType == .annual && $1.packageType != .annual
        }
    }

    private func packageCard(_ package: Package) -> some View {
        let isSelected = selected?.identifier == package.identifier
        let isAnnual = package.packageType == .annual
        return Button {
            selected = package
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if isAnnual {
                    HStack {
                        Spacer()
                        Text("Best Value")
                            .font(Theme.Typography.meta.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.Color.lime, in: Capsule())
                            .foregroundStyle(Theme.Color.ink)
                    }
                }
                Text(package.storeProduct.localizedTitle)
                    .font(Theme.Typography.body(15, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                Text(package.storeProduct.localizedPriceString)
                    .font(Theme.Typography.display(22, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                    + Text(isAnnual ? " / year" : " / month")
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.Color.mutedGrey)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(SwiftUI.Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius)
                    .stroke(isSelected ? Theme.Color.limeDeep : Theme.Color.hairline, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
        }
        .buttonStyle(.plain)
    }

    private var purchaseButton: some View {
        Button {
            purchase()
        } label: {
            HStack {
                if isPurchasing { ProgressView().tint(Theme.Color.ink) }
                Text("Start Free Trial")
                    .font(Theme.Typography.body(16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.Color.lime)
        .foregroundStyle(Theme.Color.ink)
        .disabled(selected == nil || isPurchasing)
    }

    private var finePrint: some View {
        Text("Subscription renews automatically unless cancelled at least 24 hours before the end of the current period. Manage in App Store Settings.")
            .font(Theme.Typography.meta)
            .foregroundStyle(Theme.Color.mutedGrey)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }

    // Real-device feedback: match the reference's exact line grouping — Restore Purchase on its
    // own line, Privacy Policy / Terms of Use together underneath.
    private var legalLinks: some View {
        VStack(spacing: 8) {
            Button("Restore Purchases") { restore() }
            HStack(spacing: 6) {
                Button("Privacy Policy") { legalPage = .privacy }
                    .underline()
                Text("·")
                Button("Terms of Use") { legalPage = .terms }
                    .underline()
            }
        }
        .frame(maxWidth: .infinity)
        .font(Theme.Typography.meta)
        .foregroundStyle(Theme.Color.mutedGrey)
        .buttonStyle(.plain)
    }

    private var continueFreeLink: some View {
        Button("Continue with free version") { dismiss() }
            .font(Theme.Typography.body(14))
            .foregroundStyle(Theme.Color.mutedGrey)
            .underline()
            .frame(maxWidth: .infinity)
    }

    private func purchase() {
        guard let package = selected else { return }
        isPurchasing = true
        errorMessage = nil
        Task {
            do {
                try await subscriptions.purchase(package: package)
                isPurchasing = false
                if subscriptions.isPremium { dismiss() }
            } catch {
                isPurchasing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restore() {
        isPurchasing = true
        errorMessage = nil
        Task {
            do {
                try await subscriptions.restorePurchases()
                isPurchasing = false
                if subscriptions.isPremium { dismiss() }
            } catch {
                isPurchasing = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct PaywallLegalPlaceholderView: View {
    let title: String
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Placeholder — the full \(title.lowercased()) will go here before this app is submitted for review.")
                        .font(Theme.Typography.body(15))
                        .foregroundStyle(Theme.Color.mutedGrey)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Theme.Color.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    PaywallView()
}
