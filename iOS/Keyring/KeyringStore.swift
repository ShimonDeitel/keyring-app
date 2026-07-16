import Foundation
import Combine

@MainActor
final class KeyringStore: ObservableObject {
    @Published private(set) var keys: [KeyItem] = []

    static let freeKeyLimit = 5

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("keyring_data.json")
        if ProcessInfo.processInfo.arguments.contains("-uiTestReset") {
            try? FileManager.default.removeItem(at: fileURL)
        }
        load()
        if keys.isEmpty {
            seedDefaults()
        }
    }

    private func seedDefaults() {
        keys = [
            KeyItem(label: "Front Door", note: "Deadbolt, brass key"),
            KeyItem(label: "Mailbox", note: "Small silver key")
        ]
        save()
    }

    func canAddKey(isPro: Bool) -> Bool {
        isPro || keys.count < Self.freeKeyLimit
    }

    @discardableResult
    func addKey(label: String, note: String, photoData: Data?, isPro: Bool) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canAddKey(isPro: isPro) else { return false }
        keys.append(KeyItem(label: trimmed, note: note.trimmingCharacters(in: .whitespacesAndNewlines), photoData: photoData))
        save()
        return true
    }

    func updateKey(_ id: UUID, label: String, note: String, photoData: Data?) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = keys.firstIndex(where: { $0.id == id }) else { return }
        keys[idx].label = trimmed
        keys[idx].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let photoData {
            keys[idx].photoData = photoData
        }
        save()
    }

    func deleteKey(_ id: UUID) {
        keys.removeAll { $0.id == id }
        save()
    }

    func key(_ id: UUID) -> KeyItem? {
        keys.first { $0.id == id }
    }

    func deleteAllData() {
        keys = []
        seedDefaults()
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var keys: [KeyItem]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            keys = decoded.keys
        }
    }

    private func save() {
        let snapshot = Snapshot(keys: keys)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
