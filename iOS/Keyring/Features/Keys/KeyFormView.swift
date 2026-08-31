import SwiftUI
import PhotosUI

struct KeyFormView: View {
    @Environment(KeyringStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let keyring: KeyringEntity
    let existing: KeyEntity?

    @State private var name: String
    @State private var opens: String
    @State private var category: KeyCategory
    @State private var notes: String
    @State private var assignedLocationName: String
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoData: Data?

    init(keyring: KeyringEntity, existing: KeyEntity?) {
        self.keyring = keyring
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _opens = State(initialValue: existing?.opens ?? "")
        _category = State(initialValue: existing?.category ?? .other)
        _notes = State(initialValue: existing?.notes ?? "")
        _assignedLocationName = State(initialValue: existing?.assignedLocationName ?? "")
        _photoData = State(initialValue: existing?.photoData)
    }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Key") {
                    TextField("What does this key open? (e.g. Front Door)", text: $name)
                        .accessibilityIdentifier("keyLabelField")
                    Picker("Category", selection: $category) {
                        ForEach(KeyCategory.allCases) { cat in
                            Label(cat.displayName, systemImage: cat.symbolName).tag(cat)
                        }
                    }
                    TextField("Note (e.g. brass, top of the ring)", text: $notes)
                        .accessibilityIdentifier("keyNoteField")
                }

                Section("Where is it normally kept?") {
                    TextField("Optional, e.g. Kitchen drawer", text: $assignedLocationName)
                }

                Section("Photo") {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        HStack {
                            KeyPhotoView(photoData: photoData, symbolName: category.symbolName, size: 44)
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
                            if let existing { store.deleteKey(existing) }
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
                    Button("Cancel") { dismiss() }.buttonStyle(.plain)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .buttonStyle(.plain)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let locationName = assignedLocationName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : assignedLocationName
        if let existing {
            store.updateKey(existing, name: name, photoData: photoData, keyDescription: existing.keyDescription, opens: opens, category: category, notes: notes, assignedLocationName: locationName)
            dismiss()
        } else {
            guard store.canAddKey(to: keyring) else { return }
            store.addKey(to: keyring, name: name, photoData: photoData, keyDescription: "", opens: opens, category: category, notes: notes, assignedLocationName: locationName)
            dismiss()
        }
    }
}
