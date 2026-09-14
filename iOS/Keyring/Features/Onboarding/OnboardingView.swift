import SwiftUI

/// One screen, no forced account/iCloud/location permission. Tapping through
/// leads straight into the real "add a key" flow — no separate mock form.
/// Only shown on a genuinely empty first launch; upgrading users (migrated
/// legacy data, or any existing keyring) never see it.
struct OnboardingView: View {
    let onGetStarted: () -> Void
    @State private var hasTurned = false

    var body: some View {
        ZStack {
            KRTheme.backdrop.ignoresSafeArea()
            VStack(spacing: KRTheme.Spacing.lg) {
                Spacer()
                Image(systemName: "key.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(KRTheme.brass)
                    .rotationEffect(.degrees(hasTurned ? -35 : 0))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            Haptics.lightTap()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) {
                                hasTurned = true
                            }
                        }
                    }
                Text("Welcome to Keyring")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(KRTheme.ink)
                Text("Your keys, organized.\nPhotograph each key so you always know which is which.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(KRTheme.inkFaded)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, KRTheme.Spacing.xl)
                Spacer()
                Button(action: onGetStarted) {
                    Text("Photograph Your First Key")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(KRTheme.brass)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboardingGetStartedButton")
                .padding(.horizontal, KRTheme.Spacing.xl)
                .padding(.bottom, KRTheme.Spacing.xl)
            }
        }
    }
}
