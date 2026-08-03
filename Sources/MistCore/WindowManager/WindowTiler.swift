import Foundation
import CoreGraphics

/// A requested frame for one window, produced by the tiler.
///
/// The frame is in **top-left-origin display coordinates** (the same convention
/// the `Display` model and every `Layout` returns). Converting to the
/// Accessibility API's own coordinate space happens later in the AX layer — never
/// here — so this module stays pure and testable.
public typealias WindowPlan = [String: CGRect]

/// Computes the layout plan for a set of windows on a display.
///
/// This is the pure glue between the pieces that already exist: it takes the
/// windows on a display, filters the ones the current layout should arrange
/// (i.e. not floating), and asks the appropriate `Layout` for one frame each.
///
/// It has **no** side effects and touches no AX/UI state, so it is the one part
/// of the wiring we can verify headlessly. Frames come back keyed by window id,
/// exactly matching how `WindowManager` addresses windows.
public struct WindowTiler {
    public let display: CGRect
    public let layout: any Layout
    public let config: LayoutConfig

    public init(display: CGRect, layout: any Layout, config: LayoutConfig) {
        self.display = display
        self.layout = layout
        self.config = config
    }

    /// Builds the frame plan for the given windows.
    ///
    /// Windows marked `isFloating` are left where they are: the tiler returns no
    /// frame for them, and the caller simply doesn't touch them. Only tiled
    /// windows get a frame.
    public func plan(for windows: [Window]) -> WindowPlan {
        let tiled = windows.filter { !$0.isFloating }

        // Layout engine operates on `LayoutItemID`, so translate ids. Empty
        // result or empty input both produce `[]`; the engine handles 0/n windows
        // gracefully.
        let items = tiled.map { LayoutItem(id: LayoutItemID($0.id)) }
        let frames = layout.arrange(items: items, in: display, config: config)

        return Dictionary(uniqueKeysWithValues: frames.map { ($0.key.rawValue, $0.value) })
    }
}