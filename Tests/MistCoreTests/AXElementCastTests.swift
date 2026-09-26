import Testing
import Foundation
import ApplicationServices
@testable import MistCore

/// The accessibility API is dynamically typed. It hands back whatever the owning
/// app published for the attribute it was asked about, and nothing verifies it,
/// so reading one is an untyped downcast dressed up as a typed one.
///
/// A forced cast is a fatal error, not a nil, and Mist dying means window
/// management stops on the desktop until somebody relaunches it. The asymmetry
/// is the whole point: an app publishing something odd for an AX attribute
/// should cost one hotkey, not the process.
@Suite struct AXElementCastTests {
    @Test func aRealElementComesBack() {
        // Creating an element needs no Accessibility trust, so this runs
        // headlessly. Only *using* one does.
        let element = AXUIElementCreateSystemWide()
        #expect(asAXUIElement(element) != nil)
    }

    @Test func theSameElementComesBackAsTheSameElement() {
        // The cast has to preserve identity, not just pass the type check:
        // `discovery.windowID(for:)` compares by CFEqual.
        let element = AXUIElementCreateSystemWide()
        guard let cast = asAXUIElement(element) else {
            Issue.record("expected a real element to cast")
            return
        }
        #expect(CFEqual(cast, element))
    }

    @Test func aStringIsRejectedRatherThanTrapped() {
        let value = "not an element" as CFString
        #expect(asAXUIElement(value) == nil)
    }

    @Test func otherCoreFoundationTypesAreRejected() {
        // Anything an app might plausibly publish instead.
        #expect(asAXUIElement(42 as CFNumber) == nil)
        #expect(asAXUIElement([1, 2, 3] as CFArray) == nil)
        #expect(asAXUIElement(kCFBooleanTrue) == nil)
    }

    @Test func anAXValueIsNotAnElement() {
        // The two are both AX types and the codebase handles both, so it is worth
        // saying they are not interchangeable.
        var point = CGPoint.zero
        guard let value = AXValueCreate(.cgPoint, &point) else {
            Issue.record("could not build an AXValue")
            return
        }
        #expect(asAXUIElement(value) == nil)
    }
}
