import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// The private AX entry point that maps an element to its CGWindowID.
/// Every open-source macOS WM uses this; it's the only way to get a window
/// identity that survives the tiler moving it around the screen.
@_silgen_name("_AXUIElementGetWindow")
private func axGetCGWindowID(_ element: AXUIElement, _ outID: UnsafeMutablePointer<UInt32>) -> AXError

/// Discovers top-level windows via the Accessibility API.
///
/// AX is inherently best-effort: a window can vanish mid-read, an app can be
/// unresponsive, and attributes can be missing. Every failure path is handled
/// here: a single window that fails to read is skipped, never fatal. Only
/// inputs we cannot even begin (no trust) throw.
public final class AccessibilityWindowDiscovery: @unchecked Sendable, WindowElementProviding {
    /// The trust checker used to short-circuit before hitting AX APIs.
    private let trust: any AccessibilityTrustChecking
    private let logger: Logger

    /// Maps window id → the last-resolved `AXUIElement`, refreshed every scan.
    /// Both the model and its live handle come from the same scan so they can't
    /// disagree; control layers resolve through here rather than re-enumerating.
    private let lock = NSLock()
    private var elementsByID: [String: AXUIElement] = [:]

    public init(trust: any AccessibilityTrustChecking, logger: Logger = .shared) {
        self.trust = trust
        self.logger = logger
    }

    // MARK: WindowElementProviding

    public func element(for windowID: String) -> AXUIElement? {
        lock.lock()
        defer { lock.unlock() }
        return elementsByID[windowID]
    }

    /// Reverse of `element(for:)`: finds which managed window an AX element
    /// belongs to. Used to translate the system-wide focused window into a
    /// managed window id. CF equality, not identity — AX elements are
    /// recreated between calls but compare equal for the same window.
    public func windowID(for element: AXUIElement) -> String? {
        lock.lock()
        defer { lock.unlock() }
        for (id, known) in elementsByID where CFEqual(known, element) {
            return id
        }
        return nil
    }

    /// Enumerates visible top-level windows as `Window` models.
    /// This is the data source for the `WindowManager`'s reconcile() pass.
    ///
    /// When permission is missing, returns a *non-fatal* result and logs WARNING;
    /// the app must not crash on a missing permission, it must guide the user.
    public func scanWindows() throws -> [Window] {
        guard trust.isTrusted else {
            throw MistError.accessibility(description: "accessibility permission not granted", underlying: nil)
        }

        let apps = NSWorkspace.shared.runningApplications
        var windows: [Window] = []
        // Rebuilt fresh every scan so closed windows can't leave stale handles
        // behind (the old append-only map grew without bound).
        var resolved: [String: AXUIElement] = [:]
        for app in apps {
            guard app.activationPolicy != .prohibited, let appElement = AXUIElementCreateApplication(app.processIdentifier) as AXUIElement? else {
                continue
            }
            // Bound how long a hung app can block this scan instead of
            // stalling on the system-wide default.
            AXUIElementSetMessagingTimeout(appElement, Self.axTimeout)
            let result = enumerateWindows(of: appElement, pid: app.processIdentifier, appName: app.localizedName ?? "", bundleID: app.bundleIdentifier ?? "", into: &windows, resolved: &resolved)
            switch result {
            case .success:
                break
            case .failure:
                // Skip this app entirely; keep going. Never let one bad app abort
                // the whole scan.
                logger.warning("Skipping \(app.localizedName ?? "unknown app"): could not read windows")
            }
        }
        lock.lock()
        elementsByID = resolved
        lock.unlock()
        return windows
    }

    /// Per-element AX messaging timeout. Generous enough for healthy apps,
    /// short enough that one wedged process can't freeze a scan.
    private static let axTimeout: Float = 0.5

    private func enumerateWindows(of appElement: AXUIElement,
                                  pid: pid_t,
                                  appName: String,
                                  bundleID: String,
                                  into windows: inout [Window],
                                  resolved: inout [String: AXUIElement]) -> Result<Void, MistError> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard error == .success, let value else {
            return .failure(MistError.accessibility(description: "no windows attribute", underlying: nil))
        }
        let axWindows = (value as? [AXUIElement]) ?? []
        for ax in axWindows {
            if let window = makeWindow(from: ax, pid: pid, appName: appName, bundleID: bundleID, resolved: &resolved) {
                windows.append(window)
            }
        }
        return .success(())
    }

    private func makeWindow(from element: AXUIElement,
                            pid: pid_t?,
                            appName: String,
                            bundleID: String,
                            resolved: inout [String: AXUIElement]) -> Window? {
        guard let frame = copyFrame(element) else { return nil }
        // Untitled windows are legitimate (many apps expose nil titles); tile
        // them on frame + identity rather than dropping them silently.
        let title = copyString(element, kAXTitleAttribute as CFString) ?? ""

        // Prefer the CGWindowID-backed identity: it survives retiles and
        // rescans, which position-derived ids never did.
        var cgID: UInt32 = 0
        let baseID: String
        if axGetCGWindowID(element, &cgID) == .success, cgID != 0 {
            baseID = "\(appName)-\(pid ?? 0)-\(cgID)"
        } else if let identifier = copyString(element, kAXIdentifierAttribute as CFString), !identifier.isEmpty {
            baseID = "\(appName)-\(identifier)"
        } else {
            baseID = makeFallbackID(appName: appName, frame: frame)
        }

        AXUIElementSetMessagingTimeout(element, Self.axTimeout)

        // Disambiguate collisions until the id is unique for this scan;
        // duplicate ids previously crashed downstream dictionary work.
        var id = baseID
        var suffix = 2
        while resolved[id] != nil {
            id = "\(baseID)#\(suffix)"
            suffix += 1
        }

        // Keep the live handle keyed by the same id the Window model uses so the
        // control layer can resolve it without a re-scan.
        resolved[id] = element

        return Window(id: id, displayIdentifier: nil, appName: appName, title: title, bundleID: bundleID, frame: frame)
    }

    private func copyString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    /// Interprets a CFTypeRef as an AXValue after verifying its type id. Returns
    /// nil when `value` is not an AXValue. Verification makes the forced downcast
    /// safe rather than a blind unwrap.
    private func asAXValue(_ value: CFTypeRef) -> AXValue? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }

    private func copyFrame(_ element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value else { return nil }
        guard let position = asAXValue(value) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(position, .cgPoint, &point) else { return nil }

        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let sizeValue else { return nil }
        guard let size = asAXValue(sizeValue) else { return nil }
        var sizeCG = CGSize.zero
        guard AXValueGetValue(size, .cgSize, &sizeCG) else { return nil }

        return CGRect(origin: point, size: sizeCG)
    }

    private func makeFallbackID(appName: String, frame: CGRect) -> String {
        "\(appName)-\(Int(frame.minX))-\(Int(frame.minY))"
    }
}