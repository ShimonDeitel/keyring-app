import SwiftUI

struct KeyHistoryRowView: View {
    let event: KeyHistoryEntity
    var showKeyName: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.eventType.symbolName)
                .font(.system(size: 15))
                .foregroundStyle(KRTheme.brass)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                if let showKeyName {
                    Text(showKeyName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KRTheme.ink)
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(KRTheme.inkFaded)
            }
            Spacer()
            Text(event.timestamp.keyringRelativeDescription)
                .font(.caption)
                .foregroundStyle(KRTheme.inkFaded)
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        var parts = [event.eventType.displayName]
        if let location = event.locationName { parts.append(location) }
        if let person = event.person { parts.append(person) }
        return parts.joined(separator: " · ")
    }
}
