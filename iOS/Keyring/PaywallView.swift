import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var purchasing = false

    var body: some View {
        NavigationStack {
            ZStack {
                KRTheme.backdrop.ignoresSafeArea()

                VStack(spacing: 24) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(KRTheme.brassBright)
                        .padding(.top, 40)

                    Text("Keyring Pro")
                        .font(KRTheme.titleFont)
                        .foregroundStyle(KRTheme.ink)

                    VStack(alignment: .leading, spacing: 14) {
                        featureRow("infinity", "Unlimited identified keys")
                        featureRow("sparkles", "Support future updates")
                    }
                    .padding(.horizontal, 32)

                    Spacer()

                    Button {
                        purchasing = true
                        Task {
                            await purchases.purchase()
                            purchasing = false
                            if purchases.isPro { dismiss() }
                        }
                    } label: {
                        HStack {
                            if purchasing {
                                ProgressView().tint(.white)
                            } else {
                                Text(purchases.product.map { "Unlock for \($0.displayPrice)" } ?? "Unlock Pro")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(KRTheme.brass)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(purchasing || purchases.product == nil)
                    .padding(.horizontal, 24)

                    Button("Restore Purchases") {
                        Task { await purchases.restore() }
                    }
                    .buttonStyle(.plain)
                    .font(.footnote)
                    .foregroundStyle(KRTheme.inkFaded)
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .buttonStyle(.plain)
                        .foregroundStyle(KRTheme.ink)
                }
            }
        }
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(KRTheme.brassBright)
                .frame(width: 24)
            Text(text)
                .foregroundStyle(KRTheme.ink)
        }
    }
}

#Preview {
    PaywallView().environmentObject(PurchaseManager())
}
