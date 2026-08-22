import Foundation
import CoreGraphics

/// Pure decision logic for focus-follows-mouse.
///
/// Kept free of AppKit/AX so it is trivially testable: given the cursor
/// position (top-left origin, CG coordinates) and the current window list,
/// decide which window should receive focus, if any.
public enum FocusFollowsMouse {

    /// Returns the id of the topmost window whose frame contains `point`,
    /// or nil when no managed window does.
    public static func window(at point: CGPoint, in windows: [Window]) -> Window? {
        // Later entries in the scan are higher in Z-order for overlapping
        // frames, so walk backwards and take the first hit.
        for window in windows.reversed() where window.frame.contains(point) {
            return window
        }
        return nil
    }

    /// Whether a mouse-move event at this moment should actually trigger a
    /// focus change. Suppresses refocusing the already-focused window and
    /// rate-limits AX churn from pointer jitter.
    public static func shouldFocus(
        candidateID: String?,
        currentlyFocusedID: String?,
        lastFocusedAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        minimumInterval: Duration = .milliseconds(150)
    ) -> Bool {
        guard let candidateID else { return false }
        if candidateID == currentlyFocusedID { return false }
        if let lastFocusedAt, now - lastFocusedAt < minimumInterval { return false }
        return true
    }
}
