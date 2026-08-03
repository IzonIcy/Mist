import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// Discovers top-level windows via the Accessibility API.
///
/// AX is inherently best-effort: a window can vanish mid-read, an app can be
/// unresponsive, and attributes can be missing. Every failure path is handled
/// here — a single window that fails to read is skipped, never fatal. Only
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

    /// Enumerates visible top-level windows as `Window` models.
    /// This is the data source for the `WindowManager`'s reconcile() pass.
    ///
    /// When permission is missing, returns a *non-fatal* result and logs WARNING
    /// — the app must not crash on a missing permission, it must guide the user.
    public func scanWindows() throws -> [Window] {
        guard trust.isTrusted else {
            throw MistError.accessibility(description: "accessibility permission not granted", underlying: nil)
        }

        let apps = NSWorkspace.shared.runningApplications
        var windows: [Window] = []
        for app in apps {
            guard app.activationPolicy != .prohibited, let appElement = AXUIElementCreateApplication(app.processIdentifier) as AXUIElement? else {
                continue
            }
            let result = enumerateWindows(of: appElement, appName: app.localizedName ?? "", bundleID: app.bundleIdentifier ?? "")
            switch result {
            case .success(let found):
                windows.append(contentsOf: found)
            case .failure:
                // Skip this app entirely; keep going. Never let one bad app abort
                // the whole scan.
                logger.warning("Skipping \(app.localizedName ?? "unknown app"): could not read windows")
            }
        }
        return windows
    }

    private func enumerateWindows(of appElement: AXUIElement,
                                  appName: String,
                                  bundleID: String) -> Result<[Window], MistError> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard error == .success, let value else {
            return .failure(MistError.accessibility(description: "no windows attribute", underlying: nil))
        }
        let axWindows = (value as? [AXUIElement]) ?? []
        var windows: [Window] = []
        for ax in axWindows {
            guard let window = makeWindow(from: ax, appName: appName, bundleID: bundleID) else {
                continue
            }
            windows.append(window)
        }
        return .success(windows)
    }

    private func makeWindow(from element: AXUIElement, appName: String, bundleID: String) -> Window? {
        guard let title = copyString(element, kAXTitleAttribute as CFString) else { return nil }
        guard let frame = copyFrame(element) else { return nil }

        let identifier = copyString(element, kAXIdentifierAttribute as CFString)
        let id: String
        if let identifier, !identifier.isEmpty {
            id = identifier
        } else {
            id = makeFallbackID(appName: appName, frame: frame)
        }

        // Keep the live handle keyed by the same id the Window model uses so the
        // control layer can resolve it without a re-scan.
        lock.lock()
        elementsByID[id] = element
        lock.unlock()

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