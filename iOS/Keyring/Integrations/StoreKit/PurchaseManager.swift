import Foundation
import StoreKit
import Observation

@MainActor
@Observable
final class PurchaseManager: EntitlementProviding {
    /// Original one-time unlock -- kept forever so existing purchasers never
    /// lose Pro. New purchases lead with the subscription (utility-app
    /// standing pricing policy: monthly recurring, not one-time) but this
    /// product ID must never change or be removed from ASC.
    static let proProductID = "keyring_pro_unlock"
    static let proMonthlyID = "keyring_pro_monthly"

    private(set) var isPurchased = false
    private(set) var product: Product?
    private(set) var monthlyProduct: Product?

    var isPro: Bool { isPurchased }

    private nonisolated(unsafe) var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self.refreshPurchasedState()
                }
            }
        }
        Task {
            await loadProduct()
            await refreshPurchasedState()
        }
    }

    deinit { updatesTask?.cancel() }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.proProductID, Self.proMonthlyID])
            product = products.first { $0.id == Self.proProductID }
            monthlyProduct = products.first { $0.id == Self.proMonthlyID }
        } catch {
            product = nil
            monthlyProduct = nil
        }
    }

    /// Buys the monthly subscription -- the default, primary path from the paywall.
    func purchaseMonthly() async {
        guard let monthlyProduct else { return }
        await purchase(monthlyProduct)
    }

    /// Buys the legacy one-time unlock -- offered as a secondary option for
    /// anyone who prefers it, never removed as a purchasable product.
    func purchase() async {
        guard let product else { return }
        await purchase(product)
    }

    private func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result, case .verified(let transaction) = verification {
                await transaction.finish()
                await refreshPurchasedState()
            }
        } catch {
            // user cancelled or purchase failed; no-op
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshPurchasedState()
    }

    func refreshPurchasedState() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.proProductID || transaction.productID == Self.proMonthlyID {
                owned = true
            }
        }
        isPurchased = owned
    }
}
