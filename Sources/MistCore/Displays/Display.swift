import Foundation
import CoreGraphics
import Combine

/// A display (a "screen" in macOS terms) as Mist understands it.
public struct Display: Identifiable, Equatable, Sendable {
    /// Stable identifier (CGDirectDisplayID) as a string.
    public let id: String
    /// Bounds in points (already flipped to top-left-origin for the layout rect).
    public let frame: CGRect
    /// The workspace currently assigned to this display, if any.
    public var workspaceID: String?
}

/// Notifies on display configuration changes.
public protocol DisplayObserving: AnyObject {
    /// Called on plug/unplug/resolution/move. `current` is the full new set.
    func displaysDidChange(_ current: [Display])
}

/// Manages the set of connected displays.
///
/// The core responsibility here is mapping `CGDirectDisplayID` changes to a tidy
/// model and, crucially, surviving unplug/plug without losing window→workspace
/// associations (those live on the workspace side, keyed by the stable display
/// id, so they survive a transient disconnect).
public protocol DisplayManaging: AnyObject {
    /// Current displays.
    var displays: [Display] { get }
    /// Replaces the display set (from the CG monitor-config observer).
    func reconcile(_ displays: [Display])
    /// Looks up a display by its identifier.
    func display(id: String) -> Display?
}

/// Default in-memory `DisplayManaging`. Pure bookkeeping, unit-testable.
public final class DisplayManager: DisplayManaging {
    private let lock = NSLock()
    private var store: [String: Display] = [:]
    private var observers: [DisplayObserving] = []

    public init() {}

    public var displays: [Display] {
        lock.lock()
        defer { lock.unlock() }
        return Array(store.values).sorted { $0.frame.minX < $1.frame.minX }
    }

    public func reconcile(_ displays: [Display]) {
        lock.lock()
        store = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
        let snapshot = Array(store.values)
        lock.unlock()
        for observer in observers {
            observer.displaysDidChange(snapshot)
        }
    }

    public func display(id: String) -> Display? {
        lock.lock()
        defer { lock.unlock() }
        return store[id]
    }

    public func addObserver(_ observer: DisplayObserving) {
        lock.lock()
        observers.append(observer)
        let snapshot = Array(store.values)
        lock.unlock()
        observer.displaysDidChange(snapshot)
    }

    public func assign(workspace: String, to displayID: String) {
        lock.lock()
        guard var display = store[displayID] else {
            lock.unlock()
            return
        }
        display.workspaceID = workspace
        store[displayID] = display
        lock.unlock()
    }
}