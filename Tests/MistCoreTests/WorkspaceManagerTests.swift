import Testing
@testable import MistCore

struct WorkspaceManagerTests {

    @Test func unassignedWindowsStayVisibleWithoutAnActiveWorkspace() {
        let manager = WorkspaceManager()
        #expect(manager.windowIsVisible("w1"))
    }

    @Test func unclaimedWindowsStayVisibleInAnActiveWorkspace() {
        let manager = WorkspaceManager(initial: [Workspace(id: "main", name: "main")])
        manager.switchTo("main")
        // No rule ever assigned this window, so hiding it would make the config
        // without workspace rules behave differently.
        #expect(manager.windowIsVisible("stray"))
    }

    @Test func onlyTheActiveWorkspaceShowsItsWindows() {
        let manager = WorkspaceManager(
            initial: [
                Workspace(id: "main", name: "main", windowIDs: ["w1"]),
                Workspace(id: "chat", name: "chat", windowIDs: ["w2"]),
            ]
        )
        manager.switchTo("main")
        #expect(manager.windowIsVisible("w1"))
        #expect(!manager.windowIsVisible("w2"))

        manager.switchTo("chat")
        #expect(!manager.windowIsVisible("w1"))
        #expect(manager.windowIsVisible("w2"))
    }

    @Test func movingAWindowRemovesItFromTheOldWorkspace() {
        let manager = WorkspaceManager(
            initial: [
                Workspace(id: "main", name: "main", windowIDs: ["w1"]),
                Workspace(id: "chat", name: "chat"),
            ]
        )
        manager.move(windowID: "w1", to: "chat")
        #expect(manager.workspace(id: "main")?.windowIDs.isEmpty == true)
        #expect(manager.workspace(id: "chat")?.windowIDs == ["w1"])
    }
}
