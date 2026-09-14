import SwiftUI
import MapKit
import UserNotifications

struct KeyDetailView: View {
    @Environment(KeyringStore.self) private var store
    @Environment(LocationProvider.self) private var locationProvider
    @Environment(\.dismiss) private var dismiss

    @Bindable var key: KeyEntity

    @State private var showEdit = false
    @State private var showLoanSheet = false
    @State private var showPaywall = false
    @State private var showDeleteConfirm = false
    @State private var locationErrorMessage: String?
    @State private var isConfirmingLocation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KRTheme.Spacing.lg) {
                header
                statusRow
                if store.hasAdvancedFeatures {
                    locationSection
                } else {
                    basicLocationSection
                }
                if key.isLoaned {
                    loanSection
                }
                if !key.notes.isEmpty {
                    detailSection(title: "Notes", text: key.notes)
                }
                if store.hasAdvancedFeatures {
                    historySection
                } else {
                    upgradeHistoryTeaser
                }
            }
            .padding(KRTheme.Spacing.md)
        }
        .background(KRTheme.backdrop.ignoresSafeArea())
        .navigationTitle(key.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEdit = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button {
                        store.toggleFavorite(key)
                    } label: {
                        Label(key.isFavorite ? "Unfavorite" : "Favorite", systemImage: key.isFavorite ? "star.slash" : "star")
                    }
                    Divider()
                    Button {
                        proGate { showLoanSheet = true }
                    } label: {
                        Label(key.isLoaned ? "Update Loan" : "Loan Key", systemImage: "arrow.up.right")
                    }
                    if key.isLoaned {
                        Button {
                            store.markReturned(key)
                        } label: {
                            Label("Mark Returned", systemImage: "arrow.down.left")
                        }
                    }
                    Button {
                        proGate { key.isSpare.toggle() }
                    } label: {
                        Label(key.isSpare ? "Unmark Spare" : "Mark as Spare", systemImage: "doc.on.doc")
                    }
                    if key.isLost {
                        Button {
                            proGate { store.markFound(key) }
                        } label: {
                            Label("Mark Found", systemImage: "checkmark.circle")
                        }
                    } else {
                        Button(role: .destructive) {
                            proGate { store.markLost(key) }
                        } label: {
                            Label("Mark Lost", systemImage: "exclamationmark.triangle")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Key", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(KRTheme.brass)
                }
                .accessibilityIdentifier("keyMenu_\(key.name)")
            }
        }
        .sheet(isPresented: $showEdit) {
            KeyFormView(keyring: key.keyring ?? KeyringEntity(name: ""), existing: key)
        }
        .sheet(isPresented: $showLoanSheet) {
            LoanKeySheet(existing: key) { person, expectedReturn in
                store.markLoaned(key, to: person, expectedReturn: expectedReturn)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .alert("Couldn't confirm location", isPresented: .constant(locationErrorMessage != nil), presenting: locationErrorMessage) { _ in
            Button("OK") { locationErrorMessage = nil }
        } message: { message in
            Text(message)
        }
        .confirmationDialog("Delete this key?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.deleteKey(key)
                dismiss()
            }
        }
    }

    private func proGate(_ action: @escaping () -> Void) {
        if store.isPro {
            action()
        } else {
            showPaywall = true
        }
    }

    private var header: some View {
        HStack(spacing: KRTheme.Spacing.md) {
            KeyPhotoView(photoData: key.photoData, symbolName: key.category.symbolName, tintColor: key.category.color, size: 88)
            VStack(alignment: .leading, spacing: 4) {
                Text(key.name)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(KRTheme.ink)
                if !key.opens.isEmpty {
                    Text("Opens \(key.opens)")
                        .font(.subheadline)
                        .foregroundStyle(KRTheme.inkFaded)
                }
                Label(key.category.displayName, systemImage: key.category.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(key.category.color)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if key.isLost || key.isLoaned || key.isSpare {
            HStack(spacing: 8) {
                if key.isLost { StatusBadge(text: "Lost", color: KRTheme.lostColor) }
                if key.isLoaned { StatusBadge(text: "Loaned", color: KRTheme.loanedColor) }
                if key.isSpare { StatusBadge(text: "Spare", color: KRTheme.spareColor) }
            }
        }
    }

    private var basicLocationSection: some View {
        cardSection {
            Text("KEPT AT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KRTheme.inkFaded)
            Text(key.assignedLocationName?.isEmpty == false ? key.assignedLocationName! : "Not set — edit this key to add one")
                .font(.body)
                .foregroundStyle(KRTheme.ink)
        }
    }

    private var locationSection: some View {
        cardSection {
            Text("LAST CONFIRMED")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KRTheme.inkFaded)
            Text(key.lastConfirmedLocationName ?? key.assignedLocationName ?? "Not confirmed yet")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(KRTheme.ink)
            if let confirmedAt = key.lastConfirmedAt {
                Text("Confirmed \(confirmedAt.keyringRelativeDescription)")
                    .font(.caption)
                    .foregroundStyle(KRTheme.inkFaded)
            }
            if let lat = key.lastConfirmedLatitude, let lon = key.lastConfirmedLongitude {
                LastConfirmedLocationMap(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: KRTheme.smallCorner))
                    .padding(.vertical, 4)
            }
            Button {
                confirmCurrentLocation()
            } label: {
                HStack {
                    if isConfirmingLocation {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "location.fill")
                    }
                    Text("Confirm My Location")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(KRTheme.brass)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: KRTheme.smallCorner))
            }
            .buttonStyle(.plain)
            .disabled(isConfirmingLocation)
            .padding(.top, 4)
            .accessibilityIdentifier("confirmLocationButton")
        }
    }

    private func confirmCurrentLocation() {
        isConfirmingLocation = true
        Task {
            do {
                let result = try await locationProvider.confirmCurrentLocation()
                store.confirmLocation(for: key, name: result.name, latitude: result.coordinate.latitude, longitude: result.coordinate.longitude)
            } catch LocationProviderError.denied {
                locationErrorMessage = "Keyring needs Location access to confirm where this key is. Enable it in Settings."
            } catch {
                locationErrorMessage = "Something went wrong getting your location. Try again."
            }
            isConfirmingLocation = false
        }
    }

    private var loanSection: some View {
        cardSection {
            Text("LOANED TO")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KRTheme.inkFaded)
            Text(key.loanedTo ?? "Unknown")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(KRTheme.ink)
            if let loanDate = key.loanDate {
                Text("Since \(loanDate.keyringRelativeDescription)")
                    .font(.caption)
                    .foregroundStyle(KRTheme.inkFaded)
            }
            if let expected = key.expectedReturnDate {
                Text("Expected back \(expected.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption)
                    .foregroundStyle(KRTheme.loanedColor)
            }
            Button("Mark Returned") {
                store.markReturned(key)
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(KRTheme.surfaceRaised)
            .foregroundStyle(KRTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: KRTheme.smallCorner))
            .padding(.top, 4)
        }
    }

    private func detailSection(title: String, text: String) -> some View {
        cardSection {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(KRTheme.inkFaded)
            Text(text)
                .font(.body)
                .foregroundStyle(KRTheme.ink)
        }
    }

    private var historySection: some View {
        cardSection {
            Text("HISTORY")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KRTheme.inkFaded)
            if key.sortedHistory.isEmpty {
                Text("No activity yet.")
                    .font(.subheadline)
                    .foregroundStyle(KRTheme.inkFaded)
            } else {
                ForEach(key.sortedHistory) { event in
                    KeyHistoryRowView(event: event)
                }
            }
        }
    }

    private var upgradeHistoryTeaser: some View {
        Button {
            showPaywall = true
        } label: {
            cardSection {
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(KRTheme.brass)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full history & location tracking")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KRTheme.ink)
                        Text("Unlock with Keyring Pro")
                            .font(.caption)
                            .foregroundStyle(KRTheme.inkFaded)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(KRTheme.inkFaded)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func cardSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KRTheme.Spacing.md)
        .background(KRTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: KRTheme.cardCorner))
        .overlay(RoundedRectangle(cornerRadius: KRTheme.cardCorner).stroke(KRTheme.rule, lineWidth: 1))
    }
}

private struct LastConfirmedLocationMap: View {
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        Map(initialPosition: .region(
            MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        )) {
            Marker("", coordinate: coordinate)
                .tint(KRTheme.brass)
        }
        .allowsHitTesting(false)
    }
}

private struct LoanKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var person: String
    @State private var expectedReturn: Date
    @State private var hasExpectedReturn: Bool
    @State private var notificationsDenied = false

    let existing: KeyEntity
    let onSave: (String, Date?) -> Void

    init(existing: KeyEntity, onSave: @escaping (String, Date?) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _person = State(initialValue: existing.loanedTo ?? "")
        _expectedReturn = State(initialValue: existing.expectedReturnDate ?? Date().addingTimeInterval(7 * 86400))
        _hasExpectedReturn = State(initialValue: existing.expectedReturnDate != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Loaned To") {
                    TextField("Name", text: $person)
                        .accessibilityIdentifier("loanPersonField")
                }
                Section("Expected Return") {
                    Toggle("Set a reminder date", isOn: $hasExpectedReturn)
                    if hasExpectedReturn {
                        DatePicker("Return by", selection: $expectedReturn, displayedComponents: .date)
                    }
                    // Reminders are scheduled lazily on save; a prior "Don't Allow"
                    // would otherwise leave this toggle silently doing nothing.
                    if hasExpectedReturn, notificationsDenied {
                        Label("Notifications are off, so this reminder won't alert you. Enable them in Settings.", systemImage: "bell.slash")
                            .font(.caption)
                            .foregroundStyle(KRTheme.lostColor)
                    }
                }
            }
            .task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                notificationsDenied = settings.authorizationStatus == .denied
            }
            .dismissKeyboardOnTap()
            .navigationTitle("Loan Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(person, hasExpectedReturn ? expectedReturn : nil)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(person.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Save")
                    .accessibilityIdentifier("saveLoanButton")
                }
            }
        }
    }
}
