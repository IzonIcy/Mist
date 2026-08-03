import Foundation
import CoreGraphics

/// Stable identifier for the thing a layout is arranging (a window's handle).
public struct LayoutItemID: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// A window the layout engine is asked to place.
public struct LayoutItem: Equatable, Sendable {
    public let id: LayoutItemID
    /// The smallest usable size, used by BSP/stack as a split stop condition.
    public let minimumSize: CGSize

    public init(id: LayoutItemID, minimumSize: CGSize = CGSize(width: 200, height: 120)) {
        self.id = id
        self.minimumSize = minimumSize
    }
}

/// Spacing configuration the layouts honor. Kept as a small value type so the
/// engine never reaches into global state for numbers.
public struct LayoutConfig: Equatable, Sendable {
    /// Gap between adjacent windows.
    public var gap: CGFloat
    /// Gap between the layout and the screen edges.
    public var outerGap: CGFloat

    public init(gap: CGFloat = 8, outerGap: CGFloat = 16) {
        self.gap = gap
        self.outerGap = outerGap
    }
}

/// The output of an arrangement: one frame per placed window.
public typealias LayoutResult = [LayoutItemID: CGRect]

/// The single seam every layout must implement.
///
/// A layout is a **pure function**: same items, rect, and config in → same frames
/// out. No side effects, no access to the window manager, no notion of focus or
/// the active screen beyond the `rect` argument. That purity is what makes the
/// whole engine unit-testable and what makes a future pluggable-layout system
/// trivial: a plugin is just a new `Layout` conformance.
public protocol Layout: Sendable {
    /// Identifies the layout in config and logs.
    var layoutName: LayoutName { get }

    /// Produces a frame for every item in `items` inside `rect`, honoring
    /// `config`'s spacing.
    func arrange(items: [LayoutItem], in rect: CGRect, config: LayoutConfig) -> LayoutResult
}

/// Returns the inner layout rect after applying the outer gap, clamped to be
/// valid (never inverted).
public func insetRect(_ rect: CGRect, by outerGap: CGFloat) -> CGRect {
    rect.insetBy(dx: outerGap, dy: outerGap).standardized
}

/// Splits `rect` into a primary/secondary rect about `fraction` across `axis`.
///
/// Used by BSP. Returns two rects that tile the input exactly (the sum of their
/// interiours equals `rect`, modulo integral rounding).
func splitRect(_ rect: CGRect, fraction: CGFloat, splitting axis: Axis) -> (CGRect, CGRect) {
    var first = rect
    var second = rect
    switch axis {
    case .vertical: // stack windows one above another
        let height = rect.height * fraction
        first.size.height = height
        second.size.height = rect.height - height
        second.origin.y += height
    case .horizontal: // arrange windows side by side
        let width = rect.width * fraction
        first.size.width = width
        second.size.width = rect.width - width
        second.origin.x += width
    }
    return (first, second)
}

/// Which dimension a tiling split acts along.
public enum Axis: Sendable {
    /// Splits into left/right columns.
    case vertical
    /// Splits into top/bottom rows.
    case horizontal
}