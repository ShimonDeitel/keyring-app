import XCTest
@testable import Keyring

final class KeyringTests: XCTestCase {

    @MainActor
    private func freshStore() -> KeyringStore {
        let store = KeyringStore()
        for k in store.keys { store.deleteKey(k.id) }
        return store
    }

    @MainActor
    func testAddKeyRespectsFreeLimit() {
        let store = freshStore()
        for label in ["A", "B", "C", "D", "E"] {
            XCTAssertTrue(store.addKey(label: label, note: "", photoData: nil, isPro: false))
        }
        XCTAssertFalse(store.addKey(label: "F", note: "", photoData: nil, isPro: false))
        XCTAssertTrue(store.addKey(label: "F", note: "", photoData: nil, isPro: true))
    }

    @MainActor
    func testAddKeyRejectsBlankLabel() {
        let store = freshStore()
        XCTAssertFalse(store.addKey(label: "   ", note: "", photoData: nil, isPro: false))
        XCTAssertTrue(store.keys.isEmpty)
    }

    @MainActor
    func testAddKeyStoresPhotoData() {
        let store = freshStore()
        let data = Data([0x01, 0x02])
        store.addKey(label: "Garage", note: "Silver", photoData: data, isPro: false)
        let saved = store.keys[0]
        XCTAssertEqual(saved.photoData, data)
        XCTAssertTrue(saved.hasPhoto)
    }

    @MainActor
    func testUpdateKeyChangesFields() {
        let store = freshStore()
        store.addKey(label: "Garage", note: "", photoData: nil, isPro: false)
        let key = store.keys[0]
        store.updateKey(key.id, label: "Shed", note: "Copper key", photoData: nil)
        let updated = store.key(key.id)!
        XCTAssertEqual(updated.label, "Shed")
        XCTAssertEqual(updated.note, "Copper key")
    }

    @MainActor
    func testUpdatePreservesExistingPhotoWhenNoNewOneProvided() {
        let store = freshStore()
        let data = Data([0x09])
        store.addKey(label: "Garage", note: "", photoData: data, isPro: false)
        let key = store.keys[0]
        store.updateKey(key.id, label: "Garage", note: "", photoData: nil)
        XCTAssertEqual(store.key(key.id)!.photoData, data)
    }

    @MainActor
    func testDeleteKeyRemovesIt() {
        let store = freshStore()
        store.addKey(label: "Removable", note: "", photoData: nil, isPro: false)
        let key = store.keys[0]
        store.deleteKey(key.id)
        XCTAssertTrue(store.keys.isEmpty)
    }

    @MainActor
    func testDeleteAllDataReseeds() {
        let store = freshStore()
        store.deleteAllData()
        XCTAssertFalse(store.keys.isEmpty)
    }
}
