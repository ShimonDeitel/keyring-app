import Foundation

enum KeyCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case house, car, office, storage, mailbox, padlock, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .house: return "House"
        case .car: return "Car"
        case .office: return "Office"
        case .storage: return "Storage"
        case .mailbox: return "Mailbox"
        case .padlock: return "Padlock"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .house: return "house.fill"
        case .car: return "car.fill"
        case .office: return "briefcase.fill"
        case .storage: return "shippingbox.fill"
        case .mailbox: return "envelope.fill"
        case .padlock: return "lock.fill"
        case .other: return "key.fill"
        }
    }
}
