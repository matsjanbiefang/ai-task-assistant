import Foundation
import RevenueCat

// Phase 1 (RevenueCat): single source of truth for entitlement state and the free-tier task cap.
// Mirrors NotificationService's singleton-service pattern. Entitlement identifier ("premium") and
// offering identifier ("default") are configured in the RevenueCat dashboard for the "TaskMind AI"
// project, project 2277d68b.
@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    /// Free tier: capped at 5 active (non-completed) tasks, no widgets. Everything else is free.
    static let freeTaskLimit = 5

    private static let entitlementID = "premium"
    private static let apiKey = "appl_TIxauYebDIuuHGDoykkvFDrsjPs"
    // Widgets (Phase 3) run in a separate process and can't call the Purchases SDK directly, so
    // entitlement state is mirrored into the shared App Group container on every refresh.
    private static let appGroupID = "group.com.matsb.AiTaskAssistant"
    private static let sharedDefaultsKey = "isPremium"

    @Published private(set) var isPremium = false
    @Published private(set) var offering: Offering?

    private init() {}

    func configure() {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Self.apiKey)
        Purchases.shared.delegate = self
        Task { await refreshCustomerInfo() }
    }

    func refreshCustomerInfo() async {
        guard let info = try? await Purchases.shared.customerInfo() else { return }
        apply(info)
    }

    func fetchOfferings() async {
        guard let offerings = try? await Purchases.shared.offerings() else { return }
        offering = offerings.current
    }

    func purchase(package: Package) async throws {
        let result = try await Purchases.shared.purchase(package: package)
        apply(result.customerInfo)
    }

    func restorePurchases() async throws {
        let info = try await Purchases.shared.restorePurchases()
        apply(info)
    }

    /// Called before inserting a new `TaskItem`. `currentOpenCount` is the number of existing
    /// non-completed tasks (callers pass `openTasks.count`, incrementing locally across multiple
    /// tasks split from a single note line).
    func canCreateTask(currentOpenCount: Int) -> Bool {
        isPremium || currentOpenCount < Self.freeTaskLimit
    }

    private func apply(_ info: CustomerInfo) {
        isPremium = info.entitlements[Self.entitlementID]?.isActive == true
        UserDefaults(suiteName: Self.appGroupID)?.set(isPremium, forKey: Self.sharedDefaultsKey)
    }
}

extension SubscriptionService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in apply(customerInfo) }
    }
}
