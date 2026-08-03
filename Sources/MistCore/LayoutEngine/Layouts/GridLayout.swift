import Foundation
import CoreGraphics

/// A grid layout for `columns` side-by-side windows.
///
/// Shared implementation for the "rows" and "columns" tiling. Rather than two
/// nearly-identical files, one type takes five Axis-specific details: the
/// left/right pair (Vertical = columns, horizontal = rows) are expressed through
/// `direction`.
public struct GridLayout: Layout {
    public let layoutName: LayoutName
    /// `.vertical` stacks windows as columns left→right; `.horizontal` stacks
    /// them as rows top→bottom.
    private let direction: Axis

    public init(layoutName: LayoutName, direction: Axis) {
        self.layoutName = layoutName
        self.direction = direction
    }

    public func arrange(items: [LayoutItem], in rect: CGRect, config: LayoutConfig) -> LayoutResult {
        let usable = insetRect(rect, by: config.outerGap)
        let n = items.count
        guard n > 0 else { return [:] }

        // Apply inter-window gap: reserve (n-1)*gap across the primary dimension.
        let totalGap = config.gap * CGFloat(max(0, n - 1))

        var result: LayoutResult = [:]
        let step = direction == .vertical
            ? (usable.width - totalGap) / CGFloat(n)
            : (usable.height - totalGap) / CGFloat(n)

        for (index, item) in items.enumerated() {
            var frame = usable
            switch direction {
            case .vertical:
                frame.origin.x = usable.minX + (step + config.gap) * CGFloat(index)
                frame.size.width = step
            case .horizontal:
                frame.origin.y = usable.minY + (step + config.gap) * CGFloat(index)
                frame.size.height = step
            }
            result[item.id] = frame.standardized
        }
        return result
    }
}

/// Simple top-to-bottom rows (used by config layout `"vertical"`).
public struct VerticalLayout: Layout {
    public let layoutName: LayoutName
    private let grid: GridLayout

    public init(layoutName: LayoutName = .vertical) {
        self.layoutName = layoutName
        self.grid = GridLayout(layoutName: layoutName, direction: .horizontal)
    }

    public func arrange(items: [LayoutItem], in rect: CGRect, config: LayoutConfig) -> LayoutResult {
        grid.arrange(items: items, in: rect, config: config)
    }
}

/// Simple left-to-right columns (used by config layout `"horizontal"`).
public struct HorizontalLayout: Layout {
    public let layoutName: LayoutName
    private let grid: GridLayout

    public init(layoutName: LayoutName = .horizontal) {
        self.layoutName = layoutName
        self.grid = GridLayout(layoutName: layoutName, direction: .vertical)
    }

    public func arrange(items: [LayoutItem], in rect: CGRect, config: LayoutConfig) -> LayoutResult {
        grid.arrange(items: items, in: rect, config: config)
    }
}