import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: KeyringStore
    @EnvironmentObject private var purchases: PurchaseManager
    @AppStorage("keyring_start_fanned") private var startFanned: Bool = false
    @State private var activeSheet: KeyringSheet?
    @State private var showResetConfirm = false
    @State private var restoreMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Toggle("Start with keys fanned out", isOn: $startFanned)
                        .accessibilityIdentifier("startFannedToggle")
                }

                Section("Keyring Pro") {
                    if purchases.isPro {
                        Label("Pro unlocked", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(KRTheme.forest)
                    } else {
                        Button("Upgrade to Pro") {
                            activeSheet = .paywall
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("upgradeProButton")
                    }
                    Button("Restore Purchases") {
                        Task {
                            await purchases.restore()
                            restoreMessage = purchases.isPro ? "Purchases restored." : "No purchases found."
                        }
                    }
                    .buttonStyle(.plain)
                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.caption)
                            .foregroundStyle(KRTheme.inkFaded)
                    }
                }

                Section("About") {
                    Link("Privacy Policy", destination: URL(string: "https://shimondeitel.github.io/keyring-site/privacy.html")!)
                    Link("Contact Support", destination: URL(string: "mailto:s0533495227@gmail.com")!)
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0")
                            .foregroundStyle(KRTheme.inkFaded)
                    }
                }

                Section {
                    Button("Reset All Data", role: .destructive) {
                        showResetConfirm = true
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Reset all saved keys?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    store.deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .paywall:
                    PaywallView()
                default:
                    EmptyView()
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(KeyringStore())
        .environmentObject(PurchaseManager())
}
