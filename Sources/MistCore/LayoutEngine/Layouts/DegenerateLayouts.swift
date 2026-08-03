import Foundation
import CoreGraphics

/// Stack layout: one "active" window dominates the remaining space while the
/// rest share the leftover strip.
///
/// The active window is convention-ally the **last** item in the array. The
/// window manager is responsible for ordering items so the focused window is
/// last; the layout itself stays pure.
public struct StackLayout: Layout {
    public let layoutName: LayoutName
    /// How much of the primary dimension the stack (non-active) region gets.
    private let stackRatio: CGFloat

    public init(layoutName: LayoutName = .stack, stackRatio: CGFloat = 0.4) {
        self.layoutName = layoutName
        self.stackRatio = stackRatio
    }

    public func arrange(items: [LayoutItem], in rect: CGRect, config: LayoutConfig) -> LayoutResult {
        let usable = insetRect(rect, by: config.outerGap)
        guard !items.isEmpty else { return [:] }

        var result: LayoutResult = [:]
        if items.count == 1 {
            result[items[0].id] = usable.standardized
            return result
        }

        let active = items[items.count - 1]
        let stack = Array(items.dropLast())

        // Active window claims the right region; the rest tile on the left.
        let gap = config.gap
        let activeFrame = CGRect(x: usable.minX + usable.width * stackRatio + gap,
                                 y: usable.minY,
                                 width: usable.width * (1 - stackRatio) - gap,
                                 height: usable.height).standardized

        // The rest tile into a vertical stack of equal rows on the left.
        if !stack.isEmpty {
            let inner = CGRect(x: usable.minX, y: usable.minY,
                               width: usable.width * stackRatio, height: usable.height).standardized
            let grid = GridLayout(layoutName: layoutName, direction: .horizontal)
            result.merge(grid.arrange(items: stack, in: inner, config: config)) { _, new in new }
        }
        result[active.id] = activeFrame
        return result
    }
}

/// Monocle layout: every window fills the whole rect (all overlap; the active
/// one is simply on top). The window manager picks which is shown.
public struct MonocleLayout: Layout {
    public let layoutName: LayoutName

    public init(layoutName: LayoutName = .monocle) {
        self.layoutName = layoutName
    }

    public func arrange(items: [LayoutItem], in rect: CGRect, config: LayoutConfig) -> LayoutResult {
        let usable = insetRect(rect, by: config.outerGap)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, usable.standardized) })
    }
}

/// Floating layout: a *no-op* arrangement.
///
/// Windows matched by "float" are not placed by the engine at all — the window
/// manager keeps their current sizes. `arrange` returning an empty result is the
/// honest contract: there is no frame to compute here, and forcing one would
/// violate the meaning of "floating". The manager treats an empty result as
/// "leave these windows alone".
public struct FloatingLayout: Layout {
    public let layoutName: LayoutName

    public init(layoutName: LayoutName = .floating) {
        self.layoutName = layoutName
    }

    public func arrange(items: [LayoutItem], in rect: CGRect, config: LayoutConfig) -> LayoutResult {
        [:]
    }
}