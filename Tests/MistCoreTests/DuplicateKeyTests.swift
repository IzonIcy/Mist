import Testing
import Foundation
import CoreGraphics
@testable import MistCore

/// `Dictionary(uniqueKeysWithValues:)` traps on a duplicate key.
///
/// That is a crash with no useful stack trace, and every one of these sites
/// builds a dictionary keyed on an id that arrives from outside: a window id from
/// a scan, a display id from WindowServer, a layout item id derived from a window
/// id. "Shouldn't happen" is not a reason to abort the process — Mist dying means
/// window management stops on the desktop.
///
/// WindowManager already used `uniquingKeysWith`; these were the sites that did
/// not. The rule is now that an id collision collapses instead of trapping.
@Suite struct DuplicateKeyTests {
    private func display(_ id: String, x: CGFloat = 0) -> Display {
        Display(id: id, frame: CGRect(x: x, y: 0, width: 100, height: 100))
    }

    // MARK: the layout engine

    @Test func monocleWithDuplicateItemIDsDoesNotTrap() {
        // Every item gets the same frame, so the duplicate is harmless — the only
        // thing that matters is that building the result does not abort.
        let result = MonocleLayout().arrange(
            items: [LayoutItem(id: LayoutItemID("a")),
                    LayoutItem(id: LayoutItemID("a"))],
            in: CGRect(x: 0, y: 0, width: 800, height: 600),
            config: LayoutConfig()
        )
        #expect(result.count == 1)
        #expect(result[LayoutItemID("a")] != nil)
    }

    @Test func duplicateItemsKeepTheSameFrameEitherWay() {
        // The surviving frame is the same regardless of which item wins, so the
        // uniquing policy cannot be observed here.
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let result = MonocleLayout().arrange(
            items: [LayoutItem(id: LayoutItemID("a")), LayoutItem(id: LayoutItemID("a"))],
            in: rect,
            config: LayoutConfig(gap: 0, outerGap: 0)
        )
        #expect(result[LayoutItemID("a")] == insetRect(rect, by: 0).standardized)
    }

    // MARK: the window store

    @Test func aTilerHandledDuplicateWindowIDsDoesNotTrap() {
        // The shape that connects window ids to a layout: two scans yielding the
        // same id must not abort the pass.
        let tiler = WindowTiler(display: CGRect(x: 0, y: 0, width: 800, height: 600),
                                layout: MonocleLayout(),
                                config: LayoutConfig())
        let duplicate = Window(id: "a", displayIdentifier: nil, appName: "App", title: "a",
                               bundleID: "com.app", frame: .zero)
        #expect(tiler.plan(for: [duplicate, duplicate]).count == 1)
    }

    @Test func windowReconcileWithDuplicateIDsDoesNotTrap() {
        let manager = WindowManager()
        manager.reconcile(with: [
            Window(id: "a", displayIdentifier: nil, appName: "App", title: "one",
                   bundleID: "com.app", frame: .zero),
            Window(id: "a", displayIdentifier: nil, appName: "App", title: "two",
                   bundleID: "com.app", frame: .zero),
        ])
        #expect(manager.windows.count == 1)
        #expect(manager.windows.first?.title == "two")
    }

    // MARK: the stores

    @Test func displayReconcileWithDuplicateIDsDoesNotTrap() {
        let manager = DisplayManager()
        manager.reconcile([display("a", x: 0), display("a", x: 50), display("b")])
        #expect(manager.displays.count == 2)
        #expect(Set(manager.displays.map(\.id)) == ["a", "b"])
    }

    @Test func duplicateDisplayCollapsesToTheLastOne() {
        let manager = DisplayManager()
        manager.reconcile([display("a", x: 0), display("a", x: 500)])
        #expect(manager.displays.first?.frame.minX == 500)
    }

    @Test func workspaceInitWithDuplicateIDsDoesNotTrap() {
        let manager = WorkspaceManager(initial: [
            Workspace(id: "one", name: "first"),
            Workspace(id: "one", name: "second"),
            Workspace(id: "two", name: "other"),
        ])
        #expect(manager.workspaces.count == 2)
        #expect(manager.workspace(id: "one")?.name == "second")
    }

    // MARK: why the scan is the real fix

    /// The three dictionaries above are the detonation site, not the cause. A
    /// position-derived window id is both unstable and non-unique, so it fed them
    /// duplicates *and* churned ids every time the tiler moved a window. The scan
    /// no longer mints one, which is why these tests are about not trapping rather
    /// than about recovering a sensible id.
    @Test func windowIdsAreNoLongerDerivedFromPosition() {
        // A window that moves keeps its identity. Deriving it from the frame made
        // every move look like a close plus an open: focus loss, lost float
        // state, and a full retile.
        let manager = WindowManager()
        let start = CGRect(x: 0, y: 0, width: 400, height: 300)
        manager.reconcile(with: [Window(id: "1234-5678", displayIdentifier: nil, appName: "App",
                                  title: "a", bundleID: "com.app", frame: start)])
        manager.reconcile(with: [Window(id: "1234-5678", displayIdentifier: nil, appName: "App",
                                  title: "a", bundleID: "com.app",
                                  frame: CGRect(x: 900, y: 500, width: 400, height: 300))])
        #expect(manager.windows.count == 1)
        #expect(manager.windows.first?.frame.minX == 900)
    }

    @Test func twoWindowsAtTheSameOriginCanBothBeManaged() {
        // The collision the old fallback invited. With ids from WindowServer
        // rather than from geometry, same-origin windows are just two windows.
        let manager = WindowManager()
        let frame = CGRect(x: 100, y: 100, width: 300, height: 200)
        manager.reconcile(with: [
            Window(id: "1-100", displayIdentifier: nil, appName: "App", title: "left",
                   bundleID: "com.app", frame: frame),
            Window(id: "2-200", displayIdentifier: nil, appName: "App", title: "right",
                   bundleID: "com.app", frame: frame),
        ])
        #expect(manager.windows.count == 2)
    }
}
