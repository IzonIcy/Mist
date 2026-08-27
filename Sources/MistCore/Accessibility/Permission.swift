import Foundation
@preconcurrency import ApplicationServices

/// The lifecycle of the accessibility permission.
///
/// Toggling the permission in System Settings makes the current *process* stale:
/// `AXIsProcessTrusted` stops reflecting reality until relaunch. The enum encodes
/// the states Mist can actually be in so the app can detect the permission
/// vanishing and *recover* instead of crashing (charter: "gracefully recover
/// when permissions disappear").
public enum AccessibilityPermission: Equatable, Sendable {
    /// App can read/write other apps' accessibility elements.
    case granted
    /// App is trusted but the OS hasn't forwarded it yet (rare).
    case pending
    /// Permission is missing; guide the user to System Settings.
    case missing
}

/// Reads whether the process is trusted by the accessibility system.
///
/// Exposed as a tiny protocol so the rest of the app can depend on the *shape*
/// and swap a fake in tests without touching the AX API.
public protocol AccessibilityTrustChecking {
    /// True once the process is granted accessibility.
    var isTrusted: Bool { get }
    /// Prompts the OS to re-check (this shows the System Settings path).
    func requestPermission()
}

/// Default `AccessibilityTrustChecking` backed by the real AX APIs.
public struct SystemAccessibilityTrust: AccessibilityTrustChecking {
    // Swift 6 flags the AX global as shared mutable state; it's a constant
    // CFString key that never changes.
    private nonisolated(unsafe) static let promptKey: CFString = kAXTrustedCheckOptionPrompt.takeUnretainedValue()

    public init() {}

    public var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    public func requestPermission() {
        // The options-dict variant is what actually shows the System Settings
        // prompt; the plain call only queries and would leave a first-run
        // user staring at a silent app.
        let key = Self.promptKey as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

public extension AccessibilityPermission {
    /// Computes the current permission state from a trust checker.
    init(checker: any AccessibilityTrustChecking) {
        self = checker.isTrusted ? .granted : .missing
    }
}