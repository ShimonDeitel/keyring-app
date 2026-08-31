import AppIntents
import SwiftData

/// The Siri/Shortcuts-facing projection of a key. Deliberately a plain
/// Sendable struct, not the SwiftData model itself — App Intents runs
/// outside the SwiftUI environment and may not share the app's actor.
struct KeyAppEntity: AppEntity {
    let id: UUID
    let name: String
    let opens: String
    let keyringName: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Key"
    static var defaultQuery = KeyAppEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: opens.isEmpty ? "\(keyringName)" : "Opens \(opens)"
        )
    }
}

struct KeyAppEntityQuery: EntityQuery {
    init() {}

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [KeyAppEntity] {
        let context = PersistenceController.makeContainer().mainContext
        let all = try context.fetch(FetchDescriptor<KeyEntity>())
        return all.filter { identifiers.contains($0.id) }.map(KeyAppEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [KeyAppEntity] {
        let context = PersistenceController.makeContainer().mainContext
        let all = try context.fetch(FetchDescriptor<KeyEntity>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        return Array(all.prefix(10)).map(KeyAppEntity.init)
    }
}

extension KeyAppEntity {
    init(_ key: KeyEntity) {
        self.id = key.id
        self.name = key.name
        self.opens = key.opens
        self.keyringName = key.keyring?.name ?? "Keyring"
    }
}
