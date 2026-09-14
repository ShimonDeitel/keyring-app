import SwiftUI

private let proFeatures: [(icon: String, text: String)] = [
    ("infinity", "Unlimited keys and keyrings"),
    ("bell.badge", "Loan reminders -- know the day a key is due back"),
    ("mappin.and.ellipse", "Location history for every key"),
    ("clock.arrow.circlepath", "Full activity history"),
    ("magnifyingglass", "Search across every keyring")
]

struct PaywallView: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var purchasing = false
    @State private var purchasingOneTime = false

    var body: some View {
        NavigationStack {
            ZStack {
                KRTheme.backdrop.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(KRTheme.brassBright)
                            .padding(.top, 40)

                        Text("Keyring Pro")
                            .font(KRTheme.titleFont)
                            .foregroundStyle(KRTheme.ink)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(proFeatures, id: \.text) { feature in
                                HStack(spacing: 12) {
                                    Image(systemName: feature.icon)
                                        .foregroundStyle(KRTheme.brassBright)
                                        .frame(width: 24)
                                    Text(feature.text)
                                        .foregroundStyle(KRTheme.ink)
                                }
                            }
                        }
                        .padding(.horizontal, 32)

                        Button {
                            purchasing = true
                            Task {
                                await purchases.purchaseMonthly()
                                purchasing = false
                                if purchases.isPro { dismiss() }
                            }
                        } label: {
                            VStack(spacing: 2) {
                                if purchasing {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(purchases.monthlyProduct.map { "Subscribe -- \($0.displayPrice)/month" } ?? "Subscribe to Pro")
                                        .font(.headline)
                                    Text("Cancel anytime.")
                                        .font(.caption)
                                        .opacity(0.85)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(KRTheme.brass)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .disabled(purchasing || purchases.monthlyProduct == nil)
                        .padding(.horizontal, 24)
                        .accessibilityIdentifier("unlockProButton")

                        Button {
                            purchasingOneTime = true
                            Task {
                                await purchases.purchase()
                                purchasingOneTime = false
                                if purchases.isPro { dismiss() }
                            }
                        } label: {
                            if purchasingOneTime {
                                ProgressView()
                            } else {
                                Text(purchases.product.map { "Or unlock forever for \($0.displayPrice)" } ?? "Or unlock forever")
                                    .font(.footnote)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(KRTheme.inkFaded)
                        .disabled(purchasing || purchasingOneTime || purchases.product == nil)
                        .padding(.top, 2)
                        .accessibilityIdentifier("unlockProOneTimeButton")

                        Button("Restore Purchases") {
                            Task { await purchases.restore() }
                        }
                        .buttonStyle(.plain)
                        .font(.footnote)
                        .foregroundStyle(KRTheme.inkFaded)
                        .padding(.bottom, 24)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .foregroundStyle(KRTheme.ink)
                    .accessibilityLabel("Close")
                }
            }
        }
    }
}
