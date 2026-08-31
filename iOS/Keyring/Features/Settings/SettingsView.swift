import SwiftUI

struct SettingsView: View {
    @Environment(KeyringStore.self) private var store
    @Environment(PurchaseManager.self) private var purchases
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

                if store.isPro {
                    Section("Pro") {
                        NavigationLink {
                            ActivityLogView()
                        } label: {
                            Label("Activity Log", systemImage: "clock.arrow.circlepath")
                        }
                    }
                } else if let onlyRing = store.keyrings.first {
                    Section("This Keyring") {
                        Button {
                            activeSheet = .editKeyring
                        } label: {
                            Label("Rename \"\(onlyRing.name)\"", systemImage: "pencil")
                        }
                        .buttonStyle(.plain)
                    }
                    .id(onlyRing.id)
                }

                Section("About") {
                    Link("Privacy Policy", destination: URL(string: "https://shimondeitel.github.io/keyring-site/privacy.html")!)
                    Link("Contact Support", destination: URL(string: "mailto:s0533495227@gmail.com")!)
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.appVersionDisplay)
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
                    for ring in store.keyrings { store.deleteKeyring(ring) }
                    store.createKeyring(name: "My Keys", icon: "key.fill", locationName: nil)
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .paywall:
                    PaywallView()
                case .editKeyring:
                    if let onlyRing = store.keyrings.first {
                        AddEditKeyringView(existing: onlyRing) { name, icon, location in
                            store.renameKeyring(onlyRing, name: name, icon: icon, locationName: location)
                        }
                    }
                case .add:
                    EmptyView()
                }
            }
        }
    }
}

extension Bundle {
    var appVersionDisplay: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
