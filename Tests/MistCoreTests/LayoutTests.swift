import Testing
import Foundation
import CoreGraphics
@testable import MistCore

/// Exercises the pure layout engine — the charter's "layout tests", the cheapest
/// regression net for the heart of the app.
struct LayoutTests {

    private let config = LayoutConfig(gap: 0, outerGap: 0)
    private let baseRect = CGRect(x: 0, y: 0, width: 400, height: 400)

    private func makeItems(_ count: Int) -> [LayoutItem] {
        (0..<count).map { LayoutItem(id: LayoutItemID("w\($0)")) }
    }

    @Test("A layout produces exactly one frame per item")
    func oneFramePerItem() {
        for count in 1...5 {
            let result = VerticalLayout().arrange(items: makeItems(count), in: baseRect, config: config)
            #expect(result.count == count, "expected \(count) frames for \(count) items")
        }
    }

    @Test("Vertical layout stacks full-width rows without overlap")
    func verticalStacksRows() {
        let result = VerticalLayout().arrange(items: makeItems(2), in: baseRect, config: config)
        #expect(result.count == 2)
        let frames = Array(result.values)
        #expect(frames[0].width == baseRect.width)
        #expect(abs(frames[0].width - baseRect.width) < 0.001)
        #expect(frames[0].intersects(frames[1]) == false)
    }

    @Test("Horizontal layout tiles columns edge-to-edge")
    func horizontalTilesColumns() {
        let result = HorizontalLayout().arrange(items: makeItems(3), in: baseRect, config: config)
        let frames = result.values.sorted { $0.minX < $1.minX }
        #expect(frames.count == 3)
        for index in 1..<3 {
            #expect(abs(frames[index].minX - frames[index - 1].maxX) < 0.0001)
        }
    }

    @Test("BSP with one window fills the rect")
    func bspSingleWindow() {
        let result = BSPLayout().arrange(items: makeItems(1), in: baseRect, config: config)
        #expect(result.first?.value == baseRect)
    }

    @Test("BSP partitions the rect without overlap")
    func bspCoversRect() {
        let result = BSPLayout().arrange(items: makeItems(4), in: baseRect, config: config)
        #expect(result.count == 4)
        let total = result.values.reduce(CGFloat.zero) { $0 + $1.width * $1.height }
        #expect(abs(total - baseRect.width * baseRect.height) < 0.001)
    }

    @Test("Monocle places every window in the same frame")
    func monocleOverlaps() {
        let result = MonocleLayout().arrange(items: makeItems(3), in: baseRect, config: config)
        let frames = Array(result.values)
        #expect(frames.count == 3)
        #expect(frames.dropFirst().allSatisfy { $0 == frames[0] })
    }

    @Test("Floating layout claims no managed frames")
    func floatingEmpty() {
        let result = FloatingLayout().arrange(items: makeItems(2), in: baseRect, config: config)
        #expect(result.isEmpty)
    }
}