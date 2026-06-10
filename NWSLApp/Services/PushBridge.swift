//
//  PushBridge.swift
//  NWSLApp
//
//  The one bridge between UIKit's AppDelegate (where APNs callbacks land) and the
//  SwiftUI/@Observable world (where coordinators and the router live). APNs
//  registration and notification taps are delivered to the UIApplicationDelegate,
//  which SwiftUI creates via @UIApplicationDelegateAdaptor and which we can't hand
//  our injected stores to. So the delegate writes here, and the observable side
//  reads here.
//
//  A `shared` singleton is the deliberate exception to the app's
//  inject-everything rule: there is exactly one app delegate and one APNs
//  registration, and the delegate has no access to the environment. Everything
//  else (auth, prefs, the sync coordinator) stays injected; this holds only the
//  two facts the delegate must surface.
//
//  `@MainActor` because the values feed SwiftUI-observed UI (the router) and a
//  main-actor coordinator; @Observable so reads via withObservationTracking /
//  `.onChange` re-fire when the delegate updates them.
//

import Foundation
import Observation

@MainActor
@Observable
final class PushBridge {
    static let shared = PushBridge()
    private init() {}

    /// The APNs device token (hex string), set by AppDelegate once iOS registers
    /// this device. Observed by NotificationSyncCoordinator, which uploads it to
    /// the `device_tokens` table once a user is signed in. Nil until registered
    /// (it never registers in the Simulator — APNs needs a real device).
    private(set) var deviceToken: String?

    /// The `eventID` carried by a tapped live push (goal/kickoff/…), set by
    /// AppDelegate's tap handler. Observed by RootTabView to route into the match.
    /// Cleared by the consumer after it routes.
    var tappedEventID: String?

    func didRegister(token: String) { deviceToken = token }

    func didTapNotification(eventID: String) { tappedEventID = eventID }
}
