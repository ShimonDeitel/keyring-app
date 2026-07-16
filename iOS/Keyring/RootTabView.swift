import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            KeyringHomeView()
                .tabItem {
                    Label("Keys", systemImage: "key.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(KRTheme.brass)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(KRTheme.surface)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(KeyringStore())
        .environmentObject(PurchaseManager())
}
