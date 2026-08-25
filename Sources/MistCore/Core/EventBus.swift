import Foundation
import Combine

/// A typed, decoupled publish/subscribe bus.
///
/// The app is event-driven (charter: "avoid unnecessary polling"). Modules that
/// observe the outside world (the accessibility monitor, display monitor,
/// hotkey listener) push events here; modules that react subscribe here.
/// Nothing knows who is listening, and subscribers never block publishers
/// because Combine's `PassthroughSubject` delivers asynchronously under the
/// hood with any subscriber that uses `.receive(on:)` as it wishes.
///
/// `Event` is the closed set of events the system currently understands. If a
/// future feature needs a new event, add a case: the compiler then walks every
/// subscriber to handle it. That is the point of a closed enum: exhaustiveness.
public enum Event: Sendable {
    /// System finished booting (permissions verified, config loaded).
    case didFinishLaunching

    /// Accessibility permission status changed.
    case accessibilityPermissionChanged(isGranted: Bool)

    /// The set of known windows changed (added, removed, or reordered).
    case windowsDidChange

    /// Configuration was (re)loaded. `source` says whether it was the initial
    /// load or a hot reload while running.
    case configurationDidChange(source: ConfigurationSource)

    /// A workspace was switched to.
    case workspaceDidChange(id: String)

    /// Display layout changed (plug/unplug/resolution/move).
    case displayConfigurationDidChange

    /// A hotkey was pressed.
    case hotkeyTriggered(key: String)
}

/// Where a configuration load came from; used by subscribers that want to
/// rebuild vs. just refresh.
public enum ConfigurationSource: Sendable {
    case initial
    case hotReload
}

/// Provides `Event`-typed streams to every module.
public protocol EventPublishing: AnyObject {
    /// Publishes the given event to all subscribers.
    func publish(_ event: Event)

    /// The publisher every module subscribes through.
    var events: AnyPublisher<Event, Never> { get }
}

/// Default `EventPublishing` implementation backed by a `PassthroughSubject`.
///
/// It is a class (not a struct) because it is shared, and it is small: one
/// subject, two methods. It does not try to be a general-purpose bus; when a
/// specific module needs strongly-typed events *in addition* to the global
/// ones, it uses its own subject (see `WindowObserver`).
public final class EventBus: EventPublishing {
    private let subject = PassthroughSubject<Event, Never>()

    public init() {}

    public func publish(_ event: Event) {
        subject.send(event)
    }

    public var events: AnyPublisher<Event, Never> {
        subject.eraseToAnyPublisher()
    }
}