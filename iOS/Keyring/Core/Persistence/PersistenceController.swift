import Foundation
import SwiftData

/// Local-first storage. The on-device store is the source of truth for normal
/// app operation; CloudKit sync (Phase 2) layers on top of this schema without
/// requiring a migration, since every relationship here is already optional
/// and no attribute is unique.
enum PersistenceController {
    static var schema: Schema {
        Schema([
            KeyringEntity.self,
            KeyEntity.self,
            KeyHistoryEntity.self,
            KeyLocationEntity.self
        ])
    }

    /// UI tests launch with `-uiTestReset` (the flag the legacy store already
    /// used) so every run starts from a clean, in-memory store.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestReset")
    }

    @MainActor
    static func makeContainer() -> ModelContainer {
        if isUITesting {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [configuration])
        }
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            assertionFailure("Failed to create ModelContainer: \(error)")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }

    @MainActor
    static func makePreviewContainer(seeded: Bool = true) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        if seeded {
            let context = container.mainContext
            let ring = KeyringEntity(name: "My Keys", icon: "key.fill")
            let key = KeyEntity(name: "Front Door", opens: "Front door", category: .house)
            key.keyring = ring
            context.insert(ring)
            context.insert(key)
            try? context.save()
        }
        return container
    }
}
