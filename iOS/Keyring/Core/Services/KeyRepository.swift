import Foundation
import SwiftData

/// Persistence-facing operations for keyrings and keys. Views and the feature
/// layer never touch a `ModelContext` directly — everything routes through
/// here so the storage backend (local SwiftData today, CloudKit-synced
/// SwiftData in Phase 2) can change without touching UI code.
@MainActor
protocol KeyRepositoryProtocol {
    func createKeyring(name: String, icon: String, locationName: String?) throws -> KeyringEntity
    func renameKeyring(_ keyring: KeyringEntity, name: String, icon: String, locationName: String?) throws
    func deleteKeyring(_ keyring: KeyringEntity) throws

    @discardableResult
    func createKey(in keyring: KeyringEntity, name: String, photoData: Data?, keyDescription: String, opens: String, category: KeyCategory, notes: String, assignedLocationName: String?) throws -> KeyEntity

    func updateKey(_ key: KeyEntity, name: String, photoData: Data?, keyDescription: String, opens: String, category: KeyCategory, notes: String, assignedLocationName: String?) throws
    func deleteKey(_ key: KeyEntity) throws
    func toggleFavorite(_ key: KeyEntity) throws

    func confirmLocation(for key: KeyEntity, name: String, latitude: Double?, longitude: Double?) throws
    func markLoaned(_ key: KeyEntity, to person: String, expectedReturn: Date?) throws
    func markReturned(_ key: KeyEntity) throws
    func markLost(_ key: KeyEntity) throws
    func markFound(_ key: KeyEntity) throws
}

@MainActor
final class SwiftDataKeyRepository: KeyRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    private func log(_ type: KeyHistoryEventType, for key: KeyEntity, locationName: String? = nil, notes: String? = nil, person: String? = nil) {
        let event = KeyHistoryEntity(eventType: type, locationName: locationName, notes: notes, person: person)
        event.key = key
        context.insert(event)
    }

    private func save() throws {
        try context.save()
    }

    // MARK: Keyrings

    func createKeyring(name: String, icon: String, locationName: String?) throws -> KeyringEntity {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyring = KeyringEntity(name: trimmed.isEmpty ? "Keyring" : trimmed, icon: icon, locationName: locationName)
        context.insert(keyring)
        try save()
        return keyring
    }

    func renameKeyring(_ keyring: KeyringEntity, name: String, icon: String, locationName: String?) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        keyring.name = trimmed.isEmpty ? keyring.name : trimmed
        keyring.icon = icon
        keyring.locationName = locationName
        keyring.updatedAt = .now
        try save()
    }

    func deleteKeyring(_ keyring: KeyringEntity) throws {
        context.delete(keyring)
        try save()
    }

    // MARK: Keys

    @discardableResult
    func createKey(in keyring: KeyringEntity, name: String, photoData: Data?, keyDescription: String, opens: String, category: KeyCategory, notes: String, assignedLocationName: String?) throws -> KeyEntity {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = KeyEntity(
            name: trimmed.isEmpty ? "New Key" : trimmed,
            photoData: photoData,
            keyDescription: keyDescription,
            opens: opens,
            category: category,
            notes: notes,
            assignedLocationName: assignedLocationName
        )
        key.keyring = keyring
        context.insert(key)
        log(.created, for: key)
        try save()
        return key
    }

    func updateKey(_ key: KeyEntity, name: String, photoData: Data?, keyDescription: String, opens: String, category: KeyCategory, notes: String, assignedLocationName: String?) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        key.name = trimmed.isEmpty ? key.name : trimmed
        if let photoData {
            key.photoData = photoData
        }
        key.keyDescription = keyDescription
        key.opens = opens
        key.category = category
        key.notes = notes
        key.assignedLocationName = assignedLocationName
        key.updatedAt = .now
        log(.edited, for: key)
        try save()
    }

    func deleteKey(_ key: KeyEntity) throws {
        context.delete(key)
        try save()
    }

    func toggleFavorite(_ key: KeyEntity) throws {
        key.isFavorite.toggle()
        key.updatedAt = .now
        try save()
    }

    // MARK: Location & loan lifecycle

    func confirmLocation(for key: KeyEntity, name: String, latitude: Double?, longitude: Double?) throws {
        key.lastConfirmedLocationName = name
        key.lastConfirmedAt = .now
        key.lastConfirmedLatitude = latitude
        key.lastConfirmedLongitude = longitude
        key.updatedAt = .now
        log(.locationConfirmed, for: key, locationName: name)
        try save()
    }

    func markLoaned(_ key: KeyEntity, to person: String, expectedReturn: Date?) throws {
        key.isLoaned = true
        key.loanedTo = person
        key.loanDate = .now
        key.expectedReturnDate = expectedReturn
        key.updatedAt = .now
        log(.loaned, for: key, person: person)
        try save()
    }

    func markReturned(_ key: KeyEntity) throws {
        let person = key.loanedTo
        key.isLoaned = false
        key.loanedTo = nil
        key.loanDate = nil
        key.expectedReturnDate = nil
        key.updatedAt = .now
        log(.returned, for: key, person: person)
        try save()
    }

    func markLost(_ key: KeyEntity) throws {
        key.isLost = true
        key.updatedAt = .now
        log(.markedLost, for: key)
        try save()
    }

    func markFound(_ key: KeyEntity) throws {
        key.isLost = false
        key.updatedAt = .now
        log(.markedFound, for: key)
        try save()
    }
}
