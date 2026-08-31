import SwiftUI

struct KeyringRowView: View {
    let keyring: KeyringEntity
    let isPro: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: KRTheme.smallCorner)
                    .fill(KRTheme.surfaceRaised)
                Image(systemName: keyring.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(KRTheme.brass)
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
