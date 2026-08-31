import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: KRTheme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(KRTheme.brass)
            Text(title)
                .font(KRTheme.headlineFont)
                .foregroundStyle(KRTheme.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(KRTheme.inkFaded)
                .multilineTextAlignment(.center)
                .padding(.horizontal, KRTheme.Spacing.xl)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .padding(.horizontal, KRTheme.Spacing.lg)
                    .padding(.vertical, KRTheme.Spacing.sm)
                    .background(KRTheme.brass)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(.top, KRTheme.Spacing.sm)
            }
        }
        .padding(KRTheme.Spacing.lg)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct PlanUsageBadge: View {
    let used: Int
    let limit: Int

    var body: some View {
        Text("\(used) / \(limit)")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(used >= limit ? KRTheme.lostColor : KRTheme.inkFaded)
    }
}
