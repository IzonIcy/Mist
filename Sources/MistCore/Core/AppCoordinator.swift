import Foundation
import Combine
import CoreGraphics

/// Glues the Core modules into a running system.
///
/// This is the only place that knows how the pieces fit together, so wiring a
/// change stays a single file. It is pure `MistCore` logic (no AppKit), which
/// keeps the app target a thin shell and lets this be reasoned about (and later
/// tested) in isolation.
public final class AppCoordinator {
    public let eventBus: EventPublishing
    private let logger: Logger
    private let configLoader: ConfigLoader

    private let windowManager = WindowManager()
    private let displayManager = DisplayManager()
    private let workspaceManager = WorkspaceManager()
    private var hotkeyManager: HotkeyManager?
    private var accessibilityMonitor: AccessibilityMonitor?

    // Accessibility stack. Discovered lazily so permission state and this wiring
    // stay coherent: discovery caches live AX elements, control applies them.
    private let trust: any AccessibilityTrustChecking
    private let discovery: AccessibilityWindowDiscovery
    private let windowControl: any WindowControling
    private let displayFrames: any DisplayFrameProviding

    private var currentConfig = MistConfig()
    private var hasAppliedConfig = false
    private var permissionGranted = false
    private var subscriptions: Set<AnyCancellable> = []
    private var lastMouseFocusAt: ContinuousClock.Instant?
    private var lastMouseFocusedWindowID: String?

    public init(eventBus: EventPublishing,
                logger: Logger = .shared,
                configLoader: ConfigLoader = ConfigLoader(),
                trust: any AccessibilityTrustChecking = SystemAccessibilityTrust(),
                displayFrames: any DisplayFrameProviding = CGDisplayFrameProvider()) {
        self.eventBus = eventBus
        self.logger = logger
        self.configLoader = configLoader
        self.trust = trust
        self.discovery = AccessibilityWindowDiscovery(trust: trust, logger: logger)
        self.windowControl = AccessibilityWindowControl(resolver: discovery, logger: logger)
        self.displayFrames = displayFrames
    }

    /// Brings the system up: load config, verify accessibility, start monitors,
    /// and wire events.
    public func bootstrap() {
        loadConfiguration()
        monitorAccessibility()
        wireEvents()
        if permissionGranted {
            refreshWindows() // already trusted (e.g. relaunch) → reconcile pro-actively
        }
        wireFocusSeam()
        logger.info("Mist booted")
        eventBus.publish(.didFinishLaunching)
    }

    public func shutdown() {
        accessibilityMonitor?.stop()
    }

    // MARK: configuration

    private func loadConfiguration() {
        do {
            let config: MistConfig
            if let url = configLoader.defaultConfigURL() {
                config = try configLoader.load(from: url)
            } else {
                config = .default
            }
            apply(config)
        } catch {
            // Bad/missing config must never crash launch, and a *failed
            // reload* must never wipe the user's settings. First load falls
            // back to defaults; afterwards we keep the last-good config.
            logger.error("Failed to load config: \(String(describing: error))")
            if !hasAppliedConfig {
                logger.error("No previous config available, using defaults")
                apply(.default)
            }
        }
    }

    private func apply(_ config: MistConfig) {
        currentConfig = config
        hasAppliedConfig = true
        let manager = HotkeyManager()
        do {
            try manager.setBindings(config.hotkeys)
            hotkeyManager = manager
        } catch {
            logger.error("Hotkey conflict detected: \(String(describing: error))")
        }
        eventBus.publish(.configurationDidChange(source: .initial))
    }

    // MARK: accessibility

    private func monitorAccessibility() {
        let monitor = AccessibilityMonitor(trust: trust, eventBus: eventBus)
        accessibilityMonitor = monitor
        monitor.start()
        permissionGranted = monitor.isGranted
    }

    private func wireFocusSeam() {
        // Bookkeeping-side focus forwards to the real AX focus.
        windowManager.focusHandler = { [weak self] windowID in
            self?.windowControl.focus(windowID: windowID)
        }
    }

    // MARK: focus-follows-mouse seam

    /// Whether the feature is switched on in config (the App layer checks
    /// this before installing its global event monitor).
    public var focusFollowsMouseEnabled: Bool {
        currentConfig.general.focusFollowsMouse
    }

    /// Focuses the managed window under `point` (top-left-origin CG coords),
    /// honoring the pure FocusFollowsMouse guards. Called by the App layer's
    /// global mouse monitor when the feature is enabled in config.
    public func focusWindow(at point: CGPoint) {
        guard currentConfig.general.focusFollowsMouse else { return }
        let windows = windowManager.windows
        let candidate = FocusFollowsMouse.window(at: point, in: windows)?.id
        let now = ContinuousClock.now
        guard FocusFollowsMouse.shouldFocus(
            candidateID: candidate,
            currentlyFocusedID: lastMouseFocusedWindowID,
            lastFocusedAt: lastMouseFocusAt,
            now: now
        ) else { return }

        lastMouseFocusAt = now
        if let candidate {
            lastMouseFocusedWindowID = candidate
            windowControl.focus(windowID: candidate)
        }
    }

    // MARK: event wiring

    private func wireEvents() {
        eventBus.events
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &subscriptions)
    }

    private func handle(_ event: Event) {
        switch event {
        case .didFinishLaunching:
            logger.info("Windows reconciled after launch")
        case .accessibilityPermissionChanged(let granted):
            logger.info("Accessibility permission \(granted ? "granted" : "revoked")")
            permissionGranted = granted
            if granted {
                refreshWindows()
            } else {
                // Permission revoked mid-run: no AX calls until it flips back.
                windowManager.reconcile(with: [])
            }
        case .windowsDidChange, .configurationDidChange,
             .workspaceDidChange, .displayConfigurationDidChange, .hotkeyTriggered:
            break
        }
    }

    // MARK: reconcile + tile

    /// The core gesture: snapshot windows, reconcile the manager, compute a
    /// frame plan, and apply it. Called on boot and any time permission returns.
    private func refreshWindows() {
        guard permissionGranted else { return }
        do {
            let windows = try discovery.scanWindows()
            windowManager.reconcile(with: windows)
            retile(windows: windows)
        } catch {
            // Missing/changed permission mid-scan: not fatal, log and wait.
            logger.error("Window scan failed: \(String(describing: error))")
        }
    }

    private func retile(windows: [Window]) {
        guard let display = displayFrames.displayFrame else {
            logger.info("No display to tile onto yet")
            return
        }
        let tiler = WindowTiler(
            display: display,
            layout: makeLayout(for: currentConfig.general.defaultLayout),
            config: LayoutConfig(gap: CGFloat(currentConfig.general.gap),
                                 outerGap: CGFloat(currentConfig.general.outerGap))
        )
        let plan = tiler.plan(for: windows)
        windowControl.apply(plan)
        logger.debug("Applied \(plan.count) frames on \(windows.count) windows")
    }
}

private extension MistConfig {
    /// Sensible built-in defaults used when no config file is present.
    static let `default` = MistConfig()
}