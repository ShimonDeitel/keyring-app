import SwiftUI

/// Pro hub shown when there's more than one keyring — a home-screen-style
/// list of rings, with global search and a "Keys Out" roll-up across rings.
struct KeyringsListView: View {
    @Environment(KeyringStore.self) private var store
    @State private var showAddKeyring = false
    @State private var showPaywall = false
    @State private var searchText = ""

    private var searchResults: [(keyring: KeyringEntity, key: KeyEntity)] {
        store.search(searchText)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KRTheme.backdrop.ignoresSafeArea()
                List {
                    if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Section("Results") {
                            ForEach(searchResults, id: \.key.id) { result in
                                NavigationLink {
                                    KeyDetailView(key: result.key)
                                } label: {
                                    KeyRow(key: result.key)
                                }
                            }
                        }
                    } else {
                        if !store.allLoanedKeys.isEmpty {
                            Section("Keys Out") {
                                ForEach(store.allLoanedKeys, id: \.key.id) { result in
                                    NavigationLink {
                                        KeyDetailView(key: result.key)
                                    } label: {
                                        KeyRow(key: result.key)
                                    }
                                }
                            }
                        }
                        Section("Keyrings") {
                            ForEach(store.keyrings) { keyring in
                                NavigationLink {
                                    KeyringDetailView(keyring: keyring, isRootRing: false)
                                } label: {
                                    KeyringRowView(keyring: keyring, isPro: store.isPro)
                                }
                            }
                            .onDelete { offsets in
                                for index in offsets { store.deleteKeyring(store.keyrings[index]) }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .searchable(text: $searchText, prompt: "Search all keys")
            }
            .navigationTitle("Keyrings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddKeyring = store.canCreateKeyring ? true : false
                        if !store.canCreateKeyring { showPaywall = true }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(KRTheme.brass)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addKeyringButton")
                }
            }
            .sheet(isPresented: $showAddKeyring) {
                AddEditKeyringView(existing: nil) { name, icon, location in
                    store.createKeyring(name: name, icon: icon, locationName: location)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }
}
