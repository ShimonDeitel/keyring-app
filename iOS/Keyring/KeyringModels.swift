import Foundation

/// A single identified key on the ring.
struct KeyItem: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var note: String
    var photoData: Data?
    var createdDate: Date

    init(
        id: UUID = UUID(),
        label: String,
        note: String = "",
        photoData: Data? = nil,
        createdDate: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.note = note
        self.photoData = photoData
        self.createdDate = createdDate
    }

    var hasPhoto: Bool { photoData != nil }
}
