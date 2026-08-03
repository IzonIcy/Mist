import Testing
import Foundation
import CoreGraphics
@testable import MistCore

/// Pure geometry conversions between the top-left-origin space the layout engine
/// and the Accessibility API's global coordinate space share.
struct WindowGeometryTests {

    @Test("flipped mirrors Y about the display's vertical midpoint")
    func flippedMirrorsY() {
        let src = CGRect(x: 10, y: 20, width: 400, height: 300)
        let height: CGFloat = 800
        let flipped = WindowGeometry.flipped(src, screenHeight: height)
        #expect(abs(flipped.minY - (height - src.maxY)) < 0.001)
    }

    @Test("flipped round-trips to the original frame")
    func flippedRoundTrips() {
        let src = CGRect(x: 10, y: 20, width: 400, height: 300)
        let height: CGFloat = 800
        let restored = WindowGeometry.flipped(WindowGeometry.flipped(src, screenHeight: height), screenHeight: height)
        #expect(abs(restored.minX - src.minX) < 0.001)
        #expect(abs(restored.minY - src.minY) < 0.001)
        #expect(abs(restored.width - src.width) < 0.001)
        #expect(abs(restored.height - src.height) < 0.001)
    }

    @Test("global shifts only the Y by the display top")
    func globalAddsDisplayTopToY() {
        let rect = WindowGeometry.global(CGRect(x: 5, y: 10, width: 100, height: 50), displayTop: 300)
        #expect(rect.minX == 5)
        #expect(rect.minY == 310)
        #expect(rect.size == CGSize(width: 100, height: 50))
    }
}