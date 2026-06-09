//
//  SupabaseManager.swift
//  NWSLApp
//
//  One source of truth for the shared Supabase client — the per-user backend
//  (Postgres + Apple auth + Row-Level Security) that arrived in V2 (0.2.x).
//  Mirrors how AppConfig centralizes base URLs: everything that talks to
//  Supabase (AuthStore, FollowSyncService) reads `SupabaseManager.client`
//  rather than constructing its own.
//
//  A `static let` on an enum gives a single, lazily-created, thread-safe
//  instance for free — created on first access, never duplicated. The Supabase
//  SDK persists the auth session to the keychain itself, so there's no custom
//  token storage to manage here.
//
//  Credentials come from the gitignored `Secrets` (see Secrets.example). The
//  anon key is a public client key; Row-Level Security is the real boundary.
//

import Foundation
import Supabase

enum SupabaseManager {
    /// The app-wide Supabase client. Force-unwrap is safe: `Secrets.supabaseURL`
    /// is a compile-time constant valid URL — an invalid one crashes on first
    /// access in dev, the right time to catch a bad paste.
    static let client = SupabaseClient(
        supabaseURL: URL(string: Secrets.supabaseURL)!,
        supabaseKey: Secrets.supabaseAnonKey
    )
}
