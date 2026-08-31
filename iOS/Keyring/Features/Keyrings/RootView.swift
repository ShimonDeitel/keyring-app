import SwiftUI

/// Free users with one keyring go straight into it — the original app's
/// exact flow. Pro users (or anyone with more than one keyring) land on the
/// keyrings hub so they can navigate between rings.
struct RootView: View {
    @Environment(KeyringStore.self) private var store

    var body: some View {
        if store.isPro || store.keyrings.count > 1 {
            KeyringsListView()
        } else if let onlyRing = store.keyrings.first {
            KeyringDetailView(keyring: onlyRing, isRootRing: true)
        } else {
            ProgressView()
        }
    }
}
