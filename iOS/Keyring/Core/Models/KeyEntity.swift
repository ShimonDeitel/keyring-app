import Foundation
import SwiftData

@Model
final class KeyEntity {
    // Not @Attribute(.unique): CloudKit-backed SwiftData configurations
    // (Phase 2) reject unique constraints at container creation.
    var id: UUID
    var name: String
    @Attribute(.externalStorage) var photoData: Data?
    var keyDescription: String
    var opens: String
    var categoryRaw: String
    var notes: String
    var isFavorite: Bool

    var isSpare: Bool
    var isLost: Bool
    var isLoaned: Bool
    var loanedTo: String?
    var loanDate: Date?
    var expectedReturnDate: Date?

    var assignedLocationName: String?
    var lastConfirmedLocationName: String?
    var lastConfirmedAt: Date?
    var lastConfirmedLatitude: Double?
    var lastConfirmedLongitude: Double?

    var createdAt: Date
    var updatedAt: Date

    var keyring: KeyringEntity?

    @Relationship(deleteRule: .cascade, inverse: \KeyHistoryEntity.key)
    var history: [KeyHistoryEntity]? = []

    init(
        id: UUID = UUID(),
        name: String,
        photoData: Data? = nil,
        keyDescription: String = "",
        opens: String = "",
        category: KeyCategory = .other,
        notes: String = "",
        isFavorite: Bool = false,
        isSpare: Bool = false,
        isLost: Bool = false,
        isLoaned: Bool = false,
        loanedTo: String? = nil,
        loanDate: Date? = nil,
        expectedReturnDate: Date? = nil,
        assignedLocationName: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.photoData = photoData
        self.keyDescription = keyDescription
        self.opens = opens
        self.categoryRaw = category.rawValue
        self.notes = notes
        self.isFavorite = isFavorite
        self.isSpare = isSpare
        self.isLost = isLost
        self.isLoaned = isLoaned
        self.loanedTo = loanedTo
        self.loanDate = loanDate
        self.expectedReturnDate = expectedReturnDate
        self.assignedLocationName = assignedLocationName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var category: KeyCategory {
        get { KeyCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var sortedHistory: [KeyHistoryEntity] {
        (history ?? []).sorted { $0.timestamp > $1.timestamp }
    }

    var statusLabel: String? {
        if isLost { return "Lost" }
        if isLoaned { return "Loaned" }
        if isSpare { return "Spare" }
        return nil
    }

    var hasPhoto: Bool { photoData != nil }
}
