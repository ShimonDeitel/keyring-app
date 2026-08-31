import Foundation

/// Free tier plan limits. These are plan limits, not rate limits: they never
/// hide, delete, or corrupt data a Pro downgrade would otherwise still own.
enum PlanLimits {
    static let freeMaxKeyrings = 1
    static let freeMaxKeysPerKeyring = 5
}

/// Abstraction over the entitlement source (StoreKit today, could be anything
/// in tests) so repositories and stores never talk to StoreKit directly.
@MainActor
protocol EntitlementProviding: AnyObject {
    var isPro: Bool { get }
}
