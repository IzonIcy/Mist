import Foundation
import CoreGraphics

/// Binary Space Partitioning layout.
///
/// Windows are recursively divided: the container splits roughly in half, then
/// each half splits again in the *other* axis at the next level. Interleaving the
/// split axis is why this is called BSP — it's the classic recursive bisection
/// that keeps windows near-equal in area while giving each its own slot.
///
/// - 1 window: fills the rect.
/// - N windows: the current region splits across one axis, and each subtree
///   continues independently until it holds a single window.
public struct BSPLayout: Layout {
    public let layoutName: LayoutName

    public init(layoutName: LayoutName = .bsp) {
        self.layoutName = layoutName
    }

    public func arrange(items: [LayoutItem], in rect: CGRect, config: LayoutConfig) -> LayoutResult {
        // Shrink once for the outer gap, then again by half a gap so that every
        // leaf, when it finally insets by halfGap, lands flush to neighbours.
        let half = config.gap / 2
        let usable = rect.insetBy(dx: config.outerGap + half, dy: config.outerGap + half)
        var result: LayoutResult = [:]
        place(items, in: usable, axis: .vertical, gap: half, into: &result)
        return result
    }

    private func place(_ items: [LayoutItem],
                       in rect: CGRect,
                       axis: Axis,
                       gap: CGFloat,
                       into result: inout LayoutResult) {
        guard !items.isEmpty else { return }
        if items.count == 1 {
            result[items[0].id] = rect.insetBy(dx: gap, dy: gap).standardized
            return
        }

        let (a, b) = splitRect(rect, fraction: 0.5, splitting: axis)
        // Recompute the two halves so the shared boundary earns a half-gap each
        // side; leaves are inset (dx, dy) on the way out so siblings never touch.
        let aRect: CGRect
        let bRect: CGRect
        if axis == .vertical { // a is the top half, b the bottom
            let boundary = a.midY
            aRect = CGRect(x: a.minX, y: a.minY, width: a.width, height: boundary - a.minY - gap)
            bRect = CGRect(x: b.minX, y: boundary + gap, width: b.width, height: b.maxY - boundary - gap)
        } else { // a is the left half, b the right
            let boundary = a.midX
            aRect = CGRect(x: a.minX, y: a.minY, width: boundary - a.minX - gap, height: a.height)
            bRect = CGRect(x: boundary + gap, y: b.minY, width: b.maxX - boundary - gap, height: b.height)
        }

        let split = items.count / 2
        place(Array(items[..<split]), in: aRect, axis: other(axis), gap: 0, into: &result)
        place(Array(items[split...]), in: bRect, axis: other(axis), gap: 0, into: &result)
    }

    private func other(_ axis: Axis) -> Axis {
        axis == .vertical ? .horizontal : .vertical
    }
}