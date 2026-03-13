import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var premiumProduct: Product?
    @Published private(set) var isPremiumUnlocked = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var remainingFreeUses: Int

    let productID = "backgroundremover.premium.unlock"
    let freeUsesLimit = 3

    private let usesKey = "backgroundremover.freeUsesCount"
    private var updatesTask: Task<Void, Never>?

    init() {
        let usedCount = UserDefaults.standard.integer(forKey: usesKey)
        remainingFreeUses = max(0, freeUsesLimit - usedCount)

        updatesTask = observeTransactionUpdates()

        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var canUseFreeRemoval: Bool {
        isPremiumUnlocked || remainingFreeUses > 0
    }

    func consumeFreeUseIfNeeded() {
        guard !isPremiumUnlocked else { return }

        let usedCount = UserDefaults.standard.integer(forKey: usesKey)
        let newCount = min(freeUsesLimit, usedCount + 1)
        UserDefaults.standard.set(newCount, forKey: usesKey)
        remainingFreeUses = max(0, freeUsesLimit - newCount)
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: [productID])
            premiumProduct = products.first
        } catch {
            premiumProduct = nil
        }
    }

    func purchasePremium() async throws {
        guard let product = premiumProduct else {
            throw StoreError.productUnavailable
        }

        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshEntitlements()
        case .userCancelled:
            throw StoreError.userCancelled
        case .pending:
            throw StoreError.pending
        @unknown default:
            throw StoreError.unknown
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result), transaction.productID == productID {
                unlocked = true
                break
            }
        }
        isPremiumUnlocked = unlocked
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task {
            for await result in Transaction.updates {
                if let transaction = try? checkVerified(result), transaction.productID == productID {
                    await transaction.finish()
                    await refreshEntitlements()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreError.verificationFailed
        }
    }
}

enum StoreError: LocalizedError {
    case productUnavailable
    case userCancelled
    case pending
    case verificationFailed
    case unknown

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "Premium is currently unavailable. Please try again later."
        case .userCancelled:
            return "Purchase canceled."
        case .pending:
            return "Purchase is pending approval."
        case .verificationFailed:
            return "Unable to verify purchase."
        case .unknown:
            return "Purchase failed. Please try again."
        }
    }
}
