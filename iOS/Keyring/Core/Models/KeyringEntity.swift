import Foundation
import SwiftData

@Model
final class KeyringEntity {
    // Not @Attribute(.unique): CloudKit-backed SwiftData configurations
    // (Phase 2) reject unique constraints at container creation.
    var id: UUID
    var name: String
    var icon: String
    var locationName: String?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
    var isShared: Bool

    @Relationship(deleteRule: .cascade, inverse: \KeyEntity.keyring)
    var keys: [KeyEntity]? = []

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "key.fill",
        locationName: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sortOrder: Int = 0,
        isShared: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.locationName = locationName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.isShared = isShared
    }

    var sortedKeys: [KeyEntity] {
        (keys ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    var keyCount: Int { keys?.count ?? 0 }

    var loanedKeys: [KeyEntity] {
        sortedKeys.filter { $0.isLoaned }
    }
}
