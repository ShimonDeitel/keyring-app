import SwiftUI

let keyringIconChoices = [
    "key.fill", "house.fill", "car.fill", "briefcase.fill",
    "shippingbox.fill", "building.2.fill", "sailboat.fill", "leaf.fill"
]

/// One accent per keyring icon choice, shared by the icon picker grid and
/// every keyring row/avatar so a ring's color stays consistent everywhere
/// it appears.
func keyringIconColor(for symbol: String) -> Color {
    switch symbol {
    case "house.fill": return KeyCategory.house.color
    case "car.fill": return KeyCategory.car.color
    case "briefcase.fill": return KeyCategory.office.color
    case "shippingbox.fill": return KeyCategory.storage.color
    case "building.2.fill": return Color(red: 0.35, green: 0.42, blue: 0.50)
    case "sailboat.fill": return Color(red: 0.22, green: 0.48, blue: 0.50)
    case "leaf.fill": return Color(red: 0.35, green: 0.53, blue: 0.32)
    default: return KRTheme.brass
    }
}

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
                            let color = keyringIconColor(for: symbol)
                            Button {
                                icon = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 22, height: 22)
                                    .foregroundStyle(icon == symbol ? .white : color)
                                    .frame(width: 44, height: 44)
                                    .background(icon == symbol ? color : color.opacity(0.16))
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
