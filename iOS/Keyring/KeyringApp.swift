import SwiftUI
import SwiftData

@main
struct KeyringApp: App {
    let modelContainer: ModelContainer
    @State private var store: KeyringStore
    @State private var purchases: PurchaseManager
    @State private var locationProvider = LocationProvider()
    @AppStorage("keyring_hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        let container = PersistenceController.makeContainer()
        modelContainer = container
        let purchaseManager = PurchaseManager()
        _purchases = State(initialValue: purchaseManager)
        let keyringStore = KeyringStore(context: container.mainContext, entitlements: purchaseManager)
        _store = State(initialValue: keyringStore)

        // UI tests exercise feature flows against a clean in-memory store and
        // don't need the onboarding screen in the way.
        if PersistenceController.isUITesting {
            UserDefaults.standard.set(true, forKey: "keyring_hasCompletedOnboarding")
        } else if !keyringStore.keyrings.isEmpty {
            // Upgrading users: migrated legacy data (or any pre-existing
            // keyring) means this is not a first launch.
            UserDefaults.standard.set(true, forKey: "keyring_hasCompletedOnboarding")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .environment(purchases)
                .environment(locationProvider)
                .modelContainer(modelContainer)
                .preferredColorScheme(.light)
                .task {
                    if store.keyrings.isEmpty {
                        store.createKeyring(name: "My Keys", icon: "key.fill", locationName: nil)
                    }
                }
                .fullScreenCover(isPresented: .init(
                    get: { !hasCompletedOnboarding },
                    set: { hasCompletedOnboarding = !$0 }
                )) {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                }
        }
    }
}
