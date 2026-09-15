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
    @State private var isCheckingDuplicates = false
    @State private var duplicateCandidates: [DuplicateDetectionService.Candidate] = []
    @State private var showDeleteConfirm = false

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
                    TextField("Name this key (e.g. Front Door Key)", text: $name)
                        .accessibilityIdentifier("keyLabelField")
                    TextField("What does it open? (e.g. Front Door)", text: $opens)
                        .accessibilityIdentifier("keyOpensField")
                    Picker("Category", selection: $category) {
                        ForEach(KeyCategory.allCases) { cat in
                            Label(cat.displayName, systemImage: cat.symbolName)
                                .foregroundStyle(cat.color)
                                .tag(cat)
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
                            KeyPhotoView(photoData: photoData, symbolName: category.symbolName, tintColor: category.color, size: 44)
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
                            showDeleteConfirm = true
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
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveTappingCheckFirst() }
                    } label: {
                        if isCheckingDuplicates {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCheckingDuplicates)
                    .accessibilityLabel("Save")
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
            .sheet(isPresented: Binding(
                get: { !duplicateCandidates.isEmpty },
                set: { if !$0 { duplicateCandidates = [] } }
            )) {
                DuplicateCandidatesSheet(
                    candidates: duplicateCandidates,
                    onAddAnyway: {
                        duplicateCandidates = []
                        performSave()
                    },
                    onCancel: {
                        duplicateCandidates = []
                    }
                )
            }
            .confirmationDialog("Delete this key?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let existing { store.deleteKey(existing) }
                    dismiss()
                }
            }
        }
    }

    /// A newly picked photo (not the one the key already had) gets checked
    /// against every other key's photo for visual similarity — Pro only,
    /// entirely on-device.
    private func saveTappingCheckFirst() async {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let photoChanged = photoData != nil && photoData != existing?.photoData
        guard store.isPro, photoChanged, let photoData else {
            performSave()
            return
        }
        isCheckingDuplicates = true
        let otherKeys = store.keyrings.flatMap { $0.sortedKeys }.filter { $0.id != existing?.id }
        let candidates = await Task.detached(priority: .userInitiated) {
            DuplicateDetectionService.findCandidates(forNewPhoto: photoData, among: otherKeys)
        }.value
        isCheckingDuplicates = false
        if candidates.isEmpty {
            performSave()
        } else {
            Haptics.warning()
            duplicateCandidates = candidates
        }
    }

    private func performSave() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let locationName = assignedLocationName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : assignedLocationName
        if let existing {
            store.updateKey(existing, name: name, photoData: photoData, keyDescription: existing.keyDescription, opens: opens, category: category, notes: notes, assignedLocationName: locationName)
        } else {
            guard store.canAddKey(to: keyring) else { return }
            store.addKey(to: keyring, name: name, photoData: photoData, keyDescription: "", opens: opens, category: category, notes: notes, assignedLocationName: locationName)
        }
        dismiss()
    }
}

private struct DuplicateCandidatesSheet: View {
    let candidates: [DuplicateDetectionService.Candidate]
    let onAddAnyway: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                KRTheme.backdrop.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: KRTheme.Spacing.lg) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(KRTheme.brass)
                            .padding(.top, 24)
                        Text("Possible duplicate")
                            .font(KRTheme.titleFont)
                            .foregroundStyle(KRTheme.ink)
                        Text("This photo looks like a key you already have. Double check before adding another.")
                            .font(.subheadline)
                            .foregroundStyle(KRTheme.inkFaded)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, KRTheme.Spacing.lg)

                        VStack(spacing: 10) {
                            ForEach(Array(candidates.enumerated()), id: \.offset) { _, candidate in
                                HStack(spacing: 12) {
                                    KeyPhotoView(photoData: candidate.key.photoData, symbolName: candidate.key.category.symbolName, tintColor: candidate.key.category.color, size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.key.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(KRTheme.ink)
                                        StatusBadge(text: candidate.similarity.label, color: KRTheme.brass)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(KRTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: KRTheme.smallCorner))
                            }
                        }
                        .padding(.horizontal, KRTheme.Spacing.md)

                        VStack(spacing: 10) {
                            Button("Add Anyway") {
                                onAddAnyway()
                            }
                            .buttonStyle(.plain)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(KRTheme.brass)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                            Button("Cancel") {
                                onCancel()
                            }
                            .buttonStyle(.plain)
                            .font(.subheadline)
                            .foregroundStyle(KRTheme.inkFaded)
                        }
                        .padding(.horizontal, KRTheme.Spacing.lg)
                        .padding(.bottom, KRTheme.Spacing.lg)
                    }
                }
            }
        }
    }
}
