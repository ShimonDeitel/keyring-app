import SwiftUI

struct KeyringHomeView: View {
    @EnvironmentObject private var store: KeyringStore
    @EnvironmentObject private var purchases: PurchaseManager
    @State private var activeSheet: KeyringSheet?
    @State private var deletingKey: KeyItem?
    @State private var isFanned = false

    var body: some View {
        NavigationStack {
            ZStack {
                KRTheme.backdrop.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("Keyring")
                                .font(KRTheme.titleFont)
                                .foregroundStyle(KRTheme.ink)
                            Spacer()
                            Button {
                                if store.canAddKey(isPro: purchases.isPro) {
                                    activeSheet = .add
                                } else {
                                    activeSheet = .paywall
                                }
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

                        if store.keys.isEmpty {
                            emptyState
                        } else {
                            KeyRingFanView(keys: store.keys, isFanned: $isFanned)
                                .padding(.horizontal, 18)
                                .padding(.bottom, 8)

                            VStack(spacing: 12) {
                                ForEach(store.keys) { key in
                                    KeyRow(
                                        key: key,
                                        onEdit: { activeSheet = .edit(key) },
                                        onDelete: { deletingKey = key }
                                    )
                                    .accessibilityIdentifier("keyRow_\(key.label)")
                                }
                            }
                            .padding(.horizontal, 18)

                            if !purchases.isPro {
                                Text("Free plan: \(store.keys.count)/\(KeyringStore.freeKeyLimit) keys identified")
                                    .font(.caption)
                                    .foregroundStyle(KRTheme.inkFaded)
                                    .padding(.horizontal, 18)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .add:
                    KeyFormView(existing: nil)
                case .edit(let key):
                    KeyFormView(existing: key)
                case .paywall:
                    PaywallView()
                }
            }
            .confirmationDialog(
                "Delete this key?",
                isPresented: Binding(
                    get: { deletingKey != nil },
                    set: { if !$0 { deletingKey = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let deletingKey {
                        store.deleteKey(deletingKey.id)
                    }
                    self.deletingKey = nil
                }
                Button("Cancel", role: .cancel) {
                    deletingKey = nil
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "key")
                .font(.system(size: 48))
                .foregroundStyle(KRTheme.inkFaded)
            Text("No keys identified yet")
                .font(KRTheme.headlineFont)
                .foregroundStyle(KRTheme.ink)
            Text("Tap + to add a key, note what it opens, and photograph it so you recognize it later.")
                .font(.subheadline)
                .foregroundStyle(KRTheme.inkFaded)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Add a Key") {
                if store.canAddKey(isPro: purchases.isPro) {
                    activeSheet = .add
                } else {
                    activeSheet = .paywall
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(KRTheme.brass)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .padding(.top, 60)
        .padding(.horizontal, 18)
    }
}

/// The quirky signature feature: keys hang bunched on a literal ring
/// graphic; tapping the ring spreads (fans) them out into an arc with a
/// spring animation, tap again to collapse them back together.
struct KeyRingFanView: View {
    let keys: [KeyItem]
    @Binding var isFanned: Bool

    private let ringDiameter: CGFloat = 64
    private let fannedRadius: CGFloat = 110

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ForEach(Array(keys.prefix(8).enumerated()), id: \.offset) { index, key in
                    keyGlyph(for: key)
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

    private func keyGlyph(for key: KeyItem) -> some View {
        ZStack {
            Circle()
                .fill(KRTheme.surface)
                .frame(width: 40, height: 40)
                .overlay(Circle().stroke(KRTheme.rule, lineWidth: 1))
            if let data = key.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
            } else {
                Image(systemName: "key.fill")
                    .foregroundStyle(KRTheme.brassBright)
            }
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
    let key: KeyItem
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onEdit) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(KRTheme.surfaceRaised)
                            .frame(width: 48, height: 48)
                        if let data = key.photoData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 42, height: 42)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "key.fill")
                                .foregroundStyle(KRTheme.brass)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(key.label)
                            .font(KRTheme.headlineFont)
                            .foregroundStyle(KRTheme.ink)
                        if !key.note.isEmpty {
                            Text(key.note)
                                .font(.subheadline)
                                .foregroundStyle(KRTheme.inkFaded)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Menu {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(KRTheme.inkFaded)
                    .padding(8)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("keyMenu_\(key.label)")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .padding(12)
        .background(KRTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(KRTheme.rule, lineWidth: 1)
        )
    }
}

#Preview {
    KeyringHomeView()
        .environmentObject(KeyringStore())
        .environmentObject(PurchaseManager())
}
