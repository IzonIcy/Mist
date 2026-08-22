import CoreGraphics
import Testing
@testable import MistCore

struct WindowMake {
    static func window(
        _ id: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat = 100,
        height: CGFloat = 100
    ) -> Window {
        Window(
            id: id,
            displayIdentifier: "1",
            appName: "App",
            title: id,
            bundleID: "com.app",
            frame: CGRect(x: x, y: y, width: width, height: height)
        )
    }
}

@Suite struct FocusFollowsMouseWindowAtTests {
    let windows = [
        WindowMake.window("left", x: 0, y: 0),
        WindowMake.window("right", x: 100, y: 0),
    ]

    @Test func findsWindowContainingPoint() {
        let hit = FocusFollowsMouse.window(at: CGPoint(x: 50, y: 50), in: windows)
        #expect(hit?.id == "left")
    }

    @Test func prefersLaterZOrderOnOverlap() {
        let overlapping = windows + [WindowMake.window("overlay", x: 0, y: 0)]
        let hit = FocusFollowsMouse.window(at: CGPoint(x: 10, y: 10), in: overlapping)
        #expect(hit?.id == "overlay")
    }

    @Test func returnsNilOutsideAllWindows() {
        #expect(FocusFollowsMouse.window(at: CGPoint(x: 500, y: 500), in: windows) == nil)
    }
}

@Suite struct FocusFollowsMouseShouldFocusTests {
    private let now = ContinuousClock.now

    @Test func ignoresNilCandidate() {
        #expect(
            FocusFollowsMouse.shouldFocus(
                candidateID: nil, currentlyFocusedID: nil,
                lastFocusedAt: nil, now: now
            ) == false
        )
    }

    @Test func skipsAlreadyFocusedWindow() {
        #expect(
            FocusFollowsMouse.shouldFocus(
                candidateID: "a", currentlyFocusedID: "a",
                lastFocusedAt: nil, now: now
            ) == false
        )
    }

    @Test func rateLimitsRapidMoves() {
        #expect(
            FocusFollowsMouse.shouldFocus(
                candidateID: "b", currentlyFocusedID: "a",
                lastFocusedAt: now, now: now + .milliseconds(50)
            ) == false
        )
    }

    @Test func allowsFocusAfterIntervalAndDifferentTarget() {
        #expect(
            FocusFollowsMouse.shouldFocus(
                candidateID: "b", currentlyFocusedID: "a",
                lastFocusedAt: now, now: now + .milliseconds(200)
            ) == true
        )
    }

    @Test func allowsFirstEverFocus() {
        #expect(
            FocusFollowsMouse.shouldFocus(
                candidateID: "a", currentlyFocusedID: nil,
                lastFocusedAt: nil, now: now
            ) == true
        )
    }
}
