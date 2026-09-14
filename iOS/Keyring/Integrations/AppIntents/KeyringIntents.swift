import AppIntents
import SwiftData
import StoreKit

extension KeyCategory: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Key Category"
    static var caseDisplayRepresentations: [KeyCategory: DisplayRepresentation] = [
        .house: "House", .car: "Car", .office: "Office", .storage: "Storage",
        .mailbox: "Mailbox", .padlock: "Padlock", .other: "Other"
    ]
}

/// Shared by every intent below: App Intents can run while the app is
/// suspended, so each perform() opens its own store/entitlement check
/// rather than reaching for a live environment object.
@MainActor
enum IntentSupport {
    static func makeContext() -> ModelContext {
        PersistenceController.makeContainer().mainContext
    }

    static func isPro() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == PurchaseManager.proProductID || transaction.productID == PurchaseManager.proMonthlyID {
                return true
            }
        }
        return false
    }
}

struct ShowKeyringIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Keyring"
    static var description = IntentDescription("Opens Keyring to your keys.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct SearchKeysIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Keys"
    static var description = IntentDescription("Finds keys matching a search term, e.g. \"garage\" or \"loaned\".")

    @Parameter(title: "Search")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[KeyAppEntity]> & ProvidesDialog {
        let context = IntentSupport.makeContext()
        let keys = try context.fetch(FetchDescriptor<KeyEntity>())
        let needle = query.lowercased()
        let matches = keys.filter {
            $0.name.lowercased().contains(needle) || $0.opens.lowercased().contains(needle) || $0.category.displayName.lowercased().contains(needle)
        }.map(KeyAppEntity.init)
        let dialog: String = matches.isEmpty ? "No keys matched \"\(query)\"." : "Found \(matches.count) key\(matches.count == 1 ? "" : "s")."
        return .result(value: matches, dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct ShowLoanedKeysIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Loaned Keys"
    static var description = IntentDescription("Lists every key currently loaned out.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[KeyAppEntity]> & ProvidesDialog {
        let context = IntentSupport.makeContext()
        let keys = try context.fetch(FetchDescriptor<KeyEntity>()).filter { $0.isLoaned }
        let dialog: String = keys.isEmpty ? "No keys are loaned out." : "\(keys.count) key\(keys.count == 1 ? " is" : "s are") loaned out."
        return .result(value: keys.map(KeyAppEntity.init), dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct ShowKeysInCategoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Keys by Category"
    static var description = IntentDescription("Lists your keys in a category, e.g. Home or Car.")

    @Parameter(title: "Category")
    var category: KeyCategory

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[KeyAppEntity]> & ProvidesDialog {
        let context = IntentSupport.makeContext()
        let keys = try context.fetch(FetchDescriptor<KeyEntity>()).filter { $0.category == category }
        let dialog: String = keys.isEmpty ? "No \(category.displayName.lowercased()) keys yet." : "\(keys.count) \(category.displayName.lowercased()) key\(keys.count == 1 ? "" : "s")."
        return .result(value: keys.map(KeyAppEntity.init), dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct MarkKeyLoanedIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Key Loaned"
    static var description = IntentDescription("Marks a key as loaned out to someone. Requires Keyring Pro.")

    @Parameter(title: "Key")
    var key: KeyAppEntity

    @Parameter(title: "Loaned To")
    var person: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard await IntentSupport.isPro() else {
            return .result(dialog: "Loan tracking is a Keyring Pro feature.")
        }
        let context = IntentSupport.makeContext()
        let all = try context.fetch(FetchDescriptor<KeyEntity>())
        guard let target = all.first(where: { $0.id == key.id }) else {
            return .result(dialog: "Couldn't find that key.")
        }
        let repository = SwiftDataKeyRepository(context: context)
        try repository.markLoaned(target, to: person, expectedReturn: nil)
        return .result(dialog: "\(target.name) marked as loaned to \(person).")
    }
}

struct MarkKeyReturnedIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Key Returned"
    static var description = IntentDescription("Marks a loaned key as returned. Requires Keyring Pro.")

    @Parameter(title: "Key")
    var key: KeyAppEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard await IntentSupport.isPro() else {
            return .result(dialog: "Loan tracking is a Keyring Pro feature.")
        }
        let context = IntentSupport.makeContext()
        let all = try context.fetch(FetchDescriptor<KeyEntity>())
        guard let target = all.first(where: { $0.id == key.id }) else {
            return .result(dialog: "Couldn't find that key.")
        }
        let repository = SwiftDataKeyRepository(context: context)
        try repository.markReturned(target)
        return .result(dialog: "\(target.name) marked as returned.")
    }
}

struct KeyringShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowKeyringIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open Keyring",
            systemImageName: "key.fill"
        )
        AppShortcut(
            intent: ShowLoanedKeysIntent(),
            phrases: ["Show my loaned keys in \(.applicationName)", "Which keys are loaned in \(.applicationName)"],
            shortTitle: "Loaned Keys",
            systemImageName: "arrow.up.right"
        )
        // SearchKeysIntent is deliberately not exposed as a Siri phrase here:
        // App Shortcuts phrases only support AppEntity/AppEnum parameters,
        // not free-text String. It's still available to the Shortcuts app
        // and to other intents that chain results together.
    }
}
