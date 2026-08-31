import Foundation
import SwiftData
import Observation

/// App-wide feature layer that views bind to. Holds the current fetch results
/// and plan-gating decisions; delegates every write to `KeyRepositoryProtocol`
/// so views never see a `ModelContext`.
@MainActor
@Observable
final class KeyringStore {
    private(set) var keyrings: [KeyringEntity] = []
    private(set) var lastError: String?

    private let context: ModelContext
    private let repository: KeyRepositoryProtocol
    private let entitlements: EntitlementProviding

    init(context: ModelContext, entitlements: EntitlementProviding, repository: KeyRepositoryProtocol? = nil) {
        self.context = context
        self.entitlements = entitlements
        self.repository = repository ?? SwiftDataKeyRepository(context: context)
        LegacyDataMigrator.migrateIfNeeded(into: context)
        refresh()
    }

    var isPro: Bool { entitlements.isPro }

    func refresh() {
        let descriptor = FetchDescriptor<KeyringEntity>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        keyrings = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Gating

    var canCreateKeyring: Bool {
        entitlements.isPro || keyrings.count < PlanLimits.freeMaxKeyrings
    }

    func canAddKey(to keyring: KeyringEntity) -> Bool {
        entitlements.isPro || keyring.keyCount < PlanLimits.freeMaxKeysPerKeyring
    }

    /// Advanced key history, loan/spare/lost workflows and location confirmation
    /// are Pro features; free users keep a single manual "kept at" text field.
    var hasAdvancedFeatures: Bool { entitlements.isPro }

    // MARK: Keyrings

    @discardableResult
    func createKeyring(name: String, icon: String, locationName: String?) -> KeyringEntity? {
        guard canCreateKeyring else { return nil }
        return run { try repository.createKeyring(name: name, icon: icon, locationName: locationName) }
    }

    func renameKeyring(_ keyring: KeyringEntity, name: String, icon: String, locationName: String?) {
        run { try repository.renameKeyring(keyring, name: name, icon: icon, locationName: locationName) }
    }

    func deleteKeyring(_ keyring: KeyringEntity) {
        run { try repository.deleteKeyring(keyring) }
    }

    // MARK: Keys

    @discardableResult
    func addKey(to keyring: KeyringEntity, name: String, photoData: Data?, keyDescription: String, opens: String, category: KeyCategory, notes: String, assignedLocationName: String?) -> KeyEntity? {
        guard canAddKey(to: keyring) else { return nil }
        return run {
            try repository.createKey(in: keyring, name: name, photoData: photoData, keyDescription: keyDescription, opens: opens, category: category, notes: notes, assignedLocationName: assignedLocationName)
        }
    }

    func updateKey(_ key: KeyEntity, name: String, photoData: Data?, keyDescription: String, opens: String, category: KeyCategory, notes: String, assignedLocationName: String?) {
        run { try repository.updateKey(key, name: name, photoData: photoData, keyDescription: keyDescription, opens: opens, category: category, notes: notes, assignedLocationName: assignedLocationName) }
    }

    func deleteKey(_ key: KeyEntity) {
        run { try repository.deleteKey(key) }
    }

    func toggleFavorite(_ key: KeyEntity) {
        run { try repository.toggleFavorite(key) }
    }

    func confirmLocation(for key: KeyEntity, name: String, latitude: Double?, longitude: Double?) {
        run { try repository.confirmLocation(for: key, name: name, latitude: latitude, longitude: longitude) }
    }

    func markLoaned(_ key: KeyEntity, to person: String, expectedReturn: Date?) {
        run { try repository.markLoaned(key, to: person, expectedReturn: expectedReturn) }
    }

    func markReturned(_ key: KeyEntity) {
        run { try repository.markReturned(key) }
    }

    func markLost(_ key: KeyEntity) {
        run { try repository.markLost(key) }
    }

    func markFound(_ key: KeyEntity) {
        run { try repository.markFound(key) }
    }

    var allLoanedKeys: [(keyring: KeyringEntity, key: KeyEntity)] {
        keyrings.flatMap { ring in ring.loanedKeys.map { (ring, $0) } }
    }

    func search(_ query: String) -> [(keyring: KeyringEntity, key: KeyEntity)] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        let scopedRings = entitlements.isPro ? keyrings : Array(keyrings.prefix(1))
        return scopedRings.flatMap { ring in
            ring.sortedKeys.filter { key in
                key.name.lowercased().contains(trimmed)
                    || key.opens.lowercased().contains(trimmed)
                    || key.category.displayName.lowercased().contains(trimmed)
                    || (entitlements.isPro && key.notes.lowercased().contains(trimmed))
            }.map { (ring, $0) }
        }
    }

    @discardableResult
    private func run<T>(_ block: () throws -> T) -> T? {
        do {
            let result = try block()
            refresh()
            lastError = nil
            return result
        } catch {
            lastError = error.localizedDescription
            refresh()
            return nil
        }
    }
}
