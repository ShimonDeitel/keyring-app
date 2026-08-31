import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Keeps each key discoverable from iOS search without a network round
/// trip — everything indexed here already lives on-device. Called by
/// `SwiftDataKeyRepository` on every create/update/delete so the index
/// never drifts from what's actually saved.
enum SpotlightIndexer {
    static func index(_ key: KeyEntity) {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = key.name
        var descriptionParts: [String] = []
        if !key.opens.isEmpty { descriptionParts.append("Opens \(key.opens)") }
        descriptionParts.append(key.category.displayName)
        if let location = key.assignedLocationName, !location.isEmpty {
            descriptionParts.append("Kept at \(location)")
        }
        attributes.contentDescription = descriptionParts.joined(separator: " · ")
        attributes.keywords = [key.name, key.opens, key.category.displayName, "key", "keyring"].filter { !$0.isEmpty }
        if let photoData = key.photoData {
            attributes.thumbnailData = photoData
        }

        let item = CSSearchableItem(
            uniqueIdentifier: key.id.uuidString,
            domainIdentifier: key.keyring?.id.uuidString ?? "keys",
            attributeSet: attributes
        )
        CSSearchableIndex.default().indexSearchableItems([item])
    }

    static func deindex(_ key: KeyEntity) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [key.id.uuidString])
    }

    static func deindexKeyring(_ keyring: KeyringEntity) {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [keyring.id.uuidString])
    }
}
