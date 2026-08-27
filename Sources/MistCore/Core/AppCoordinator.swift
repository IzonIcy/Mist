import Foundation
import Combine
import CoreGraphics
import Carbon.HIToolbox

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
    /// Live handle for the CGEventTap; nil until permission is granted.
    private var eventTap: CFMachPort?

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
    private var configWatcher: DispatchSourceFileSystemObject?

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
            startHotkeyTap()
        } else {
            trust.requestPermission()
        }
        watchConfigFile()
        wireFocusSeam()
        logger.info("Mist booted")
        eventBus.publish(.didFinishLaunching)
    }

    public func shutdown() {
        accessibilityMonitor?.stop()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        configWatcher?.cancel()
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

    /// Watches the config file so edits apply live. A parse failure keeps the
    /// last-good config (the watcher just waits for the next edit).
    private func watchConfigFile() {
        guard let url = configLoader.defaultConfigURL(), FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        // Re-arm on every change: DispatchSource consumes its descriptor's
        // interest after one fire when the file is replaced by an editor.
        let armWatcher: () -> Void = { [weak self] in
            guard let self else { return }
            self.configWatcher?.cancel()
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else { return }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.loadConfiguration()
                self?.refreshWindows()
                self?.armConfigWatcher()
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            self.configWatcher = source
        }
        armWatcher()
    }

    fileprivate func armConfigWatcher() {
        watchConfigFile()
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

    /// Current accessibility permission state.
    public var isAccessibilityGranted: Bool {
        permissionGranted
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
                startHotkeyTap()
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

    /// The core gesture: snapshot windows, apply config rules, reconcile the
    /// manager, compute a frame plan, and apply it. Called on boot, any time
    /// permission returns, and after a config edit.
    private func refreshWindows() {
        guard permissionGranted else { return }
        do {
            var windows = try discovery.scanWindows()
            applyRules(to: &windows)
            windowManager.reconcile(with: windows)
            retile(windows: windows)
        } catch {
            // Missing/changed permission mid-scan: not fatal, log and wait.
            logger.error("Window scan failed: \(String(describing: error))")
        }
    }

    /// Bakes matched-rule actions into the scanned windows before reconcile.
    /// Rules re-evaluate every scan, so the config stays the single source of
    /// truth for float/always-on-top state. Monitor/workspace/layout actions
    /// are now wired to the display and workspace managers.
    private func applyRules(to windows: inout [Window]) {
        guard !currentConfig.rules.isEmpty else { return }
        let engine = RuleEngine(rules: currentConfig.rules)
        let displays = displayManager.displays
        for index in windows.indices {
            for action in engine.actions(for: windows[index].snapshot) {
                switch action {
                case .float(let value):
                    windows[index].isFloating = value
                case .alwaysOnTop(let value):
                    windows[index].isAlwaysOnTop = value
                case .monitor(let displayIndex):
                    // Display index in config is 1-based; map to actual display.
                    let targetIndex = displayIndex - 1
                    if targetIndex >= 0 && targetIndex < displays.count {
                        let targetDisplay = displays[targetIndex]
                        // Move window to this display's workspace (or create one)
                        let workspaceID = "display-\(targetDisplay.id)"
                        if workspaceManager.workspace(id: workspaceID) == nil {
                            workspaceManager.add(Workspace(id: workspaceID, name: workspaceID, layout: .bsp, displayID: targetDisplay.id))
                        }
                        workspaceManager.move(windowID: windows[index].id, to: workspaceID)
                        displayManager.assign(workspace: workspaceID, to: targetDisplay.id)
                    }
                case .workspace(let workspaceID):
                    // Ensure workspace exists with a default layout
                    if workspaceManager.workspace(id: workspaceID) == nil {
                        workspaceManager.add(Workspace(id: workspaceID, name: workspaceID, layout: .bsp))
                    }
                    workspaceManager.move(windowID: windows[index].id, to: workspaceID)
                case .layout(let layoutName):
                    // Set layout on the window's current workspace (or active)
                    let windowID = windows[index].id
                    var targetWorkspaceID: String?
                    for ws in workspaceManager.workspaces where ws.windowIDs.contains(windowID) {
                        targetWorkspaceID = ws.id
                        break
                    }
                    targetWorkspaceID = targetWorkspaceID ?? workspaceManager.activeWorkspaceID
                    if let wsID = targetWorkspaceID,
                       var ws = workspaceManager.workspace(id: wsID) {
                        ws.layout = layoutName
                        workspaceManager.add(ws) // update
                    }
                }
            }
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

    // MARK: hotkeys

    // The tap callback runs on the main run loop only, so this handoff is
    // single-threaded in practice; unsafe-static keeps Swift 6 happy.
    nonisolated(unsafe) private static var activeCoordinator: AppCoordinator?

    /// Installs a HID-level key tap so configured bindings fire system-wide.
    /// Matched events are consumed; everything else passes through untouched.
    private func startHotkeyTap() {
        guard eventTap == nil else { return }
        Self.activeCoordinator = self
        let callback: CGEventTapCallBack = { _, type, event, _ in
            guard type == .keyDown,
                  AppCoordinator.activeCoordinator?.handleKeyEvent(event) == true else {
                return Unmanaged.passUnretained(event)
            }
            return nil // swallow the key we acted on
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else {
            logger.error("Could not create hotkey event tap (input monitoring permission missing?)")
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Returns true when the event matched a binding and was handled.
    private func handleKeyEvent(_ event: CGEvent) -> Bool {
        guard let hotkeyManager else { return false }
        var modifiers: ModifierMask = []
        if event.flags.contains(.maskCommand) { modifiers.insert(.command) }
        if event.flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if event.flags.contains(.maskControl) { modifiers.insert(.control) }
        if event.flags.contains(.maskShift) { modifiers.insert(.shift) }
        let key = Hotkey(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)), modifiers: modifiers)
        guard let action = hotkeyManager.action(for: key) else { return false }
        performAction(action)
        return true
    }

    /// Dispatches a bound hotkey name to its behavior. The names are the
    /// binding keys from `[hotkeys]`, documented in the example config.
    private func performAction(_ action: String) {
        switch action {
        case "focus_left", "focus_right", "focus_up", "focus_down":
            let direction: FocusDirection = action.hasSuffix("left") ? .left
                : action.hasSuffix("right") ? .right
                : action.hasSuffix("up") ? .up
                : .down
            focusDirectional(direction)
        case "toggle_float":
            toggleFloatFocused()
        default:
            logger.debug("No behavior bound to hotkey action '\(action)' yet")
        }
    }

    /// Focused-window lookup goes through the system-wide AX element, then is
    /// translated into a managed id via the discovery cache.
    private func focusedWindowID() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value else { return nil }
        let focusedElement = value as! AXUIElement
        return discovery.windowID(for: focusedElement)
    }

    private func focusDirectional(_ direction: FocusDirection) {
        let windows = windowManager.windows
        guard let target = WindowNavigation.nextWindow(from: focusedWindowID(), in: windows, direction: direction) else {
            logger.debug("No window to focus \(String(describing: direction))")
            return
        }
        windowControl.focus(windowID: target.id)
    }

    private func toggleFloatFocused() {
        guard let id = focusedWindowID() ?? lastMouseFocusedWindowID else {
            logger.debug("toggle_float: no focused window")
            return
        }
        let windows = windowManager.windows
        guard let current = windows.first(where: { $0.id == id }) else { return }
        windowManager.setFloating(!current.isFloating, for: id)
        retile(windows: windowManager.windows)
    }
}

private extension MistConfig {
    /// Sensible built-in defaults used when no config file is present.
    static let `default` = MistConfig()
}