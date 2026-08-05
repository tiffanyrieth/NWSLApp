---
paths:
  - "**/*SyncCoordinator.swift"
  - "**/*SyncService.swift"
---

# ⚠️ Per-user sync (follows / alerts / progress) — direction matters (read the doc first)

**STOP. Read `docs/data-sync.md` before you change any sync direction.** Each datum syncs a SPECIFIC
direction, and getting it wrong has caused real data-loss bugs ("only the oldest follow survives"). The
device is the source of truth for follows; Supabase is bookkeeping the user never hears about.

## Source-of-truth doc:

- **`docs/data-sync.md`** — the per-datum direction table (what restores, what's upward-only, and why).

## The laws that bite:

- **Follows sync = UPWARD-ONLY.** The DEVICE is authoritative. Signing in NEVER rewrites follows, completes
  onboarding, or changes what's on screen — **there is no restore-down**. Pure/tested rule
  (`FollowSyncCoordinator.resolveFollowOps`): **adds always; deletes only once `hasOnboarded`** (a half-filled
  onboarding picker must never look authoritative).
- **THE RESTORE LINE (settled owner ruling — see `docs/decisions.md`): detailed PREFERENCES may restore, the
  generic "who do I follow" may NOT.** So the nine alert TYPES (`notification_preferences`) restore verbatim
  but land INERT (apply to nothing until a bell is tapped); per-team/NT **BELLS do NOT restore** — a reinstall
  is a clean slate. `TeamAlertSyncCoordinator` is UPWARD-ONLY (prune gated on `hasOnboarded`).
- **Game PROGRESS restores** (`fanzone_progress`, keyed `user_id` never `device_id`).
- **Grants gotcha:** a new per-user table needs `grant … to authenticated` (RLS ≠ privilege, else silent
  `42501`); any table a Worker reads/writes as `service_role` needs an explicit `grant … to service_role`
  matching the operation (a `select`-only grant strands a coordinator that also DELETEs).

State that you read the doc when you touch this.
