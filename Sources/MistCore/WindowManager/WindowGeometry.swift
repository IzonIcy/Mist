import Foundation
import CoreGraphics

/// Pure coordinate conversions between the two spaces Mist and the AX API use.
///
/// The layout engine works in **top-left-origin** display coordinates (y grows
/// downward). The Accessibility API's position attribute is also top-left-origin
/// but measured in *global* desktop space, where `y = 0` is the top edge of the
/// primary display. This is the classic footgun, so the arithmetic lives here as
/// a single, pure, testable unit instead of being scattered in AX code.
public enum WindowGeometry {
    /// Converts a `CGRect` given in our top-left-origin space (within the display
    /// whose top-left is at `origin`, also top-left space) into the equivalent
    /// rect in global AX coordinates.
    ///
    /// - Parameters:
    ///   - originY: the global Y (top-left) of the display that `rect` is local to.
    /// - Returns: the same rect, shifted into global AX space. X is unchanged;
    ///   Y shifts so the window keeps its distance-from-top identity.
    public static func global(_ rect: CGRect, displayTop originY: CGFloat) -> CGRect {
        CGRect(origin: CGPoint(x: rect.minX, y: rect.minY + originY),
               size: rect.size)
    }

    /// Inverts a bottom-left-origin `NSScreen`-style frame (y grows upward) into
    /// a top-left-origin frame (y grows downward) for the tiler.
    ///
    /// `screenHeight` is the height of the display in points. The returned rect
    /// keeps the same x; the y is flipped so the visual (non-resized) geometry is
    /// preserved.
    public static func flipped(_ bottomLeft: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(x: bottomLeft.minX,
               y: screenHeight - bottomLeft.minY - bottomLeft.height,
               width: bottomLeft.width,
               height: bottomLeft.height)
    }
}