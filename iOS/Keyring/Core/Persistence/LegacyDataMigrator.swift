import Foundation
import SwiftData

/// One-time import of the pre-2.0 flat JSON store (`keyring_data.json`) into
/// the new SwiftData schema, so upgrading users keep every key they already
/// identified. Runs once: on success the legacy file is renamed so it never
/// runs again, even if the new store is later cleared.
enum LegacyDataMigrator {
    private struct LegacyKeyItem: Codable {
        var id: UUID
        var label: String
        var note: String
        var photoData: Data?
        var createdDate: Date
    }

    private struct LegacySnapshot: Codable {
        var keys: [LegacyKeyItem]
    }

    @MainActor
    static func migrateIfNeeded(into context: ModelContext) {
        guard !PersistenceController.isUITesting else { return }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacyURL = dir.appendingPathComponent("keyring_data.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }

        defer {
            let migratedURL = dir.appendingPathComponent("keyring_data.migrated.json")
            try? FileManager.default.removeItem(at: migratedURL)
            try? FileManager.default.moveItem(at: legacyURL, to: migratedURL)
        }

        guard let data = try? Data(contentsOf: legacyURL),
              let snapshot = try? JSONDecoder().decode(LegacySnapshot.self, from: data),
              !snapshot.keys.isEmpty else { return }

        let ring = KeyringEntity(name: "My Keys", icon: "key.fill")
        context.insert(ring)

        for legacy in snapshot.keys {
            let key = KeyEntity(
                id: legacy.id,
                name: legacy.label,
                photoData: legacy.photoData,
                notes: legacy.note,
                createdAt: legacy.createdDate,
                updatedAt: legacy.createdDate
            )
            key.keyring = ring
            context.insert(key)
            let event = KeyHistoryEntity(eventType: .created, timestamp: legacy.createdDate)
            event.key = key
            context.insert(event)
        }

        try? context.save()
    }
}
