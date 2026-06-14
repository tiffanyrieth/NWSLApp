//
//  SupportStore.swift
//  NWSLApp
//
//  The StoreKit 2 layer behind the Support screen (QOL v2 §5) — optional "tip" IAPs
//  that help cover servers, data feeds, and the Apple Developer Program. NWSLApp is
//  and stays free; supporters get no extra features, so these are pure tips:
//  four one-time consumables, plus monthly auto-renewable equivalents.
//
//  @MainActor @Observable, owned by SupportView (not app-wide — only that screen
//  cares). Products load from the App Store (or the local NWSLApp.storekit config in
//  the simulator). Display always shows the tiers from `tiers` below, with the
//  real localized price when a Product is loaded and a spec fallback when it isn't —
//  so the screen renders even before/without StoreKit.
//

import Foundation
import StoreKit

/// One tip tier. `id` is the short suffix; the full product ids derive from it.
struct SupportTier: Identifiable, Hashable {
    let id: String          // "corner"
    let emoji: String
    let title: String       // "Corner Kick"
    let blurb: String       // "Covers a day of API calls"
    let fallbackPrice: String   // shown when StoreKit hasn't loaded the Product

    /// One-time consumable product id.
    var oneTimeID: String { "com.tiffanyrieth.nwslapp.tip.\(id)" }
    /// Monthly auto-renewable product id (same base + `.monthly`).
    var monthlyID: String { "com.tiffanyrieth.nwslapp.tip.\(id).monthly" }
}

@MainActor
@Observable
final class SupportStore {
    /// The four tiers, in grid order (spec §5).
    static let tiers: [SupportTier] = [
        .init(id: "corner",  emoji: "⚽",  title: "Corner Kick", blurb: "Covers a day of API calls",            fallbackPrice: "$0.99"),
        .init(id: "freekick", emoji: "🥅", title: "Free Kick",   blurb: "Keeps the servers running for a week",  fallbackPrice: "$2.99"),
        .init(id: "penalty", emoji: "🏟️", title: "Penalty Kick", blurb: "Covers a month of match data",          fallbackPrice: "$4.99"),
        .init(id: "hattrick", emoji: "🏆", title: "Hat Trick",   blurb: "Funds a full month of development",     fallbackPrice: "$9.99"),
    ]

    /// Loaded StoreKit products, keyed by product id (empty until `loadProducts`).
    private(set) var products: [String: Product] = [:]
    /// Set after a successful purchase — drives the thank-you state.
    private(set) var purchased = false
    /// The product id currently being purchased (drives the CTA spinner).
    private(set) var purchasing: String?

    private var allProductIDs: [String] {
        Self.tiers.flatMap { [$0.oneTimeID, $0.monthlyID] }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        let fetched = (try? await Product.products(for: allProductIDs)) ?? []
        products = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
    }

    private func productID(_ tier: SupportTier, monthly: Bool) -> String {
        monthly ? tier.monthlyID : tier.oneTimeID
    }

    /// The price to show: StoreKit's localized price if the Product loaded, else the
    /// spec fallback (so the grid always shows an amount). Monthly appends "/mo".
    func displayPrice(_ tier: SupportTier, monthly: Bool) -> String {
        let base = products[productID(tier, monthly: monthly)]?.displayPrice ?? tier.fallbackPrice
        return monthly ? "\(base)/mo" : base
    }

    /// Buy a tier. Verifies + finishes the transaction and flips `purchased` on
    /// success; cancellation/pending/failure leave state unchanged.
    func purchase(_ tier: SupportTier, monthly: Bool) async {
        let id = productID(tier, monthly: monthly)
        guard let product = products[id] else { return }
        purchasing = id
        defer { purchasing = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    purchased = true
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            // Surface nothing — a failed/declined tip just leaves the screen as-is.
        }
    }

    /// Restore — re-syncs entitlements (matters for the monthly subscriptions).
    func restore() async {
        try? await AppStore.sync()
    }

    /// Return from the thank-you state to the tier picker (e.g. to tip again).
    func reset() { purchased = false }
}
