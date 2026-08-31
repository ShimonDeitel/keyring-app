import SwiftUI

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

    /// One accent per category, all warm/muted enough to sit next to
    /// KRTheme's brass-and-bone palette without clashing.
    var color: Color {
        switch self {
        case .house: return Color(red: 0.72, green: 0.42, blue: 0.27)     // terracotta
        case .car: return Color(red: 0.27, green: 0.44, blue: 0.58)       // steel blue
        case .office: return Color(red: 0.40, green: 0.36, blue: 0.46)    // slate plum
        case .storage: return Color(red: 0.42, green: 0.48, blue: 0.30)   // olive
        case .mailbox: return Color(red: 0.68, green: 0.32, blue: 0.30)   // brick red
        case .padlock: return Color(red: 0.52, green: 0.37, blue: 0.58)   // plum
        case .other: return KRTheme.brass
        }
    }
}
