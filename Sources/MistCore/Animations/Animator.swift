import Foundation
import AppKit

/// Timing/curve family for layout animations, as named in config.
///
/// These map to `CAMediaTimingFunction`/`NSAnimationContext` primitives. This is
/// the only place the animation *policy* lives; the animate/no-animate decision
/// is factored by `AnimationDirector`.
public enum AnimationSpeed: String, CaseIterable, Sendable {
    case spring
    case ease
    case instant

    /// The `CAMediaTimingFunction` curve this maps to. `spring` is a cubic-bezier
    /// approximation of a spring; `ease` is the system ease-in-out; `instant`
    /// is linear (used when animations are disabled).
    public var timingFunction: CAMediaTimingFunction {
        switch self {
        case .spring: return CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
        case .ease: return CAMediaTimingFunction(name: .easeInEaseOut)
        case .instant: return CAMediaTimingFunction(name: .linear)
        }
    }

    /// The `NSAnimationContext` duration (seconds). Zero disables the animation.
    public var duration: TimeInterval {
        switch self {
        case .spring: return 0.28
        case .ease: return 0.2
        case .instant: return 0
        }
    }
}

/// Coordinates whether animations run at all.
///
/// Animations are *optional* (charter) and must respect the system Reduce Motion
/// preference. This type centralizes that on/off decision so a caller never
/// hard-codes "animate everything" or "never animate".
public struct MoveDirector {
    /// Defaults to the system reduce-motion setting; overridable for tests.
    public var prefersReducedMotion: Bool

    public init(prefersReducedMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        self.prefersReducedMotion = prefersReducedMotion
    }

    /// Effective duration for a config `AnimationSpeed` given reduce-motion state.
    public func duration(for style: AnimationSpeed) -> TimeInterval {
        guard !prefersReducedMotion else { return 0 }
        return style.duration
    }

    /// Whether to animate at all for a given config setting.
    public func shouldAnimate(enabled: Bool, style: AnimationSpeed) -> Bool {
        enabled && !prefersReducedMotion && duration(for: style) > 0
    }
}