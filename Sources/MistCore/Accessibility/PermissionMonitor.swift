import Foundation
import Combine

/// Watches the accessibility permission and publishes an `Event` when it changes.
///
/// A periodic re-check (`AXIsProcessTrusted` is extremely cheap) catches both the
/// routine grant and the "revoked while running" case. When the permission
/// disappears, the monitor flips state and publishes an event; every dependent
/// module should treat it as "stop touching AX", not crash.
public final class AccessibilityMonitor: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case granted
        case missing
    }

    private let trust: any AccessibilityTrustChecking
    private let eventBus: EventPublishing
    private let lock = NSLock()

    private var state: State
    private var timer: Timer?
    private var started = false

    /// Poll interval (seconds). `AXIsProcessTrusted` is cheap, so a modest
    /// interval is fine; this is not a busy loop.
    public let pollInterval: TimeInterval

    public init(trust: any AccessibilityTrustChecking,
                eventBus: EventPublishing,
                pollInterval: TimeInterval = 3.0) {
        self.trust = trust
        self.eventBus = eventBus
        self.pollInterval = pollInterval
        self.state = trust.isTrusted ? .granted : .missing
    }

    /// Current permission state.
    public var isGranted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state == .granted
    }

    /// Begins watching. Safe to call once at boot.
    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.recheck()
        }
        // Timer retains its block, so keep a strong handle to cancel on stop.
        self.timer = timer
        // We must not hold the lock across the callback; recheck guards itself.
    }

    /// Stops watching (e.g. app termination).
    public func stop() {
        lock.lock()
        timer?.invalidate()
        timer = nil
        started = false
        lock.unlock()
    }

    private func recheck() {
        let latest: State = trust.isTrusted ? .granted : .missing

        lock.lock()
        let changed = latest != state
        state = latest
        lock.unlock()

        guard changed else { return }
        eventBus.publish(.accessibilityPermissionChanged(isGranted: latest == .granted))
    }
}