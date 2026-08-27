import Testing
import CoreGraphics
@testable import MistCore

/// Coverage for directional focus navigation: side checks, perpendicular
/// overlap, and nearest-edge wins.
struct WindowNavigationTests {

    private func window(_ id: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Window {
        Window(id: id, displayIdentifier: nil, appName: "app", title: id, bundleID: "b", frame: CGRect(x: x, y: y, width: w, height: h))
    }

    @Test func picksLeftNeighbor() {
        let windows = [
            window("left", 0, 0, 400, 600),
            window("right", 400, 0, 400, 600),
        ]
        let next = WindowNavigation.nextWindow(from: "right", in: windows, direction: .left)
        #expect(next?.id == "left")
    }

    @Test func picksRightNeighbor() {
        let windows = [
            window("left", 0, 0, 400, 600),
            window("right", 400, 0, 400, 600),
        ]
        let next = WindowNavigation.nextWindow(from: "left", in: windows, direction: .right)
        #expect(next?.id == "right")
    }

    @Test func respectsVerticalDirection() {
        // Two stacked rows; from the bottom row, "up" must pick above.
        let windows = [
            window("top", 0, 0, 800, 300),
            window("bottom", 0, 300, 800, 300),
        ]
        #expect(WindowNavigation.nextWindow(from: "bottom", in: windows, direction: .up)?.id == "top")
        #expect(WindowNavigation.nextWindow(from: "top", in: windows, direction: .down)?.id == "bottom")
    }

    @Test func ignoresWindowsWithoutPerpendicularOverlap() {
        // Far-right column doesn't overlap vertically with the anchor,
        // so moving left from it must skip that column entirely.
        let anchor = window("anchor", 800, 500, 400, 100)
        let offColumn = window("offcolumn", 0, 0, 400, 200)
        let next = WindowNavigation.nextWindow(from: anchor.id, in: [anchor, offColumn], direction: .left)
        #expect(next == nil)
    }

    @Test func closestEdgeWinsAmongCandidates() {
        let current = window("current", 400, 0, 400, 600)
        let near = window("near", 350, 0, 50, 600)
        let far = window("far", 0, 0, 100, 600)
        // near's right edge touches current at x=400; far's right edge is at
        // x=100. The smaller gap wins.
        let next = WindowNavigation.nextWindow(from: "current", in: [current, far, near], direction: .left)
        #expect(next?.id == "near")
    }

    @Test func noAnchorFallsBackToTopmost() {
        let a = window("a", 0, 0, 100, 100)
        let b = window("b", 0, 100, 100, 100)
        let next = WindowNavigation.nextWindow(from: "missing", in: [a, b], direction: .down)
        #expect(next?.id == "b")
    }
}
