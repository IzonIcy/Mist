import Foundation

/// A named, user-switchable workspace.
///
/// A workspace is a *collection* of window ids plus the layout and display those
/// windows will live in. It does not own `Window` objects (the `WindowManager`
/// does), so moving a window between workspaces is just moving its id; the
/// source of truth stays single.
public struct Workspace: Identifiable, Equatable, Sendable {
    public let id: String
    /// Human label (e.g. "Main").
    public let name: String
    /// Which layout windows in this workspace tile with.
    public var layout: LayoutName
    /// The display this workspace is bound to, if any.
    public var displayID: String?
    /// Ordered window ids assigned to this workspace.
    public var windowIDs: [String]

    public init(id: String, name: String, layout: LayoutName = .bsp,
                displayID: String? = nil, windowIDs: [String] = []) {
        self.id = id
        self.name = name
        self.layout = layout
        self.displayID = displayID
        self.windowIDs = windowIDs
    }
}

/// Notifies a listener when the active workspace changes.
public protocol WorkspaceObserving: AnyObject {
    func activeWorkspaceDidChange(_ id: String)
}

/// Owns the set of workspaces and carries out the charter's workspace
/// operations: move windows, switch, remember layouts, and bind to displays.
public final class WorkspaceManager {
    /// Remembers each workspace's layout across switches (that's the point of a
    /// workspace: your layout comes back).
    private var store: [String: Workspace]
    /// The active workspace id.
    public private(set) var activeWorkspaceID: String?
    private let lock = NSLock()
    private var observers: [WorkspaceObserving] = []

    public init(initial: [Workspace] = []) {
        self.store = Dictionary(uniqueKeysWithValues: initial.map { ($0.id, $0) })
    }

    public var workspaces: [Workspace] {
        lock.lock()
        defer { lock.unlock() }
        return Array(store.values)
    }

    /// Adds a workspace, returning true if it was new.
    @discardableResult
    public func add(_ workspace: Workspace) -> Bool {
        lock.lock()
        let existed = store[workspace.id] != nil
        store[workspace.id] = workspace
        lock.unlock()
        return !existed
    }

    /// Moves window (by id) into `workspaceID`, removing it from any others.
    public func move(windowID: String, to workspaceID: String) {
        lock.lock()
        var target = store[workspaceID] ?? Workspace(id: workspaceID, name: workspaceID)
        if !target.windowIDs.contains(windowID) {
            target.windowIDs.append(windowID)
        }
        store[workspaceID] = target
        for (id, var ws) in store where id != workspaceID {
            ws.windowIDs.removeAll { $0 == windowID }
            store[id] = ws
        }
        lock.unlock()
    }

    /// Switches the active workspace and notifies observers.
    public func switchTo(_ workspaceID: String) {
        lock.lock()
        activeWorkspaceID = workspaceID
        let snapshot = observers
        lock.unlock()
        for observer in snapshot {
            observer.activeWorkspaceDidChange(workspaceID)
        }
    }

    public func workspace(id: String) -> Workspace? {
        lock.lock()
        defer { lock.unlock() }
        return store[id]
    }

    public func addObserver(_ observer: WorkspaceObserving) {
        lock.lock()
        observers.append(observer)
        let active = activeWorkspaceID
        lock.unlock()
        if let active {
            observer.activeWorkspaceDidChange(active)
        }
    }
}