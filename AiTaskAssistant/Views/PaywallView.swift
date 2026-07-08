import SwiftUI
import RevenueCat

// Phase 1 (RevenueCat): native paywall styled with the app's own design system rather than
// RevenueCatUI's default, shown when a free-tier user hits the 5-task cap or taps a widget/Siri
// upsell. Presents the "default" offering's monthly/annual packages.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptions = SubscriptionService.shared

    @State private var selected: Package?
    @State private var isPurchasing = false
    @State private var errorMessage: String?

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
                    restoreButton
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
            ForEach(subscriptions.offering?.availablePackages ?? [], id: \.identifier) { package in
                packageRow(package)
            }
        }
    }

    private func packageRow(_ package: Package) -> some View {
        let isSelected = selected?.identifier == package.identifier
        return Button {
            selected = package
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(package.storeProduct.localizedTitle)
                        .font(Theme.Typography.body(15, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                    Text(package.storeProduct.localizedPriceString)
                        .font(Theme.Typography.meta)
                        .foregroundStyle(Theme.Color.mutedGrey)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.Color.limeDeep : Theme.Color.mutedGrey)
            }
            .padding(14)
            .background(Theme.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius)
                    .stroke(isSelected ? Theme.Color.limeDeep : Theme.Color.hairline, lineWidth: isSelected ? 2 : 1)
            )
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

    private var restoreButton: some View {
        Button("Restore Purchases") {
            restore()
        }
        .font(Theme.Typography.body(14))
        .foregroundStyle(Theme.Color.mutedGrey)
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

#Preview {
    PaywallView()
}
