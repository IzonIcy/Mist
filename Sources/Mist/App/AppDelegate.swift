import AppKit
import MistCore

/// The application delegate — the *thin* tip of Mist.
///
/// Per the charter, business logic must never depend on UI. This type owns only
/// AppKit lifecycle and hands the heavy lifting to `AppCoordinator` (pure
/// `MistCore`). If you find yourself adding window-management logic here, it
/// belongs in a Core module instead.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let buffer = NSApplication.shared
        _ = buffer

        // Build the Core stack and start it.
        let core = AppCoordinator(
            eventBus: EventBus(),
            logger: .shared
        )
        coordinator = core
        core.bootstrap()

        setupMenuBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }

    /// Minimal menu bar presence so the app is discoverable / un-quittable on
    /// accident. Settings UI (SwiftUI) attaches later.
    @MainActor
    private func setupMenuBar() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Mist")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Mist", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
}