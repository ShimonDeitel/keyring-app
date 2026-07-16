import SwiftUI
import PhotosUI

enum KeyringSheet: Identifiable {
    case add
    case edit(KeyItem)
    case paywall

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let k): return "edit-\(k.id)"
        case .paywall: return "paywall"
        }
    }
}

struct KeyFormView: View {
    @EnvironmentObject private var store: KeyringStore
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    let existing: KeyItem?

    @State private var label: String
    @State private var note: String
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoData: Data?

    init(existing: KeyItem?) {
        self.existing = existing
        _label = State(initialValue: existing?.label ?? "")
        _note = State(initialValue: existing?.note ?? "")
        _photoData = State(initialValue: existing?.photoData)
    }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Key") {
                    TextField("What does this key open? (e.g. Front Door)", text: $label)
                        .accessibilityIdentifier("keyLabelField")
                    TextField("Note (e.g. brass, top of the ring)", text: $note)
                        .accessibilityIdentifier("keyNoteField")
                }

                Section("Photo") {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        HStack {
                            if let photoData, let uiImage = UIImage(data: photoData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "key")
                                    .foregroundStyle(KRTheme.brass)
                                    .frame(width: 44, height: 44)
                            }
                            Text(photoData != nil ? "Photo added" : "Add a photo of this key")
                                .foregroundStyle(KRTheme.ink)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("keyPhotoPicker")
                }

                if isEditing {
                    Section {
                        Button("Delete Key", role: .destructive) {
                            if let existing {
                                store.deleteKey(existing.id)
                            }
                            dismiss()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("deleteKeyButton")
                    }
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle(isEditing ? "Edit Key" : "New Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.plain)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .buttonStyle(.plain)
                        .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveKeyButton")
                }
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let item, let data = try? await item.loadTransferable(type: Data.self) {
                        photoData = data
                    }
                }
            }
        }
    }

    private func save() {
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let existing {
            store.updateKey(existing.id, label: label, note: note, photoData: photoData)
            dismiss()
        } else {
            guard store.canAddKey(isPro: purchases.isPro) else { return }
            store.addKey(label: label, note: note, photoData: photoData, isPro: purchases.isPro)
            dismiss()
        }
    }
}
