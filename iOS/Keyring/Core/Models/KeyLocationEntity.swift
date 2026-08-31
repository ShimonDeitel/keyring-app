import Foundation
import SwiftData

@Model
final class KeyLocationEntity {
    // Not @Attribute(.unique): CloudKit-backed SwiftData configurations
    // (Phase 2) reject unique constraints at container creation.
    var id: UUID
    var name: String
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
    }
}
