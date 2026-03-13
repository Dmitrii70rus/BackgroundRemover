import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Unlock Premium")
                    .font(.largeTitle.bold())

                Text("Free users can remove backgrounds from up to 3 photos. Upgrade once to remove unlimited backgrounds forever.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Unlimited background removals", systemImage: "checkmark.circle.fill")
                    Label("No subscription", systemImage: "checkmark.circle.fill")
                    Label("Restore anytime", systemImage: "checkmark.circle.fill")
                }
                .font(.subheadline)

                Group {
                    if purchaseManager.isLoadingProducts {
                        ProgressView("Loading offer…")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if let product = purchaseManager.premiumProduct {
                        Button {
                            Task {
                                do {
                                    try await purchaseManager.purchasePremium()
                                    dismiss()
                                } catch {
                                    if case StoreError.userCancelled = error {
                                        return
                                    }
                                    errorMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            HStack {
                                if purchaseManager.isPurchasing {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text("Unlock Premium • \(product.displayPrice)")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(purchaseManager.isPurchasing)
                    } else {
                        Text("Store unavailable right now. Please try again later.")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Restore Purchases") {
                    Task {
                        do {
                            try await purchaseManager.restorePurchases()
                            if purchaseManager.isPremiumUnlocked {
                                dismiss()
                            }
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(purchaseManager.isPurchasing)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
