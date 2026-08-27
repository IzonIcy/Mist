import AppKit
import MistCore

/// The application delegate: the *thin* tip of Mist.
///
/// Per the charter, business logic must never depend on UI. This type owns only
/// AppKit lifecycle and hands the heavy lifting to `AppCoordinator` (pure
/// `MistCore`). If you find yourself adding window-management logic here, it
/// belongs in a Core module instead.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var mouseMonitor: Any?
    /// NSStatusItem must be strongly retained by its owner or the menu bar
    /// item disappears once setupMenuBar() returns.
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let core = AppCoordinator(
            eventBus: EventBus(),
            logger: .shared
        )
        coordinator = core
        core.bootstrap()

        setupMenuBar()
        setupFocusFollowsMouseIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        coordinator?.shutdown()
    }

    /// Installs a global mouse-move monitor when `focus_follows_mouse` is on.
    /// Global monitors only see events delivered to *other* apps, which is
    /// exactly the case we care about; Mist's own windows never need this.
    private func setupFocusFollowsMouseIfNeeded() {
        guard let coordinator, coordinator.focusFollowsMouseEnabled else { return }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .otherMouseDragged, .leftMouseDragged]) { [weak self] _ in
            self?.coordinator?.focusWindow(at: Self.cgPoint(from: NSEvent.mouseLocation))
        }
    }

    /// AppKit's global mouse location is bottom-left origin; the window frames
    /// from AX are top-left origin (CG coordinates). Convert before lookup.
    /// Both spaces anchor to the *primary* screen, so its height is the right
    /// pivot; using the tallest screen breaks vertically-stacked displays.
    private static func cgPoint(from appKitPoint: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: appKitPoint.x, y: primaryHeight - appKitPoint.y)
    }

    /// Minimal menu bar presence so the app is discoverable / un-quittable on
    /// accident. Settings UI (SwiftUI) attaches later.
    @MainActor
    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Mist")
        }
        let menu = NSMenu()

        // Permission status & prompt
        let permItem = NSMenuItem(
            title: "Accessibility Permission: Checking…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permItem.target = self
        permItem.isEnabled = true
        menu.addItem(permItem)
        // Update after a moment once the monitor has run
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.updatePermissionMenuItem(permItem)
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Mist", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func updatePermissionMenuItem(_ item: NSMenuItem) {
        guard let coordinator else { return }
        let granted = coordinator.isAccessibilityGranted
        item.title = granted ? "✅ Accessibility Permission: Granted" : "⚠️ Accessibility Permission: Missing (click to fix)"
    }
}