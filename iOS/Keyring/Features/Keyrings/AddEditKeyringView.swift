import SwiftUI

private let keyringIconChoices = [
    "key.fill", "house.fill", "car.fill", "briefcase.fill",
    "shippingbox.fill", "building.2.fill", "sailboat.fill", "leaf.fill"
]

struct AddEditKeyringView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String
    @State private var locationName: String

    let existing: KeyringEntity?
    let onSave: (String, String, String?) -> Void

    init(existing: KeyringEntity?, onSave: @escaping (String, String, String?) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _icon = State(initialValue: existing?.icon ?? keyringIconChoices[0])
        _locationName = State(initialValue: existing?.locationName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Home, Office, Rental", text: $name)
                        .accessibilityIdentifier("keyringNameField")
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(keyringIconChoices, id: \.self) { symbol in
                            Button {
                                icon = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 20))
                                    .foregroundStyle(icon == symbol ? .white : KRTheme.brass)
                                    .frame(width: 44, height: 44)
                                    .background(icon == symbol ? KRTheme.brass : KRTheme.surfaceRaised)
                                    .clipShape(RoundedRectangle(cornerRadius: KRTheme.smallCorner))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Where is this keyring usually kept?") {
                    TextField("Optional, e.g. Kitchen drawer", text: $locationName)
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle(existing == nil ? "New Keyring" : "Edit Keyring")
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
                        onSave(name, icon, locationName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : locationName)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Save")
                    .accessibilityIdentifier("saveKeyringButton")
                }
            }
        }
    }
}
