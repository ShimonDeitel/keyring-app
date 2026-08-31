import SwiftUI

struct KeyringRowView: View {
    let keyring: KeyringEntity
    let isPro: Bool

    var body: some View {
        HStack(spacing: 14) {
            let color = keyringIconColor(for: keyring.icon)
            ZStack {
                RoundedRectangle(cornerRadius: KRTheme.smallCorner)
                    .fill(color.opacity(0.16))
                Image(systemName: keyring.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(color)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(keyring.name)
                    .font(KRTheme.headlineFont)
                    .foregroundStyle(KRTheme.ink)
                if let location = keyring.locationName, !location.isEmpty {
                    Text(location)
                        .font(.subheadline)
                        .foregroundStyle(KRTheme.inkFaded)
                }
            }

            Spacer()

            if isPro {
                Text("\(keyring.keyCount) key\(keyring.keyCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(KRTheme.inkFaded)
            } else {
                PlanUsageBadge(used: keyring.keyCount, limit: PlanLimits.freeMaxKeysPerKeyring)
            }
        }
        .padding(.vertical, 6)
    }
}
