import Foundation
import CoreGraphics

/// Supplies the frame the tiler should target, so the coordinator (pure
/// Foundation) doesn't touch AppKit.
public protocol DisplayFrameProviding {
    /// The display we tile onto, in top-left-origin AX coordinates. Nil when no
    /// display is available.
    var displayFrame: CGRect? { get }
}

/// `DisplayFrameProviding` backed by the Core Graphics display API.
///
/// Targets the main display and returns its frame in the **top-left-origin**
/// space the layout engine and AX both use. Using `CGDisplayBounds` (rather than
/// `NSScreen`) keeps this free of AppKit and `@MainActor` isolation, so it can be
/// exercised from any thread. Multi-display targeting (the screen under the
/// focused window) is a later step; tiling the main display first is the correct
/// default.
public final class CGDisplayFrameProvider: DisplayFrameProviding {
    public init() {}

    public var displayFrame: CGRect? {
        let id = CGMainDisplayID()
        guard id != 0 else { return nil }
        let bounds = CGDisplayBounds(id) // bottom-left origin
        return WindowGeometry.flipped(bounds, screenHeight: bounds.height)
    }
}