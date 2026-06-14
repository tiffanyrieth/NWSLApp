//
//  SupportView.swift
//  NWSLApp
//
//  "Support NWSLApp" (QOL v2 §5) — optional tips that help keep the app free. Pushed
//  from the Profile "Support" row. NWSLApp stays free with no ads, no paywalls, and
//  supporters get NO extra features — this is purely a way for fans who want to chip
//  in toward servers, data feeds, and the Apple Developer Program.
//
//  StoreKit lives in SupportStore; this is the screen: a hero, a one-time/monthly
//  switch, the four tip tiers, a CTA, Restore, a "where it goes" breakdown, and a
//  thank-you state after a successful tip.
//

import SwiftUI

struct SupportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = SupportStore()
    @State private var monthly = false
    @State private var selected: SupportTier?

    // The brand pink + its gradient (spec: linear-gradient(135°, #FF375F, #FF6B8A)).
    private let pink = Color(hex: "FF375F")
    private var pinkGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: "FF375F"), Color(hex: "FF6B8A")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        Group {
            if store.purchased {
                thankYou
            } else {
                content
            }
        }
        .background(Color.dsBgGrouped)
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadProducts() }
    }

    // MARK: - Main content

    private var content: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                billingToggle
                tierGrid
                cta
                restoreLink
                whereItGoes
                footer
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(pinkGradient)
                Image(systemName: "heart.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            Text("Built by a fan, for the fans")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.dsFgPrimary)
                .multilineTextAlignment(.center)
            Text("NWSLApp is indie-built and completely free. No ads, no paywalls, no tracking. Your support helps cover servers, data feeds, and the Apple Developer Program — and keeps it that way.")
                .font(.system(size: 13))
                .foregroundStyle(Color.dsFgSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // One-time / Monthly — a centered two-segment pill; pink when Monthly is active.
    private var billingToggle: some View {
        HStack(spacing: 0) {
            segment("One-time", isActive: !monthly) { monthly = false }
            segment("Monthly", isActive: monthly) { monthly = true }
        }
        .padding(3)
        .background(Color.dsBgCard)
        .clipShape(Capsule())
        .frame(maxWidth: 240)
    }

    private func segment(_ label: String, isActive: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? .white : Color.dsFgSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if isActive { Capsule().fill(monthly ? pink : Color.dsBgTertiary) }
                    }
                )
        }
        .buttonStyle(.plain)
    }

    private var tierGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(SupportStore.tiers) { tier in
                tierCard(tier)
            }
        }
    }

    private func tierCard(_ tier: SupportTier) -> some View {
        let isSelected = selected?.id == tier.id
        return Button { selected = tier } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(tier.emoji).font(.system(size: 26))
                Text(tier.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.dsFgPrimary)
                Text(store.displayPrice(tier, monthly: monthly))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isSelected ? pink : Color.dsFgPrimary)
                Text(tier.blurb)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsFgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .padding(14)
            .background(isSelected ? pink.opacity(0.12) : Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? pink : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var cta: some View {
        let enabled = selected != nil
        let busy = store.purchasing != nil
        return Button {
            if let tier = selected { Task { await store.purchase(tier, monthly: monthly) } }
        } label: {
            Group {
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Text(ctaLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(enabled ? .white : Color.dsFgTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(enabled ? AnyShapeStyle(pinkGradient) : AnyShapeStyle(Color.dsBgCard))
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
    }

    private var ctaLabel: String {
        guard let tier = selected else { return "Choose an amount" }
        return "Support with \(store.displayPrice(tier, monthly: monthly))"
    }

    private var restoreLink: some View {
        Button { Task { await store.restore() } } label: {
            Text("Restore purchases")
                .font(.system(size: 13))
                .foregroundStyle(Color.dsAccent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Where it goes

    private var whereItGoes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where it goes").trackedCaps().padding(.horizontal, 4)
            VStack(spacing: 0) {
                whereRow("📡", "Live match data feeds", "Real-time scores, stats, lineups")
                rowDivider
                whereRow("🖥️", "Server & hosting", "Push notifications, API, database")
                rowDivider
                whereRow("🍎", "Apple Developer Program", "$99/year to stay on the App Store")
                rowDivider
                whereRow("⚡", "New features", "Fan Zone games, How to Watch, more")
            }
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
        }
    }

    private func whereRow(_ emoji: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Text(emoji).font(.system(size: 18)).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15)).foregroundStyle(Color.dsFgPrimary)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.dsFgSecondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.dsSeparator).frame(height: 1).padding(.leading, 16)
    }

    private var footer: some View {
        Text("NWSLApp will always be free. Supporters get no extra features — just the knowledge that you're helping grow women's soccer.")
            .font(.system(size: 11))
            .foregroundStyle(Color.dsFgQuaternary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    // MARK: - Thank-you state

    private var thankYou: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("💛").font(.system(size: 64))
            Text("Thank you!")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.dsFgPrimary)
            Text("Your support directly helps keep NWSLApp free for every fan. You're part of what makes this community special.")
                .font(.system(size: 14))
                .foregroundStyle(Color.dsFgSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button("Back to Profile") { dismiss() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.dsAccent)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack { SupportView() }
}
