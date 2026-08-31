import Foundation
import SwiftData

enum KeyHistoryEventType: String, Codable, CaseIterable, Hashable {
    case created = "Created"
    case edited = "Edited"
    case locationConfirmed = "LocationConfirmed"
    case loaned = "Loaned"
    case returned = "Returned"
    case markedLost = "MarkedLost"
    case markedFound = "MarkedFound"
    case addedToKeyring = "AddedToKeyring"
    case removedFromKeyring = "RemovedFromKeyring"

    var displayName: String {
        switch self {
        case .created: return "Added"
        case .edited: return "Edited"
        case .locationConfirmed: return "Location confirmed"
        case .loaned: return "Loaned"
        case .returned: return "Returned"
        case .markedLost: return "Marked lost"
        case .markedFound: return "Marked found"
        case .addedToKeyring: return "Added to keyring"
        case .removedFromKeyring: return "Removed from keyring"
        }
    }

    var symbolName: String {
        switch self {
        case .created: return "plus.circle.fill"
        case .edited: return "pencil.circle.fill"
        case .locationConfirmed: return "mappin.circle.fill"
        case .loaned: return "arrow.up.right.circle.fill"
        case .returned: return "arrow.down.left.circle.fill"
        case .markedLost: return "exclamationmark.triangle.fill"
        case .markedFound: return "checkmark.circle.fill"
        case .addedToKeyring: return "tray.and.arrow.down.fill"
        case .removedFromKeyring: return "tray.and.arrow.up.fill"
        }
    }
}

@Model
final class KeyHistoryEntity {
    // Not @Attribute(.unique): CloudKit-backed SwiftData configurations
    // (Phase 2) reject unique constraints at container creation.
    var id: UUID
    var eventTypeRaw: String
    var timestamp: Date
    var locationName: String?
    var notes: String?
    var person: String?

    var key: KeyEntity?

    init(
        id: UUID = UUID(),
        eventType: KeyHistoryEventType,
        timestamp: Date = .now,
        locationName: String? = nil,
        notes: String? = nil,
        person: String? = nil
    ) {
        self.id = id
        self.eventTypeRaw = eventType.rawValue
        self.timestamp = timestamp
        self.locationName = locationName
        self.notes = notes
        self.person = person
    }

    var eventType: KeyHistoryEventType {
        KeyHistoryEventType(rawValue: eventTypeRaw) ?? .edited
    }
}
