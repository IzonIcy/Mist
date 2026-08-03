import Foundation
import CoreGraphics

/// The `WindowManager.Window` is the live model of one managed window.
///
/// It is deliberately a thin, app-agnostic projection of an accessibility
/// element. Direct `AXUIElement` manipulation lives in the Accessibility module;
/// this type is only the *facts* and the *operations the manager itself needs*.
public struct Window: Identifiable, Hashable, Sendable {
    public let id: String
    /// Display identifier the window currently lives on.
    public let displayIdentifier: String?
    public let appName: String
    public let title: String
    public let bundleID: String
    public var frame: CGRect
    /// Whether the window is floating (not placed by the layout engine).
    public var isFloating: Bool
    /// Whether the window is on top (Z-order) of other windows.
    public var isAlwaysOnTop: Bool

    public init(id: String,
                displayIdentifier: String?,
                appName: String,
                title: String,
                bundleID: String,
                frame: CGRect,
                isFloating: Bool = false,
                isAlwaysOnTop: Bool = false) {
        self.id = id
        self.displayIdentifier = displayIdentifier
        self.appName = appName
        self.title = title
        self.bundleID = bundleID
        self.frame = frame
        self.isFloating = isFloating
        self.isAlwaysOnTop = isAlwaysOnTop
    }

    /// The immutable snapshot the rules engine can consume.
    public var snapshot: WindowSnapshot {
        WindowSnapshot(appName: appName,
                       title: title,
                       bundleID: bundleID,
                       displayIdentifier: displayIdentifier)
    }
}

/// Notifies a listener whenever the live window set changes.
public protocol WindowObserving: AnyObject {
    /// Called when the set of known windows changed. `changed` lists windows
    /// that were added, removed, or moved across displays.
    func windowsDidChange(_ windows: [Window], changed: [Window])
}

/// Owns the current set of windows and the operations the manager exposes.
///
/// The manager is stateful (it holds the tracked windows) but the mutations that
/// matter — add/remove/move — are passed through an observer protocol so the
/// rest of the app can subscribe without owning the state.
public protocol WindowManaging: AnyObject {
    /// Current managed windows.
    var windows: [Window] { get }
    /// Replaces the window set wholesale (e.g. from a re-scan).
    func reconcile(with newWindows: [Window])
    /// Marks a window floating or not.
    func setFloating(_ floating: Bool, for windowID: String)
    /// Marks a window always-on-top or not.
    func setAlwaysOnTop(_ onTop: Bool, for windowID: String)
    /// Focuses a window.
    func focus(_ windowID: String)
}

/// Default in-memory `WindowManaging`.
///
/// This holds no `AXUIElement` or `CGWindow` handles; it is pure bookkeeping,
/// so it can be unit-tested and swapped for a fake without touching the
/// accessibility stack.
public final class WindowManager: WindowManaging {
    private let lock = NSLock()
    private var store: [String: Window] = [:]
    private var observers: [WindowObserving] = []

    /// Injectable focus side-effect. The app layer sets this to its AX-backed
    /// focus; defaults to nil (no-op) so the pure manager stays safe standalone.
    public var focusHandler: ((String) -> Void)?

    public init() {}

    public var windows: [Window] {
        lock.lock()
        defer { lock.unlock() }
        return Array(store.values)
    }

    public func reconcile(with newWindows: [Window]) {
        lock.lock()
        store = Dictionary(uniqueKeysWithValues: newWindows.map { ($0.id, $0) })
        lock.unlock()
        notifyChange(windows: newWindows)
    }

    public func setFloating(_ floating: Bool, for windowID: String) {
        update(windowID) { $0.isFloating = floating }
    }

    public func setAlwaysOnTop(_ onTop: Bool, for windowID: String) {
        update(windowID) { $0.isAlwaysOnTop = onTop }
    }

    public func focus(_ windowID: String) {
        // Bookkeeping can't focus (that's the AX layer's job), so it defers to an
        // injected handler the app layer sets in. Defaults to a no-op so callers
        // that only need the pure seam (e.g. tests) get a safe behavior.
        focusHandler?(windowID)
    }

    // MARK: observation

    public func addObserver(_ observer: WindowObserving) {
        lock.lock()
        observers.append(observer)
        // Replay current state so an observer doesn't sit in a stale "empty" state.
        let current = Array(store.values)
        lock.unlock()
        observer.windowsDidChange(current, changed: current)
    }

    // MARK: helpers

    private func update(_ windowID: String, _ mutate: (inout Window) -> Void) {
        lock.lock()
        guard var window = store[windowID] else {
            lock.unlock()
            return
        }
        mutate(&window)
        store[windowID] = window
        let changed = [window]
        lock.unlock()
        notifyChange(windows: changed)
    }

    private func notifyChange(windows newWindows: [Window]) {
        let snapshotObservers: [WindowObserving]
        lock.lock()
        snapshotObservers = observers
        lock.unlock()
        for observer in snapshotObservers {
            observer.windowsDidChange(windows, changed: newWindows)
        }
    }
}