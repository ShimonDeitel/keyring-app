import SwiftUI

struct KeyringDetailView: View {
    @Environment(KeyringStore.self) private var store
    @Bindable var keyring: KeyringEntity
    var isRootRing: Bool = true

    @State private var activeSheet: KeyringSheet?
    @State private var deletingKey: KeyEntity?
    @State private var isFanned = false
    @State private var searchText = ""

    private var filteredKeys: [KeyEntity] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return keyring.sortedKeys }
        let q = searchText.lowercased()
        return keyring.sortedKeys.filter {
            $0.name.lowercased().contains(q) || $0.opens.lowercased().contains(q) || $0.category.displayName.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KRTheme.backdrop.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        if keyring.sortedKeys.isEmpty {
                            EmptyStateView(
                                systemImage: "key",
                                title: "No keys identified yet",
                                message: "Tap + to add a key, note what it opens, and photograph it so you recognize it later.",
                                actionTitle: "Add a Key",
                                action: attemptAddKey
                            )
                        } else {
                            KeyRingFanView(keys: keyring.sortedKeys, isFanned: $isFanned)
                                .padding(.horizontal, 18)
                                .padding(.bottom, 8)

                            if store.isPro, !keyring.loanedKeys.isEmpty {
                                Text("KEYS OUT")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(KRTheme.inkFaded)
                                    .padding(.horizontal, 18)
                                VStack(spacing: 12) {
                                    ForEach(keyring.loanedKeys) { key in
                                        NavigationLink(value: key) {
                                            KeyRow(key: key)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 18)
                            }

                            VStack(spacing: 12) {
                                ForEach(filteredKeys) { key in
                                    NavigationLink(value: key) {
                                        KeyRow(key: key)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("keyRow_\(key.name)")
                                }
                            }
                            .padding(.horizontal, 18)

                            if !store.isPro {
                                Text("Free plan: \(keyring.keyCount)/\(PlanLimits.freeMaxKeysPerKeyring) keys identified")
                                    .font(.caption)
                                    .foregroundStyle(KRTheme.inkFaded)
                                    .padding(.horizontal, 18)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .searchable(text: $searchText, prompt: "Search keys")
            }
            .navigationBarHidden(true)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .add:
                    KeyFormView(keyring: keyring, existing: nil)
                case .editKeyring:
                    AddEditKeyringView(existing: keyring) { name, icon, location in
                        store.renameKeyring(keyring, name: name, icon: icon, locationName: location)
                    }
                case .paywall:
                    PaywallView()
                }
            }
            .confirmationDialog(
                "Delete this key?",
                isPresented: Binding(get: { deletingKey != nil }, set: { if !$0 { deletingKey = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let deletingKey { store.deleteKey(deletingKey) }
                    self.deletingKey = nil
                }
                Button("Cancel", role: .cancel) { deletingKey = nil }
            }
            .navigationDestination(for: KeyEntity.self) { key in
                KeyDetailView(key: key)
            }
        }
    }

    private var header: some View {
        HStack {
            if isRootRing {
                Text("Keyring")
                    .font(KRTheme.titleFont)
                    .foregroundStyle(KRTheme.ink)
            } else {
                Button {
                    activeSheet = .editKeyring
                } label: {
                    HStack(spacing: 6) {
                        Text(keyring.name)
                            .font(KRTheme.titleFont)
                            .foregroundStyle(KRTheme.ink)
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(KRTheme.inkFaded)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                attemptAddKey()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(KRTheme.brass)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addKeyButton")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private func attemptAddKey() {
        activeSheet = store.canAddKey(to: keyring) ? .add : .paywall
    }
}

enum KeyringSheet: Identifiable {
    case add
    case editKeyring
    case paywall

    var id: String {
        switch self {
        case .add: return "add"
        case .editKeyring: return "editKeyring"
        case .paywall: return "paywall"
        }
    }
}

/// The quirky signature feature: keys hang bunched on a literal ring
/// graphic; tapping the ring spreads (fans) them out into an arc with a
/// spring animation, tap again to collapse them back together.
struct KeyRingFanView: View {
    let keys: [KeyEntity]
    @Binding var isFanned: Bool

    private let ringDiameter: CGFloat = 64
    private let fannedRadius: CGFloat = 110

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ForEach(Array(keys.prefix(8).enumerated()), id: \.offset) { index, key in
                    KeyPhotoView(photoData: key.photoData, symbolName: key.category.symbolName, size: 40)
                        .offset(fannedOffset(index: index, total: min(keys.count, 8)))
                        .rotationEffect(.degrees(isFanned ? fannedAngle(index: index, total: min(keys.count, 8)) : 0))
                        .zIndex(Double(keys.count - index))
                }

                Circle()
                    .strokeBorder(KRTheme.brass, lineWidth: 6)
                    .frame(width: ringDiameter, height: ringDiameter)
                    .background(Circle().fill(KRTheme.backdrop))
            }
            .frame(height: isFanned ? fannedRadius * 2 + 40 : 140)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("keyRingFanToggle")
            .accessibilityAddTraits(.isButton)
            .onTapGesture {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                    isFanned.toggle()
                }
            }

            Text(isFanned ? "Tap the ring to gather keys" : "Tap the ring to fan out keys")
                .font(.caption)
                .foregroundStyle(KRTheme.inkFaded)
        }
    }

    private func fannedOffset(index: Int, total: Int) -> CGSize {
        guard isFanned, total > 0 else { return .zero }
        let angleStep = 160.0 / Double(max(total - 1, 1))
        let angle = Angle.degrees(-80 + angleStep * Double(index)).radians
        let x = CGFloat(sin(angle)) * fannedRadius
        let y = CGFloat(1 - cos(angle)) * fannedRadius * 0.6 + 40
        return CGSize(width: x, height: y)
    }

    private func fannedAngle(index: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        let angleStep = 160.0 / Double(max(total - 1, 1))
        return -80 + angleStep * Double(index)
    }
}

struct KeyRow: View {
    let key: KeyEntity

    var body: some View {
        HStack(spacing: 14) {
            KeyPhotoView(photoData: key.photoData, symbolName: key.category.symbolName, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(key.name)
                        .font(KRTheme.headlineFont)
                        .foregroundStyle(KRTheme.ink)
                    if key.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(KRTheme.brass)
                    }
                }
                if !key.notes.isEmpty {
                    Text(key.notes)
                        .font(.subheadline)
                        .foregroundStyle(KRTheme.inkFaded)
                }
                if let status = key.statusLabel {
                    StatusBadge(text: status, color: statusColor)
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KRTheme.inkFaded.opacity(0.6))
        }
        .padding(12)
        .background(KRTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(KRTheme.rule, lineWidth: 1)
        )
    }

    private var statusColor: Color {
        if key.isLost { return KRTheme.lostColor }
        if key.isLoaned { return KRTheme.loanedColor }
        return KRTheme.spareColor
    }
}
