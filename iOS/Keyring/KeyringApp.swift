import SwiftUI

@main
struct KeyringApp: App {
    @StateObject private var store = KeyringStore()
    @StateObject private var purchases = PurchaseManager()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environmentObject(purchases)
                .preferredColorScheme(.light)
        }
    }
}
