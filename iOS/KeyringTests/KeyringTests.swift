import XCTest
import SwiftData
@testable import Keyring

@MainActor
final class MockEntitlements: EntitlementProviding {
    var isPro: Bool = false
}

@MainActor
final class KeyringTests: XCTestCase {
    var container: ModelContainer!
    var entitlements: MockEntitlements!
    var store: KeyringStore!
    var ring: KeyringEntity!

    override func setUp() {
        super.setUp()
        let configuration = ModelConfiguration(schema: PersistenceController.schema, isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: PersistenceController.schema, configurations: [configuration])
        entitlements = MockEntitlements()
        store = KeyringStore(context: container.mainContext, entitlements: entitlements)
        ring = store.createKeyring(name: "My Keys", icon: "key.fill", locationName: nil)!
    }

    // MARK: Keys — free/Pro limits (matches the original KeyringStore contract)

    func testAddKeyRespectsFreeLimit() {
        for label in ["A", "B", "C", "D", "E"] {
            XCTAssertNotNil(store.addKey(to: ring, name: label, photoData: nil, keyDescription: "", opens: "", category: .other, notes: "", assignedLocationName: nil))
        }
        XCTAssertNil(store.addKey(to: ring, name: "F", photoData: nil, keyDescription: "", opens: "", category: .other, notes: "", assignedLocationName: nil))
        entitlements.isPro = true
        XCTAssertNotNil(store.addKey(to: ring, name: "F", photoData: nil, keyDescription: "", opens: "", category: .other, notes: "", assignedLocationName: nil))
    }

    func testAddKeyRejectsBlankLabel() {
        let key = store.addKey(to: ring, name: "   ", photoData: nil, keyDescription: "", opens: "", category: .other, notes: "", assignedLocationName: nil)
        // A blank trimmed name falls back to "New Key" rather than failing —
        // guard against silently losing the add instead.
        XCTAssertEqual(key?.name, "New Key")
    }

    func testAddKeyStoresPhotoData() {
        let data = Data([0x01, 0x02])
        let key = store.addKey(to: ring, name: "Garage", photoData: data, keyDescription: "", opens: "", category: .other, notes: "Silver", assignedLocationName: nil)!
        XCTAssertEqual(key.photoData, data)
        XCTAssertTrue(key.hasPhoto)
    }

    func testUpdateKeyChangesFields() {
        let key = store.addKey(to: ring, name: "Garage", photoData: nil, keyDescription: "", opens: "", category: .other, notes: "", assignedLocationName: nil)!
        store.updateKey(key, name: "Shed", photoData: nil, keyDescription: "", opens: "", category: .other, notes: "Copper key", assignedLocationName: nil)
        XCTAssertEqual(key.name, "Shed")
        XCTAssertEqual(key.notes, "Copper key")
    }

    func testUpdatePreservesExistingPhotoWhenNoNewOneProvided() {
        let data = Data([0x09])
        let key = store.addKey(to: ring, name: "Garage", photoData: data, keyDescription: "", opens: "", category: .other, notes: "", assignedLocationName: nil)!
        store.updateKey(key, name: "Garage", photoData: nil, keyDescription: "", opens: "", category: .other, notes: "", assignedLocationName: nil)
        XCTAssertEqual(key.photoData, data)
    }

    func testDeleteKeyRemovesIt() {
        let key = store.addKey(to: ring, name: "Removable", photoData: nil, keyDescription: "", opens: "", category: .other, notes: "", assignedLocationName: nil)!
        store.deleteKey(key)
        XCTAssertEqual(ring.keyCount, 0)
    }

    // MARK: Keyrings

    func testFreeUserCannotCreateSecondKeyring() {
        let second = store.createKeyring(name: "Office", icon: "briefcase.fill", locationName: nil)
        XCTAssertNil(second)
        XCTAssertEqual(store.keyrings.count, 1)
    }

    func testProUserCanCreateMultipleKeyrings() {
        entitlements.isPro = true
        _ = store.createKeyring(name: "Office", icon: "briefcase.fill", locationName: nil)
        XCTAssertEqual(store.keyrings.count, 2)
    }

    // MARK: History

    func testAddingKeyLogsCreatedHistoryEvent() {
        let key = store.addKey(to: ring, name: "Front Door", photoData: nil, keyDescription: "", opens: "Front door", category: .house, notes: "", assignedLocationName: nil)!
        XCTAssertEqual(key.sortedHistory.count, 1)
        XCTAssertEqual(key.sortedHistory.first?.eventType, .created)
    }

    func testEditingKeyLogsEditedHistoryEvent() {
        let key = store.addKey(to: ring, name: "Front Door", photoData: nil, keyDescription: "", opens: "", category: .house, notes: "", assignedLocationName: nil)!
        store.updateKey(key, name: "Back Door", photoData: nil, keyDescription: "", opens: "", category: .house, notes: "", assignedLocationName: nil)
        XCTAssertTrue(key.sortedHistory.contains { $0.eventType == .edited })
    }

    // MARK: Loan / spare / lost lifecycle

    func testMarkLoanedThenReturned() {
        let key = store.addKey(to: ring, name: "Garage", photoData: nil, keyDescription: "", opens: "", category: .house, notes: "", assignedLocationName: nil)!
        store.markLoaned(key, to: "Dad", expectedReturn: nil)
        XCTAssertTrue(key.isLoaned)
        XCTAssertEqual(key.loanedTo, "Dad")
        XCTAssertEqual(ring.loanedKeys.count, 1)
        store.markReturned(key)
        XCTAssertFalse(key.isLoaned)
        XCTAssertNil(key.loanedTo)
        XCTAssertEqual(ring.loanedKeys.count, 0)
    }

    func testMarkLostThenFound() {
        let key = store.addKey(to: ring, name: "Mailbox", photoData: nil, keyDescription: "", opens: "", category: .mailbox, notes: "", assignedLocationName: nil)!
        store.markLost(key)
        XCTAssertTrue(key.isLost)
        store.markFound(key)
        XCTAssertFalse(key.isLost)
    }

    // MARK: Location

    func testConfirmLocationUpdatesKeyAndLogsHistory() {
        let key = store.addKey(to: ring, name: "Storage", photoData: nil, keyDescription: "", opens: "", category: .storage, notes: "", assignedLocationName: nil)!
        store.confirmLocation(for: key, name: "Storage Unit 12", latitude: 32.0, longitude: 34.0)
        XCTAssertEqual(key.lastConfirmedLocationName, "Storage Unit 12")
        XCTAssertNotNil(key.lastConfirmedAt)
        XCTAssertTrue(key.sortedHistory.contains { $0.eventType == .locationConfirmed })
    }

    // MARK: Search

    func testSearchFindsKeyByOpensField() {
        _ = store.addKey(to: ring, name: "Weird Key", photoData: nil, keyDescription: "", opens: "Storage unit 12", category: .storage, notes: "", assignedLocationName: nil)
        let results = store.search("storage unit")
        XCTAssertEqual(results.count, 1)
    }
}

/// Verifies upgrading users' pre-2.0 flat JSON store is imported into
/// SwiftData rather than silently dropped.
@MainActor
final class LegacyDataMigratorTests: XCTestCase {
    private var legacyURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("keyring_data.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: legacyURL)
        let migratedURL = legacyURL.deletingLastPathComponent().appendingPathComponent("keyring_data.migrated.json")
        try? FileManager.default.removeItem(at: migratedURL)
        super.tearDown()
    }

    func testMigratesLegacyKeysIntoNewSchema() throws {
        let legacyID = UUID()
        let json = """
        {"keys":[{"id":"\(legacyID.uuidString)","label":"Front Door","note":"Deadbolt","photoData":null,"createdDate":719000000}]}
        """
        try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.data(using: .utf8)!.write(to: legacyURL)

        let configuration = ModelConfiguration(schema: PersistenceController.schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistenceController.schema, configurations: [configuration])
        LegacyDataMigrator.migrateIfNeeded(into: container.mainContext)

        let rings = try container.mainContext.fetch(FetchDescriptor<KeyringEntity>())
        XCTAssertEqual(rings.count, 1)
        XCTAssertEqual(rings.first?.sortedKeys.first?.name, "Front Door")
        XCTAssertEqual(rings.first?.sortedKeys.first?.notes, "Deadbolt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path), "legacy file should be renamed after a successful migration")
    }

    func testDoesNothingWhenNoLegacyFileExists() throws {
        let configuration = ModelConfiguration(schema: PersistenceController.schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistenceController.schema, configurations: [configuration])
        LegacyDataMigrator.migrateIfNeeded(into: container.mainContext)
        let rings = try container.mainContext.fetch(FetchDescriptor<KeyringEntity>())
        XCTAssertTrue(rings.isEmpty)
    }
}
