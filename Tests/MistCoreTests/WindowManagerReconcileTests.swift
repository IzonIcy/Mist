import Testing
import Foundation
@testable import MistCore

/// Regression tests for WindowManager reconcile behavior.
///
/// The fallback window ids derived from `appName-minX-minY` can collide when
/// two same-app windows share an origin; reconcile must dedupe instead of
/// trapping, and must expose a stable Z-order approximation for consumers
/// like focus-follows-mouse ("later entries = higher").
@Suite struct WindowManagerReconcileTests {
    private func window(_ id: String) -> Window {
        Window(id: id, displayIdentifier: nil, appName: "App", title: id, bundleID: "com.app", frame: .zero)
    }

    @Test func reconcileWithDuplicateIDsDoesNotTrap() {
        let manager = WindowManager()
        // Before the fix this crashed: Dictionary(uniqueKeysWithValues:)
        // traps on duplicate keys.
        manager.reconcile(with: [window("a"), window("a"), window("b")])
        #expect(manager.windows.count == 2)
        #expect(Set(manager.windows.map(\.id)) == ["a", "b"])
    }

    @Test func duplicateIDCollapsesToLastOccurrence() {
        let manager = WindowManager()
        let second = Window(id: "dup", displayIdentifier: nil, appName: "App", title: "newer", bundleID: "com.app", frame: .zero)
        manager.reconcile(with: [window("dup"), second])
        #expect(manager.windows.first { $0.id == "dup" }?.title == "newer")
    }

    @Test func survivingWindowsKeepRelativeOrder() {
        let manager = WindowManager()
        manager.reconcile(with: [window("a"), window("b"), window("c")])
        manager.reconcile(with: [window("c"), window("a")])
        #expect(manager.windows.map(\.id) == ["a", "c"])
    }

    @Test func newlySeenWindowsAppendOnTop() {
        let manager = WindowManager()
        manager.reconcile(with: [window("bottom"), window("top")])
        // Later entries are higher in Z-order per the FocusFollowsMouse contract.
        manager.reconcile(with: [window("bottom"), window("top"), window("fresh")])
        #expect(manager.windows.map(\.id) == ["bottom", "top", "fresh"])
        #expect(manager.windows.last?.id == "fresh")
    }
}
