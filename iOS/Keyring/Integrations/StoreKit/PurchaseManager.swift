import Foundation
import StoreKit
import Observation

@MainActor
@Observable
final class PurchaseManager: EntitlementProviding {
    static let proProductID = "keyring_pro_unlock"

    private(set) var isPurchased = false
    private(set) var product: Product?

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
            let products = try await Product.products(for: [Self.proProductID])
            product = products.first
        } catch {
            product = nil
        }
    }

    func purchase() async {
        guard let product else { return }
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
            if case .verified(let transaction) = result, transaction.productID == Self.proProductID {
                owned = true
            }
        }
        isPurchased = owned
    }
}
