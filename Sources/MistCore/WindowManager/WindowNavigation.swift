import Foundation
import CoreGraphics

/// Direction keys for focus navigation.
public enum FocusDirection: Sendable {
    case left, right, up, down
}

/// Picks the window to focus when moving `direction` from `current`.
///
/// Pure and testable by design: it only sees frames. A neighbor must share a
/// span perpendicular to the movement (a "left" neighbor overlaps vertically),
/// otherwise diagonal windows would win; among candidates the closest edge
/// distance wins.
public enum WindowNavigation {
    public static func nextWindow(from currentID: String?, in windows: [Window], direction: FocusDirection) -> Window? {
        guard let current = windows.first(where: { $0.id == currentID }) else {
            // No known anchor: fall back to the topmost other window.
            return windows.last
        }

        var best: (window: Window, distance: CGFloat)?
        for candidate in windows where candidate.id != current.id {
            guard let distance = directionalDistance(from: current.frame, to: candidate.frame, direction: direction) else {
                continue
            }
            if best == nil || distance < best!.distance {
                best = (candidate, distance)
            }
        }
        return best?.window
    }

    /// Edge distance from `from` toward `to`, or nil when `to` isn't in that
    /// direction or doesn't overlap perpendicular to the movement.
    private static func directionalDistance(from: CGRect, to: CGRect, direction: FocusDirection) -> CGFloat? {
        switch direction {
        case .left:
            guard overlaps(from.minY, from.maxY, to.maxY, to.minY), to.midX < from.midX else { return nil }
            return max(0, from.minX - to.maxX)
        case .right:
            guard overlaps(from.minY, from.maxY, to.maxY, to.minY), to.midX > from.midX else { return nil }
            return max(0, to.minX - from.maxX)
        case .up:
            // Top-left origin: smaller y is higher.
            guard overlaps(from.minX, from.maxX, to.maxX, to.minX), to.midY < from.midY else { return nil }
            return max(0, from.minY - to.maxY)
        case .down:
            guard overlaps(from.minX, from.maxX, to.maxX, to.minX), to.midY > from.midY else { return nil }
            return max(0, to.minY - from.maxY)
        }
    }

    /// Whether two 1-D spans overlap at all.
    private static func overlaps(_ aMin: CGFloat, _ aMax: CGFloat, _ bMax: CGFloat, _ bMin: CGFloat) -> Bool {
        min(aMax, bMax) > max(aMin, bMin)
    }
}
