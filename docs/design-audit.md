# Pre-Launch Visual & Design-Consistency Audit

**Date:** 2026-07-17 · **Scope:** every screen (33 views) + component (35) + the two cross-cutting
lenses (component reuse, dark-mode). **Method:** 13 parallel read-in-full passes against the design-system
yardstick (`DSColor` / `DSText.dsFont` / `DSMetrics`), plus targeted in-sim screenshots. **This is a
flag-only report — nothing here has been changed.** Decide what to address before shipping.

## How to read this

Every finding is tagged and carries a `file:line`.

- 🔴 **Blocker** — dead/unfinished UI, a genuine accessibility failure, or a debug surface reaching real
  users. Fix before App Store.
- 🟡 **Polish** — a real, visible inconsistency (off-token color/type, divergent pattern, duplicated-and-
  disagreeing values). Worth fixing before launch or in a fast-follow.
- ⚪ **Nit** — mechanical token drift (a literal `16` instead of `DS.radiusXl`, a raw padding). Low
  individual impact; aggregated per file so the blockers stay visible.

**One structural fact colors the whole report:** there is **no shared `PrimaryButton`, no shared
`RetryStateView`, no single team-color resolver, and no single brand-color table.** Most 🟡 findings are
symptoms of those four missing seams — see the **Cross-Cutting** chapter, which is where the "built in
isolation" story really lives. The per-screen sections are where you'll see it surface.

---

## TL;DR — the short list

**Fix before App Store (🔴):**
1. **`NotificationDiagnosticsView` ships to release** — a disposable debug screen, one tap from Profile →
   Settings, exposing `device_id`/token state to real users. `ProfileView.swift:133` (unconditional
   `NavigationLink`, no `#if DEBUG`). *Confirmed — this is the clearest must-fix.*
2. **"COMING SOON" dead teaser in onboarding** — a prominent accent badge on a real-looking "Follow
   individual players" row in the first-run flow; it does nothing. `OnboardingView.swift:240`.
3. **White-on-amber CTA fails contrast** — the KnowHer Game primary buttons put white text on
   `dsGameSpotlight` #F5A623 (~1.9:1, below the 3:1 floor). `KnowHerGameView.swift:116, :320`.

**The biggest consistency story (🟡, app-wide):**
4. **The bare-chevron back button is documented but never implemented** — `.toolbarRole(.editor)` exists
   only in the doc comment; every drilled-in screen falls back to iOS's default back button. `DSText.swift:104-111`.
5. **The Fan Zone splits into two design families** — Bracket is fully on-system; Predict XI / Trivia /
   KnowHer are built on **UIKit semantic colors + raw fonts**, kept dark only by the single root
   `.preferredColorScheme(.dark)`.
6. **Four values are defined twice and disagree** — broadcast palette, platform palette, the team-color
   resolver (×7), and the TBD-gray (×5). Same concept, different hex depending on the screen.
7. **`PlayerDetailView` never migrated to the design system** — all raw `.font`, the one clear off-pattern
   screen in the Teams chain.

**Two dead components** sit in the tree unused: `PlayerCard.swift`, `SocialLinkButton.swift` (the latter
self-documents as unused). Plus dead `leaderboardCard` in `DailyTriviaView` (defined, never rendered).

---

## Severity summary by screen

| Area / screen | 🔴 | 🟡 | ⚪ | Standout |
|---|---|---|---|---|
| App shell / gate | 0 | 2 | 2 | ForceUpdate button radius 14 vs app's 10; "Social" tab mounts `FeedView` |
| Home | 0 | 5 | 2 | 3 different section-title styles on one screen; raw-white avatar ring |
| Schedule | 0 | 4 | 5 | MatchCard `padding(14)` vs its own token; TBD-gray raw hex |
| Standings | 0 | 4 | 2 | 7pt form badges (legibility); floating column header hand-aligned |
| Teams + detail | 0 | 7 | 4 | **PlayerDetailView off-DS**; 2 dead components; header crest 64 vs token 56 |
| Match Detail | 0 | 6 | 2 | UIKit `tertiarySystemFill` chip; 3rd copy of team-color resolver; stale comments |
| Social / Feed | 0 | 7 | 3 | divergent NEWS-pill green; duplicate `teamPill`; palette splits |
| Fan Zone | 1 | 6 | 6 | **UIKit-grouped screens**; white-on-amber CTA; emoji in game UI; dead card |
| Onboarding | 1 | 3 | 2 | **COMING SOON teaser**; system-List look; 3 CTA treatments in 2 screens |
| Settings / account | 1 | 6 | 3 | **debug screen ships**; 3 competing grouped-row systems; untokenized pink |
| Diagnostics / DEBUG | (1) | 1 | 0 | (the 🔴 is the ProfileView row, counted under Settings) |
| **Cross-cutting** | 1 | 8 | 2 | error/retry view re-rolled ×15; contrast; brand palettes |

*The 🔴 total across the app is 3 distinct issues (debug-ships, onboarding teaser, contrast); the table
lists each under its home screen so counts don't double-report.*

---

# Per-screen findings

## App shell / gate

**AppGateView** — clean, no findings.

**ForceUpdateView**
- 🟡 `ForceUpdateView.swift:43` — "Update" CTA uses `cornerRadius: 14`; every other accent button in the
  app uses 10. The wall's button reads slightly off. (Symptom of the missing shared button — see X-cut #5.)
- ⚪ `ForceUpdateView.swift:20,42,43,47` — literals that map 1:1 to tokens (`spacing:20`=`space10`, etc).

**RootTabView**
- 🟡 `RootTabView.swift:208-211` — the fifth tab's label is **"Social"** but the enum case is `.feed` and it
  mounts `FeedView()`. Confirm the label rename is intentional (view + tag still say "Feed").
- ⚪ `RootTabView.swift:153` — `restoringView` uses literal `spacing: 16` instead of `DS.space8`.

## Home

- 🟡 `HomeView.swift:407-409 / 235 / 788` — **three section-title treatments on one screen**: Club News =
  `.sectionTitle()` token; "Coming up" hand-rolls `dsFont(20,.bold)` inline (re-implements the token); Fan
  Zone = `dsFont(20,.heavy)`. Peers that should match don't.
- 🟡 `HomeView.swift:162` — profile-avatar ring uses raw `Color.white.opacity(0.08)`; every other hairline
  ring in the app uses `dsFgQuaternary`.
- 🟡 `HomeView.swift:326,346` — raw `.font(.subheadline)` (only non-`dsFont` type in the file; also escapes
  the Dynamic-Type cap).
- 🟡 `HomeView.swift:851 / 329,354,854` — error/retry uses system `.borderedProminent` while the sibling
  `moduleError` (807-824) is a custom `dsBgCard` retry card — two visual languages for the same action.
- ⚪ `FanZoneCard.swift:130,132,210,212` — hardcoded `cornerRadius: 16` (=`DS.radiusXl`); `FanZoneCarouselCard`
  and `SuperfanCard` copy-paste identical card chrome instead of sharing a container.
- ⚪ `HomeView` / `HomeContentListView` — aggregate literal spacing/padding (~20 sites) matching token
  values but written raw.

## Schedule

- 🟡 `ScheduleView.swift:459,476` — empty/error states use UIKit `Color(.systemGroupedBackground)` instead
  of `dsBgGrouped`; `:451,453,471` use raw `.font(.headline/.subheadline)`.
- 🟡 `MatchCard.swift:50` — internal `.padding(14)` while `DS.cardPadding` and its own doc-comment say 16.
- 🟡 `MatchCard.swift:220` / `PlayoffMatchupRow.swift:252,257` — TBD-gray `Color(hex:"8E8E93")` re-derived
  raw (it's byte-identical to `dsFgSecondary`). See X-cut #2.
- 🟡 `ScheduleView.swift:432 vs PlayoffPathView.swift:113` — the "Win →" element is cyan (`dsStateKickoff`)
  on one playoff surface and team-accent on the other. Same semantic, two colors.
- ⚪ Schedule/Playoff/ComingUpRow/HowToWatchCard — aggregate literal metrics. **MatchCard and
  PlayoffMatchupRow have NOT diverged** (same 60pt crests, same anatomy) — good; the playoff row is a
  faithful rebuild, not drift.
- ⚪ `ComingUpRow.swift:86` — LIVE badge uses raw `.font(.caption.bold)` while the match cards render the
  identical badge with `.dsFont(11,.bold)`.

## Standings

- 🟡 `StandingsView.swift:346,348-351` — error state uses `.foregroundStyle(.secondary)` + system
  `.borderedProminent` "Try again"; reads unfinished vs the polished table.
- 🟡 `StandingsView.swift:154-172` — the column header lives **outside** the card, aligned to the rows by
  manually-summed insets (`34`/`30`). Fragile; the most "ESPN stats-table pasted in" part of the app.
- 🟡 `StandingsView.swift:219` — playoff line uses raw `frame(height:1)` while the sibling divider uses
  `DS.hairline` — same 1pt concept, two sources.
- ⚪ `FormBadge.swift` in the Last-5 column renders at **7pt** (size 11) — real legibility risk on device,
  esp. white "D" on the mid-grey `dsResultDraw`. **Needs device eyes.**
- ⚪ Aggregate literal metrics; stale header doc-comment omits the GD column.

## Teams + club/player detail

- 🟡 **`PlayerDetailView.swift:36-115` — the whole screen uses raw `.font(.largeTitle/.title2/.subheadline/
  .caption)`, zero `.dsFont`**, plus `.foregroundStyle(.secondary)` and `Divider()` instead of the
  `dsSeparator` hairline. Its sibling `TeamDetailView` (same push chain) is fully on-system — so the Squad
  grid → PlayerDetail tap crosses a design-system boundary mid-chain. The clearest off-pattern screen here.
- 🟡 `TeamDetailView.swift:251-259` — `platformColor` is a raw brand palette that duplicates `PlatformBadge`
  with **different** hex. See X-cut #4.
- 🟡 `TeamDetailView.swift:93` — header crest `TeamLogo(size: 64)` vs its own token `DS.avatarXl = 56`.
- 🟡 `TeamDetailView.swift:307` — raw `.font(.callout)` in `sectionError`.
- 🟡 **`PlayerCard.swift` — dead code** (unreferenced; TeamDetail renders its own inline `playerCard` with a
  different design). Two divergent squad-cell designs, the component one unused.
- 🟡 **`SocialLinkButton.swift` — dead code** (its own header admits "currently unused").
- ⚪ Crest sizing varies across the chain (grid 58 / header 64 / list 24-32) and player-avatar diameters
  differ within one push chain (42 / 48 / 96) — the tapped monogram doesn't match its detail hero.
- `CompetitionsView` + `NationalTeamCard` are the best-aligned in the set — nav title correct, faithful
  card reuse.

## Match Detail

- 🟡 `MatchDetailView.swift:445` — substitute chip uses UIKit `Color(.tertiarySystemFill)`, a translucent
  adaptive gray that won't match the surrounding `dsBgCard`. (Renders acceptably on the forced-dark canvas,
  so 🟡 not 🔴 — but it's the one card fill that visibly differs. **Needs eyes.**)
- 🟡 `MatchDetailView.swift:1048-1053` — `sideColor` is the **3rd copy** of the team-color resolver, and
  `:1050` re-derives the TBD-gray raw. See X-cut #1/#2.
- 🟡 `MatchDetailView.swift:146-147` + `:302-306` — two **stale/contradictory comments**: the tabBar comment
  claims a "home-team-color/red" underline the code doesn't produce (it returns cyan/orange), and a "Task #3
  will add a FormationPitchView" comment describes work that already shipped.
- 🟡 `MDInfoCard.swift:33-34` — uses `dsBgCard`+`radiusMd`(12) while the Match-Detail token family has
  purpose-named `dsMdCard`(#1A1C23) + `radiusLg`(14) "for info cards" — a visible corner/surface mismatch
  when an info card sits beside a big card.
- 🟡 `PitchDot.swift` duplicates `PlayerDot` (headshot+monogram+ring+label), both re-emitting raw
  `.font(.system(...))`. See X-cut #6.
- ⚪ The screen has a **legacy seam**: newer components (timeline row, stat bar, header) are token-clean;
  the older Lineups/Stats sub-renders (~355-509) use `.font(.caption)`, raw `.secondary/.green/.red`, and
  literal `cornerRadius: 16`. The two pitches also render at different proportions (0.66 vs 0.70).

## Social / Feed

- 🟡 `ArticleContentCard.swift:108-116` — hand-rolled "NEWS" pill duplicates `CategoryPill` **and tints it a
  different green** (`dsStateFinal` vs CategoryPill's `#30D158` literal). Same label, two greens across
  Home vs Social. See X-cut #7. **Needs eyes** to confirm the shades read different.
- 🟡 `BroadcastChip.swift:44-55 vs BroadcastInfo.swift` — broadcast palette defined twice, **divergent**
  (ESPN `#E0203B` vs `#D32F2F`, ION red vs purple). See X-cut #3.
- 🟡 `PlatformBadge.swift:43-51 vs TeamDetailView.swift:253-257` — platform palette diverges on 4 of 5
  platforms. See X-cut #4.
- 🟡 `AvatarContentCard.swift:101-109` — `teamPill` is duplicated verbatim in `ArticleContentCard.swift:118-126`.
- 🟡 `CategoryPill.swift:45-49` — five semantic voice-category colors hardcoded as raw hex outside the DS
  allow-list (these are app-semantic, not brand — should be tokens).
- 🟡 `ThumbnailContentCard.swift:150,36` — inline Reddit `#FF4500` + raw `#444444` fallback.
- 🟡 `FeedView.swift:233 / FeedSourcesView.swift:87-90` — empty/error + the whole sources sheet bypass
  `dsFont`/`dsFg*` (native List styling — flag for a consistency decision).
- ⚪ The three content-card variants share chrome but diverge on inner padding (14 vs asymmetric 12/14) and
  introduce fractional type sizes (`14.5`, `10.5`) absent elsewhere.

## Fan Zone

**The headline:** these do **not** read as one family — Bracket is fully on-system; **Predict XI, Trivia,
KnowHer are built on UIKit semantic colors + raw fonts** and are kept dark only by the root
`.preferredColorScheme`. `DailyTriviaView` is the single most internally-inconsistent file (mixes
`Color.indigo` with `dsGameTrivia`, `.font` with `.dsFont` on one screen).

- 🔴 `KnowHerGameView.swift:116,:320` — **white-on-amber CTA fails contrast** (~1.9:1). The one true
  accessibility defect. **Needs eyes / an accessibility check.**
- 🟡 `PredictXIView / XIPickerView / KnowHerPickerView / DailyTriviaView / KnowHerGameView` — built on
  `Color(.systemGroupedBackground)` / `.secondary…` / `systemGray*` / `.separator` instead of `Color.ds*`.
  Full line list in the dark-mode chapter. The **pickers are sheets** → the classic place a UIKit semantic
  color can resolve to the *system* appearance; **on-device sheet check recommended.**
- 🟡 `KnowHerGameView.swift:377,379` — emoji "💛"/"🌱" in game result UI (check against the no-emoji-in-game-UI
  rule).
- 🟡 `KnowHerGameView.swift:439-478 / XIPickerView.swift:166-184` — two more reimplementations of the
  ringed-headshot avatar (3rd and 4th copies). See X-cut #6.
- 🟡 `FanZoneGate.swift:187-255` — the sign-in gate is hardcoded teal (`dsGameBracket`) regardless of the
  calling game, so Predict (pink) / Trivia (indigo) / KnowHer (amber) all show a teal gate.
- 🟡 `DailyTriviaView.swift:31` — `accent = Color.indigo` (raw) while the badge uses `dsGameTrivia` — two
  indigos on one screen.
- ⚪ **Dead code:** `DailyTriviaView.swift:315-355` `leaderboardCard` is fully defined but never rendered
  (superseded by `CommunityResultsView`). Not user-visible, but remove it.
- ⚪ Bracket family uses `dsBgPrimary`#000 + `dsMdCard`#1A1C23 — internally consistent but off the *canonical*
  page/card tokens (#1C1C1E / #2C2C2E). Aggregate literal-padding drift (BracketBattleView ~45 sites).
- `BracketLeaderboardView` and `FanZoneGate` are the cleanest non-Bracket-Battle files.

## Onboarding

- 🔴 `OnboardingView.swift:230-256` (badge at **:240**) — the "Follow individual players" row carries a
  bold accent **"COMING SOON"** capsule that draws the eye like a live feature and does nothing. Dead teaser
  in the first screen a user ever sees.
- 🟡 `OnboardingView.swift:285-310` — the CTA has **two constructions** (empty state = hand-drawn accent
  *outline* with a no-op action; active = system `.borderedProminent`), and `:310 vs ThesisView.swift:61`
  the button jumps `.regular`→`.large` size across the two-step flow.
- 🟡 `ThesisView.swift:80,88` — crests wrapped in a colored **ring**, violating the "TeamLogo, no ring" rule
  (only monograms get rings). The only ringed crests in the area.
- 🟡 Onboarding leans on a native `.listStyle(.insetGrouped)` List with system `.secondary`/`.accentColor`
  semantics — it reads like a stock iOS **Settings** screen, the least-"designed" surface, and it's the
  first impression. *(Screenshot confirmed: system-List rows + accent-outline CTA — see appendix shot 02.)*
- ⚪ Mixes DS tokens with `.secondary`/`.accentColor`/raw semantic fonts within one file.

## Settings / account

- 🔴 `ProfileView.swift:133` — **`NotificationDiagnosticsView` reachable in release.** Unconditional
  `NavigationLink`, no `#if DEBUG` anywhere in the file; the "Notification Diagnostics / Token registration
  state" row and its raw-`.font`/`Color.green/.red` debug UI ship to the App Store. Both inline comments say
  "TEMP … remove." *This is the confirmed must-fix.*
- 🟡 `ProfileView.swift:188,215 / SupportView.swift:24,26` — brand pink `#FF375F`/`#FF6B8A` hardcoded raw and
  duplicated across both files (no `dsSupport*` token).
- 🟡 `NotificationAuthPromptView.swift:36-82` — bypasses the design system almost entirely (raw `.title2/
  .subheadline`, `Color.accentColor/.secondary/.red`, `cornerRadius:12`) and sets **no `dsBgGrouped`
  background** — relies on the system default. Drifted apart from the parallel sign-in CTA in ProfileView.
- 🟡 Three competing grouped-row systems: **NotificationsView** is the only consumer of the shared
  `SettingsGroup`/`SettingsToggleRow`/`SettingsRowDivider` (sentence-case headers); **ProfileView** and
  **SupportView** each roll their own (CAPS `trackedCaps` headers + local dividers). The grouped surfaces
  visibly disagree on header style.
- 🟡 `NotificationsView.swift:123-188` — per-team rows hand-roll the toggle instead of `SettingsToggleRow`
  (the shared row has no leading-image variant); this one destination is reached by **3 different route
  styles** (typed route / `isPresented` / plain link).
- 🟡 `SupportView.swift:149-171` — hand-rolled gradient CTA + bespoke segmented billing pill.
- ⚪ Icon-tile radii `7`/`9` (ProfileView) and `14` (SupportView) written raw; `MatchAlertToast`/
  `SettingsToggleRow` otherwise clean.

---

# Cross-Cutting — where "built in isolation" really shows

This chapter is the heart of the "AI-generated / unaware of the rest of the app" concern. Each item is one
missing shared seam that spawned many of the per-screen 🟡s.

### 1. Error / retry state — re-rolled in ~15 screens 🟡 (highest-value fix)
There is **no shared retry view**. The identical `VStack { message + Button("Try again"/"Retry"){reload}
.borderedProminent }` is reimplemented in FeedView, StandingsView, TeamsView, CompetitionsView,
KnowHerPickerView, PredictXIView, MatchDetailView, ScheduleView, HomeView (×2), OnboardingView,
TeamDetailView, DailyTriviaView, CommunityResultsView, XIPickerView, BracketBattleView. They've **drifted**:
button label alternates "Try again" vs "Retry"; style alternates `.borderedProminent` vs `.bordered`. The
copy is centralized (`FeedStore.loadFailureMessage`) but the view is not. One `RetryStateView(message:action:)`
replaces all ~15 and is the single strongest reuse opportunity.

### 2. Team-color resolver — copy-pasted ×7 🟡 (and 3 copies are subtly wrong)
`DesignTeamColors.displayHex(for:) → Color.teamFillOnDark` is re-rolled in MatchCard:215,
PlayoffMatchupRow:249, MatchDetailView:1048 (`sideColor`), PlayoffPathView:220, KnowHerGameView:53,
KnowHerPickerView:111 & :185 (+ NationalTeam.swift:59 at the model layer). The **3 KnowHer sites skip
`teamFillOnDark`** (raw `Color(hex:)`), so near-black brand colors aren't lifted — an actual inconsistency,
not just duplication. Fallbacks also disagree (gray vs `.dsAccent`). A shared
`Color.teamColor(abbreviation:fallback:)` collapses all 7 and fixes the KnowHer bug.

### 3. TBD-gray re-derived ×5 🟡
`Color(hex:"8E8E93")` hardcoded in MatchCard:219, PlayoffMatchupRow:251 & :257, MatchDetailView:1050
(+ NationalTeam.swift:59). It is byte-identical to `dsFgSecondary` (`DSColor.swift:36`). Should reference the
token.

### 4. Broadcast + platform palettes defined twice, disagreeing 🟡
- **Broadcast** (`BroadcastChip.swift:44-55` vs `BroadcastInfo.swift`): ESPN `#E0203B`/`#D32F2F`, CBS
  `#1FA0E0`/`#1A73E8`, ION `#E4322B`/`#6B4EFF` (red vs purple), Victory+ teal vs green. A partner renders a
  different brand color on a Schedule chip vs the How-to-Watch section.
- **Platform** (`PlatformBadge.swift:38-53` vs `TeamDetailView.platformColor:251-259`, + inline Reddit in
  `ThumbnailContentCard.swift:150`): Bluesky, YouTube, TikTok, Instagram all diverge; only Reddit matches.

Both should collapse to one tokenized brand-color table. (The values are legitimate third-party brand
colors — the problem is two sources of truth, not the hexes.)

### 5. No shared PrimaryButton — radii disagree 🟡
The accent-filled/outlined CTA is hand-rolled in ForceUpdateView:43 (r=14), OnboardingView:293 (r=10,
outline), TeamsView:215 & FeedView:134 (r=10, and these two are actually *coach-mark tooltips* reusing the
CTA recipe). No `DSButton`/`ButtonStyle`. One shared style fixes the 10-vs-14 drift and the onboarding
outline-vs-filled split.

### 6. Player-avatar primitive reimplemented ×4 🟡
`PlayerDot`, `PitchDot`, `XIPickerView:166-184` (inline), and `KnowHerPlayerAvatar`
(`KnowHerGameView:439-478`) all wrap `PlayerHeadshot` with a team ring + jersey/monogram fallback + label.
The monogram/last-name/initials fallback logic is itself triplicated. One parameterized dot serves all.
(Ring convention is also applied inconsistently — PlayerDot/PitchDot ring; the 96pt PlayerDetail monogram
and the squad card don't.)

### 7. Bespoke "NEWS" pill duplicates CategoryPill 🟡
`ArticleContentCard.swift:108-116` hand-rolls a NEWS `Text`+`Capsule` that duplicates `CategoryPill` **and**
tints it a different green. Should render `CategoryPill(sourceType:.news)`.

### 8. Dark-only contract — intact, but leaning on one line 🟡
Enforced at a **single airtight point**: `NWSLAppApp.swift:83` `.preferredColorScheme(.dark)`. No light-mode
branch anywhere; the Live Activity (the only out-of-process surface) hardcodes its own dark hexes, so nothing
leaks light **today**. The risk is that the four Fan-Zone game screens (Trivia, KnowHer, Predict XI, the
pickers) are built almost entirely on adaptive UIKit backgrounds — visually correct now because they resolve
to nearly the exact DS hexes on a dark system, but they'd **invert if that one line were ever removed**, and
two adaptive tokens don't match any DS value even today:
- `Color(.separator)` at 0.6 opacity (`KnowHerPickerView.swift:165,169`) vs `dsSeparator` at 0.35 — a
  visibly heavier hairline than every other divider.
- `Color(.tertiarySystemFill)` translucent gray (`MatchDetailView.swift:445`, `TeamLogo.swift:152`
  placeholder) — matches no card token.

**Contrast:** the white-on-amber KnowHer CTA (item under Fan Zone) is the one real failure. `dsFgQuaternary`
#48484A on a #2C2C2E card ("TBD"/"VS" in BracketBattleView) is ~1.4:1 — near-invisible; confirm it's
intentional.

---

# The back-button treatment (app-wide) 🟡

`nativeBackButton(title:)` (`DSText.swift:107-111`) is meant to give every drilled-in screen the MLS/Athletic
**bare ‹ chevron**. Its own doc comment says `.toolbarRole(.editor)` "is what strips the inherited parent
back-title down to a bare chevron." **Confirmed in code:** `.toolbarRole(.editor)` appears *only in that
comment* — the function body applies just `.navigationBarTitleDisplayMode(.inline)` + `.navigationTitle`. So
the documented mechanism is absent and every pushed screen falls back to iOS's default back button (which
shows "Back", or a parent screen's title, next to the chevron — not the intended bare "‹").

I could not screenshot the rendered label this session (see Verification below), so severity is 🟡 pending a
device glance — but it affects **every drilled-in screen**, so it's worth 30 seconds of eyes before launch.
**To see it:** Home → Fan Zone → any game (e.g. Bracket Battle), or Teams → Competitions, and look at the
top-left — bare chevron vs chevron+word.

---

# Mechanical vs structural — how to triage

**Mechanical (safe, fast, mostly find-and-replace) — the ⚪ bulk:**
- Raw `.font(.system(...))` → `.dsFont(...)` (~17 product sites).
- Literal `cornerRadius:`/`RoundedRectangle(cornerRadius:)` → `DS.radius*` (~123 sites, most already equal a
  token value).
- Literal `.padding(...)`/`spacing:` → `DS.space*` (~900 sites — the largest volume, lowest individual
  impact; convert opportunistically, not as a blocking task).
- Raw `.foregroundStyle(.secondary)` → `Color.dsFgSecondary`.

**Structural (real decisions, do deliberately) — the 🟡/🔴:**
- Remove the release debug screen (🔴, trivial + mandatory).
- Decide the onboarding "COMING SOON" teaser: cut it or ship the feature (🔴).
- Fix the white-on-amber contrast (🔴 — swap to a legible on-color pair).
- Extract the four missing seams: `RetryStateView`, `DSButton`, one team-color resolver, one brand-color
  table (X-cut #1–#7 collapse into these).
- Reskin the UIKit-grouped Fan-Zone screens onto DS tokens (largest surface; also removes the
  dependence-on-one-line dark-mode risk).
- Migrate `PlayerDetailView` to `dsFont`/tokens; delete the two dead components.
- Decide the back-button treatment (implement the bare chevron, or accept the iOS default).

None of the mechanical work blocks launch. The three 🔴s and the back-button glance are the only
launch-gating items; everything else is quality you can stage into fast-follows.

---

# Verification notes (honest limits)

- **Code findings:** every finding resolves to a real `file:line`; the headline items (debug-ships,
  COMING SOON, back-button mechanism, palette divergences, dead components) were confirmed by direct reads,
  not inferred.
- **Screenshots:** the app built + installed clean (Debug, iPhone 17 sim). In-sim capture was **limited by
  two tooling blockers**, so this pass is code-first with partial visual confirmation:
  1. No HID tap path this session (`idb` client absent; cliclick needs a visible window under Xcode 27's
     Device Hub), so I couldn't navigate multi-tap flows.
  2. A persistent simulator **"Apple Account Verification"** system dialog overlays center-screen on every
     launch and can't be dismissed without HID, and `-resetOnboarding` + cfprefsd caching pinned the sim on
     the onboarding picker. Confirmed visually: **onboarding's system-List look + accent-outline CTA**
     (appendix shot 02).
- **Items that specifically want device eyes before launch:** the back-button label; the white-on-amber CTA
  contrast; the picker sheets staying dark; the 7pt Last-5 form badges; the divergent NEWS-pill greens and
  ESPN broadcast reds; the `tertiarySystemFill` substitute chip vs its card.

*Appendix screenshots saved to the session scratchpad: `shot_01_launch.png` (NotificationAuthPrompt sheet,
renders dark), `shot_02_onboarding.png` (system-List onboarding + outline CTA).*
