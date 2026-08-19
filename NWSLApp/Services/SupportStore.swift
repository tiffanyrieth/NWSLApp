//
//  SupportStore.swift
//  NWSLApp
//
//  The StoreKit 2 layer behind the Support screen (QOL v2 §5) — optional "tip" IAPs
//  that help cover servers, data feeds, and the Apple Developer Program. The app's
//  core is free and supporters get no extra features, so these are pure tips —
//  four ONE-TIME consumables (no subscriptions: Apple 3.1.1 bars auto-renewable tips
//  that unlock no ongoing value).
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

    /// One-time consumable product id. Tips are ONE-TIME ONLY — Apple (guideline 3.1.1) does not
    /// allow auto-renewable subscriptions that unlock no ongoing exclusive value, and a pure tip does
    /// not. (Revisit if a premium tier ever ships.)
    var oneTimeID: String { "com.tiffanyrieth.nwslapp.tip.\(id)" }
}

@MainActor
@Observable
final class SupportStore {
    /// The four tiers, in grid order (spec §5).
    static let tiers: [SupportTier] = [
        .init(id: "corner",  emoji: "⚽",  title: "Corner Kick", blurb: "Covers a day of API calls",            fallbackPrice: "$2"),
        .init(id: "freekick", emoji: "🥅", title: "Free Kick",   blurb: "Keeps the servers running for a week",  fallbackPrice: "$5"),
        .init(id: "penalty", emoji: "🏟️", title: "Penalty Kick", blurb: "Covers a month of match data",          fallbackPrice: "$10"),
        .init(id: "hattrick", emoji: "🏆", title: "Hat Trick",   blurb: "Funds a full month of development",     fallbackPrice: "$20"),
    ]

    /// Loaded StoreKit products, keyed by product id (empty until `loadProducts`).
    private(set) var products: [String: Product] = [:]
    /// Set after a successful purchase — drives the thank-you state.
    private(set) var purchased = false
    /// The product id currently being purchased (drives the CTA spinner).
    private(set) var purchasing: String?
    /// Honest, user-facing message for any non-success outcome (failed/unverified/pending
    /// purchase, unreachable App Store). nil = nothing to show. NEVER let a failed tip look
    /// like a success — the worst case is a "thank you" with no charge taken.
    private(set) var errorMessage: String?

    private var allProductIDs: [String] {
        Self.tiers.map(\.oneTimeID)
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let fetched = try await Product.products(for: allProductIDs)
            products = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        } catch {
            // The grid still renders with fallback prices, but a purchase can't proceed
            // without a loaded Product — flag it so a dead StoreKit config/outage is seen.
            Diagnostics.shared.record(.apiFailure, "support loadProducts: \(error.localizedDescription)")
        }
    }

    /// The price to show: StoreKit's localized price if the Product loaded, else the
    /// spec fallback (so the grid always shows an amount).
    func displayPrice(_ tier: SupportTier) -> String {
        products[tier.oneTimeID]?.displayPrice ?? tier.fallbackPrice
    }

    /// Buy a tier. Verifies + finishes the transaction and flips `purchased` ONLY on a
    /// verified success. Every other outcome is made HONEST: a verification failure or a
    /// thrown error sets a "you weren't charged, try again" message (and telemetry); a
    /// pending purchase says so; a user-cancel is silent (they chose). Never a fake success.
    func purchase(_ tier: SupportTier) async {
        let id = tier.oneTimeID
        errorMessage = nil
        guard let product = products[id] else {
            // Products never loaded (StoreKit outage / bad config) — don't pretend.
            Diagnostics.shared.record(.apiFailure, "support purchase: product \(id) not loaded")
            errorMessage = "Couldn't reach the App Store. Please try again in a moment."
            return
        }
        purchasing = id
        defer { purchasing = nil }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                purchased = true
            case .success(.unverified(_, let verificationError)):
                // App Store couldn't verify the receipt — treat as NOT purchased.
                Diagnostics.shared.record(.apiFailure, "support purchase unverified \(id): \(verificationError.localizedDescription)")
                errorMessage = "Your purchase couldn't be verified, so you weren't charged. Please try again."
            case .pending:
                // Deferred (Ask to Buy / SCA) — honest: it isn't done yet.
                errorMessage = "Your tip is pending approval — it'll complete once approved. You haven't been charged yet."
            case .userCancelled:
                break   // user chose to cancel — no error, no telemetry
            @unknown default:
                Diagnostics.shared.record(.apiFailure, "support purchase \(id): unknown result")
                errorMessage = "Something went wrong with the purchase. You weren't charged."
            }
        } catch {
            Diagnostics.shared.record(.apiFailure, "support purchase \(id): \(error.localizedDescription)")
            errorMessage = "Something went wrong with the purchase. You weren't charged — please try again."
        }
    }

    /// Return from the thank-you state to the tier picker (e.g. to tip again).
    func reset() { purchased = false; errorMessage = nil }
}
