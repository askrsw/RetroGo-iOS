//
//  AppStorePurchaseManager.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/8.
//  Copyright © 2026 haharsw. All rights reserved.
//
//  ---------------------------------------------------------------------------------
//  This file is part of RetroGo.
//  ---------------------------------------------------------------------------------
//
//  RetroGo is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  RetroGo is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Combine
import StoreKit
import Foundation
import ObjcHelper

enum IAPProductID {
    static let monthly: String = {
        guard let dict = inAppPurchaseDict else { return "" }
        return dict["ProMonthly"] ?? ""
    }()

    static let yearly: String = {
        guard let dict = inAppPurchaseDict else { return "" }
        return dict["ProYearly"] ?? ""
    }()

    static let lifetime: String = {
        guard let dict = inAppPurchaseDict else { return "" }
        return dict["ProLifetime"] ?? ""
    }()

    private static let inAppPurchaseDict = Bundle.main.object(forInfoDictionaryKey: "InAppPurchase") as? Dictionary<String, String>
}

enum AppStoreProductKind: CaseIterable {
    case proMonthly
    case proYearly
    case proLifetime

    var productID: String {
        switch self {
        case .proMonthly:  return IAPProductID.monthly
        case .proYearly:   return IAPProductID.yearly
        case .proLifetime: return IAPProductID.lifetime
        }
    }

    init?(productID: String) {
        switch productID {
        case IAPProductID.monthly:  self = .proMonthly
        case IAPProductID.yearly:   self = .proYearly
        case IAPProductID.lifetime: self = .proLifetime
        default: return nil
        }
    }
}

struct AppStoreProductInfo {
    let kind: AppStoreProductKind
    let productID: String
    let displayName: String
    let displayDescription: String
    let displayPrice: String
    let price: Decimal
    let isPurchased: Bool

    // 订阅试用信息
    let hasFreeTrial: Bool
    let freeTrialDisplayText: String?          // e.g. "7-day free trial"
    let isEligibleForIntroOffer: Bool          // 当前 Apple ID 是否可用试用
}

struct AppStoreProEntitlementInfo {
    let kind: AppStoreProductKind
    let productID: String
    let isInFreeTrial: Bool
    let expirationDate: Date?

    var displayName: String {
        Self.localizedDisplayName(for: kind)
    }

    var isLifetime: Bool {
        kind == .proLifetime
    }

    private static func localizedDisplayName(for kind: AppStoreProductKind) -> String {
        switch kind {
        case .proMonthly:  return Bundle.localizedString(forKey: "iap_retrogo_pro_monthly")
        case .proYearly:   return Bundle.localizedString(forKey: "iap_retrogo_pro_yearly")
        case .proLifetime: return Bundle.localizedString(forKey: "iap_retrogo_pro_lifetime")
        }
    }
}

private struct CachedProEntitlement: Codable {
    let productID: String
    let isInFreeTrial: Bool
    let expirationDate: Date?

    init(entitlement: AppStoreProEntitlementInfo) {
        productID = entitlement.productID
        isInFreeTrial = entitlement.isInFreeTrial
        expirationDate = entitlement.expirationDate
    }
}

enum AppStorePurchaseResult {
    case success
    case pending
    case userCancelled
}

enum AppStorePurchaseError: LocalizedError {
    case invalidProductID
    case productNotLoaded
    case verificationFailed
    case operationInProgress
    case noActiveEntitlements
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidProductID:
            return Bundle.localizedString(forKey: "iap_error_invalid_product_id")
        case .productNotLoaded:
            return Bundle.localizedString(forKey: "iap_error_product_not_loaded")
        case .verificationFailed:
            return Bundle.localizedString(forKey: "iap_error_transaction_verifi_failed")
        case .operationInProgress:
            return Bundle.localizedString(forKey: "iap_error_another_purchase_in_progress")
        case .noActiveEntitlements:
            return Bundle.localizedString(forKey: "iap_error_no_purchase_available_to_restore")
        case .unknown:
            return Bundle.localizedString(forKey: "iap_error_unknown_purchase_error")
        }
    }
}

extension Notification.Name {
    static let appStorePurchaseStateDidChange = Notification.Name("appStorePurchaseStateDidChange")
}

enum AppStorePurchaseFlowState: Equatable {
    case idle
    case purchasing(AppStoreProductKind)
    case restoring
    case pending(AppStoreProductKind)
    case cancelled
    case purchased(AppStoreProductKind)
    case restored
    case failed(String)
}

extension AppStorePurchaseFlowState {
    var isLoading: Bool {
        switch self {
        case .purchasing, .restoring:
            return true
        default:
            return false
        }
    }

    var isPurchasing: Bool {
        if case .purchasing = self { return true }
        return false
    }

    var isRestoring: Bool {
        if case .restoring = self { return true }
        return false
    }
}

enum AppStoreBootstrapState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

fileprivate let cachedProEntitlementKey = "AppStorePurchaseManager.cachedProEntitlement"

@MainActor
final class AppStorePurchaseManager: ObservableObject {
    static let shared = AppStorePurchaseManager()
    private init() {
        activeProEntitlement = Self.loadCachedProEntitlement()
        if let activeProEntitlement {
            purchasedProductIDs.insert(activeProEntitlement.productID)
        }
        transactionUpdatesTask = observeTransactionUpdates()
        ensureBootstrapped()
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func ensureBootstrapped() {
        guard bootstrapState != .ready, bootstrapTask == nil else { return } // 幂等
        bootstrapTask = Task { [weak self] in
            await self?.bootstrap()
        }
    }

    func retryBootstrapIfNeeded() {
        guard !isReady else { return }
        bootstrapTask = nil
        ensureBootstrapped()
    }

    // MARK: - State

    @Published private(set) var flowState: AppStorePurchaseFlowState = .idle
    @Published private(set) var bootstrapState: AppStoreBootstrapState = .idle

    private var transactionUpdatesTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var productsByKind: [AppStoreProductKind: Product] = [:]
    private(set) var purchasedProductIDs = Set<String>()
    private(set) var activeProEntitlement: AppStoreProEntitlementInfo?
    private var introOfferEligibilityByKind: [AppStoreProductKind: Bool] = [:]

    var onStateChanged: (() -> Void)?

    var isProPurchased: Bool {
        guard let activeProEntitlement else { return false }
        return Self.isLocallyValidEntitlement(
            kind: activeProEntitlement.kind,
            expirationDate: activeProEntitlement.expirationDate
        )
    }

    var isReady: Bool {
        if case .ready = bootstrapState { return true }
        return false
    }

    nonisolated static var hasLocallyValidCachedProEntitlement: Bool {
        loadCachedProEntitlement() != nil
    }

    // MARK: - Public API

    func loadProducts() async throws {
        let ids = Set(AppStoreProductKind.allCases.map(\.productID).filter { !$0.isEmpty })
        guard !ids.isEmpty else {
            throw AppStorePurchaseError.invalidProductID
        }

        let products = try await Product.products(for: ids)
        var map: [AppStoreProductKind: Product] = [:]

        for product in products {
            guard let kind = AppStoreProductKind(productID: product.id) else { continue }
            map[kind] = product
        }

        productsByKind = map
        await refreshIntroOfferEligibilityCache()
        notifyStateChanged()
    }

    func productInfos() -> [AppStoreProductInfo] {
        AppStoreProductKind.allCases.compactMap { kind in
            guard let product = productsByKind[kind] else { return nil }
            return makeProductInfo(kind: kind, product: product)
        }
    }

    func productInfo(for kind: AppStoreProductKind) -> AppStoreProductInfo? {
        guard let product = productsByKind[kind] else { return nil }
        return makeProductInfo(kind: kind, product: product)
    }

    func purchase(_ kind: AppStoreProductKind) async throws -> AppStorePurchaseResult {
        guard !flowState.isLoading else {
            throw AppStorePurchaseError.operationInProgress
        }

        setFlowState(.purchasing(kind))

        do {
            if productsByKind[kind] == nil {
                try await loadProducts()
            }

            guard let product = productsByKind[kind] else {
                setFlowState(.failed(AppStorePurchaseError.productNotLoaded.localizedDescription))
                throw AppStorePurchaseError.productNotLoaded
            }

            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try verified(verification)

                guard isUsablePurchasedTransaction(transaction, fallbackKind: kind) else {
                    await transaction.finish()
                    await refreshEntitlements(allowClearingActiveEntitlement: true)
                    setFlowState(.failed(AppStorePurchaseError.noActiveEntitlements.localizedDescription))
                    throw AppStorePurchaseError.noActiveEntitlements
                }

                applyPurchasedTransaction(transaction, fallbackKind: kind)
                await transaction.finish()
                await refreshEntitlements()
                setFlowState(.purchased(kind))
                return .success

            case .pending:
                setFlowState(.pending(kind))
                return .pending

            case .userCancelled:
                setFlowState(.cancelled)
                return .userCancelled

            @unknown default:
                setFlowState(.pending(kind))
                return .pending
            }
        } catch {
            setFlowState(.failed(error.localizedDescription))
            throw error
        }
    }

    func restorePurchases() async throws {
        guard !flowState.isLoading else {
            throw AppStorePurchaseError.operationInProgress
        }

        setFlowState(.restoring)

        do {
            try await AppStore.sync()
            await refreshEntitlements(allowClearingActiveEntitlement: true)

            guard isProPurchased else {
                throw AppStorePurchaseError.noActiveEntitlements
            }

            setFlowState(.restored)
        } catch {
            setFlowState(.failed(error.localizedDescription))
            throw error
        }
    }

    func refreshEntitlements(allowClearingActiveEntitlement: Bool = false) async {
        var ids = Set<String>()
        var entitlements: [AppStoreProEntitlementInfo] = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            guard transaction.revocationDate == nil,
                  let kind = AppStoreProductKind(productID: transaction.productID) else {
                continue
            }

            ids.insert(transaction.productID)
            entitlements.append(makeProEntitlementInfo(kind: kind, transaction: transaction))
        }

        if let entitlement = preferredProEntitlement(from: entitlements) {
            purchasedProductIDs = ids
            activeProEntitlement = entitlement
            cacheActiveProEntitlement()
        } else if let activeProEntitlement, Self.isLocallyValidEntitlement(kind: activeProEntitlement.kind, expirationDate: activeProEntitlement.expirationDate), !allowClearingActiveEntitlement {
            purchasedProductIDs = [activeProEntitlement.productID]
            cacheActiveProEntitlement()
        } else {
            purchasedProductIDs = []
            activeProEntitlement = nil
            Self.clearCachedProEntitlement()
        }

        if !productsByKind.isEmpty {
            await refreshIntroOfferEligibilityCache()
        }
        notifyStateChanged()
    }

    func isPurchased(_ kind: AppStoreProductKind) -> Bool {
        guard isProPurchased else { return false }
        return purchasedProductIDs.contains(kind.productID)
    }

    // MARK: - Private

    private func makeProductInfo(kind: AppStoreProductKind, product: Product) -> AppStoreProductInfo {
        let trialText = freeTrialDisplayText(for: product)
        let hasFreeTrial = trialText != nil
        let eligible = introOfferEligibilityByKind[kind] ?? false

        return AppStoreProductInfo(
            kind: kind,
            productID: product.id,
            displayName: fallbackDisplayName(for: kind),
            displayDescription: product.description,
            displayPrice: product.displayPrice,
            price: product.price,
            isPurchased: isPurchased(kind),
            hasFreeTrial: hasFreeTrial,
            freeTrialDisplayText: trialText,
            isEligibleForIntroOffer: hasFreeTrial ? eligible : false
        )
    }

    private func applyPurchasedTransaction(_ transaction: Transaction, fallbackKind: AppStoreProductKind) {
        guard transaction.revocationDate == nil else { return }

        let kind = AppStoreProductKind(productID: transaction.productID) ?? fallbackKind
        purchasedProductIDs.insert(transaction.productID)

        let entitlement = makeProEntitlementInfo(kind: kind, transaction: transaction)
        if let current = activeProEntitlement {
            activeProEntitlement = preferredProEntitlement(from: [current, entitlement])
        } else {
            activeProEntitlement = entitlement
        }
        cacheActiveProEntitlement()
    }

    private func isUsablePurchasedTransaction(_ transaction: Transaction, fallbackKind: AppStoreProductKind) -> Bool {
        guard transaction.revocationDate == nil else { return false }

        let kind = AppStoreProductKind(productID: transaction.productID) ?? fallbackKind
        if kind == .proLifetime {
            return true
        }

        guard let expirationDate = transaction.expirationDate else {
            return true
        }

        return expirationDate > Date()
    }

    private func makeProEntitlementInfo(kind: AppStoreProductKind, transaction: Transaction) -> AppStoreProEntitlementInfo {
        return AppStoreProEntitlementInfo(
            kind: kind,
            productID: transaction.productID,
            isInFreeTrial: isFreeTrialEntitlement(kind: kind, transaction: transaction),
            expirationDate: transaction.expirationDate
        )
    }

    private func isFreeTrialEntitlement(kind: AppStoreProductKind, transaction: Transaction) -> Bool {
        guard transaction.offerType == .introductory else {
            return false
        }

        if let paymentMode = productsByKind[kind]?.subscription?.introductoryOffer?.paymentMode {
            return paymentMode == .freeTrial
        }

        // Product metadata may not be loaded when the app restores cached/current
        // entitlements during launch. RetroGo currently only offers an introductory
        // free trial on the yearly plan, so keep the entitlement state consistent
        // before Product.products(for:) finishes.
        return kind == .proYearly
    }

    private func preferredProEntitlement(from entitlements: [AppStoreProEntitlementInfo]) -> AppStoreProEntitlementInfo? {
        entitlements.sorted { lhs, rhs in
            entitlementPriority(lhs.kind) > entitlementPriority(rhs.kind)
        }.first
    }

    private func entitlementPriority(_ kind: AppStoreProductKind) -> Int {
        switch kind {
        case .proLifetime: return 3
        case .proYearly:   return 2
        case .proMonthly:  return 1
        }
    }

    private func fallbackDisplayName(for kind: AppStoreProductKind) -> String {
        switch kind {
        case .proMonthly:  return Bundle.localizedString(forKey: "iap_retrogo_pro_monthly")
        case .proYearly:   return Bundle.localizedString(forKey: "iap_retrogo_pro_yearly")
        case .proLifetime: return Bundle.localizedString(forKey: "iap_retrogo_pro_lifetime")
        }
    }

    private nonisolated static func isLocallyValidEntitlement(kind: AppStoreProductKind, expirationDate: Date?) -> Bool {
        if kind == .proLifetime {
            return true
        }

        guard let expirationDate else {
            return true
        }

        return expirationDate > Date()
    }

    private func cacheActiveProEntitlement() {
        guard let activeProEntitlement else {
            Self.clearCachedProEntitlement()
            return
        }

        let cache = CachedProEntitlement(entitlement: activeProEntitlement)
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cachedProEntitlementKey)
        }
    }

    private nonisolated static func clearCachedProEntitlement() {
        UserDefaults.standard.removeObject(forKey: cachedProEntitlementKey)
    }

    private nonisolated static func loadCachedProEntitlement() -> AppStoreProEntitlementInfo? {
        guard let data = UserDefaults.standard.data(forKey: cachedProEntitlementKey),
              let cache = try? JSONDecoder().decode(CachedProEntitlement.self, from: data),
              let kind = AppStoreProductKind(productID: cache.productID) else {
            return nil
        }

        if !isLocallyValidEntitlement(kind: kind, expirationDate: cache.expirationDate) {
            clearCachedProEntitlement()
            return nil
        }

        return AppStoreProEntitlementInfo(
            kind: kind,
            productID: cache.productID,
            isInFreeTrial: cache.isInFreeTrial,
            expirationDate: cache.expirationDate
        )
    }

    private func refreshIntroOfferEligibilityCache() async {
        var cache: [AppStoreProductKind: Bool] = [:]

        for (kind, product) in productsByKind {
            guard let subscription = product.subscription,
                  subscription.introductoryOffer != nil else {
                continue
            }
            cache[kind] = await subscription.isEligibleForIntroOffer
        }

        introOfferEligibilityByKind = cache
    }

    private func freeTrialDisplayText(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer else { return nil }

        switch offer.paymentMode {
        case .freeTrial:
            return formatSubscriptionPeriod(offer.period) + Bundle.localizedString(forKey: "iap_free_trial")
        default:
            return nil
        }
    }

    private func formatSubscriptionPeriod(_ period: Product.SubscriptionPeriod) -> String {
        let value = period.value
        switch period.unit {
        case .day:
            return Bundle.localizedString(forKey: "iap_period_unit_day", count: value)
        case .week:
            return Bundle.localizedString(forKey: "iap_period_unit_week", count: value)
        case .month:
            return Bundle.localizedString(forKey: "iap_period_unit_month", count: value)
        case .year:
            return Bundle.localizedString(forKey: "iap_period_unit_year", count: value)
        @unknown default:
            return ""
        }
    }

    private func bootstrap() async {
        defer { bootstrapTask = nil }
        setBootstrapState(.loading)

        await consumeUnfinishedTransactions()
        await refreshEntitlements(allowClearingActiveEntitlement: true)

        do {
            try await loadProducts()
            setBootstrapState(.ready)
        } catch {
            setBootstrapState(.failed(error.localizedDescription))
        }
    }

    private func setBootstrapState(_ state: AppStoreBootstrapState) {
        bootstrapState = state
        notifyStateChanged()
    }

    private func setFlowState(_ state: AppStorePurchaseFlowState) {
        flowState = state
        notifyStateChanged()
    }

    func clearFlowState() {
        guard !flowState.isLoading else { return }
        setFlowState(.idle)
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }

            for await result in Transaction.updates {
                do {
                    let transaction = try await self.verified(result)
                    if transaction.revocationDate == nil,
                       let kind = AppStoreProductKind(productID: transaction.productID) {
                        await self.applyPurchasedTransaction(transaction, fallbackKind: kind)
                    }
                    await transaction.finish()
                    let allowsClearing = transaction.revocationDate != nil &&
                        AppStoreProductKind(productID: transaction.productID) != nil
                    await self.refreshEntitlements(allowClearingActiveEntitlement: allowsClearing)
                } catch {
                    // Ignore invalid transaction update
                }
            }
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw AppStorePurchaseError.verificationFailed
        }
    }

    private func consumeUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            do {
                let transaction = try verified(result)
                await transaction.finish()
            } catch {
                // ignore unverified unfinished transactions
            }
        }
    }

    private func notifyStateChanged() {
        onStateChanged?()
        NotificationCenter.default.post(name: .appStorePurchaseStateDidChange, object: nil)
    }
}
