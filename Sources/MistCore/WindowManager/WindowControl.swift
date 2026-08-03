import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// Supplies the current `AXUIElement` for a window, so the control layer doesn't
/// have to own the scan. Discovery populates it during a resolve.
public protocol WindowElementProviding {
    /// Returns the live accessibility element for `windowID`, or nil if the
    /// window is gone / not resolvable.
    func element(for windowID: String) -> AXUIElement?
}

/// Moves, resizes, and focuses real windows through the Accessibility API.
public protocol WindowControling: AnyObject {
    /// Applies a frame plan (window id → frame, in global AX coordinates).
    func apply(_ plan: WindowPlan)
    /// Raises + activates the app owning the given window id.
    func focus(windowID: String)
}

/// Concrete `WindowControling` backed by AX.
///
/// Every mutation requires a trusted process. A single failed element is logged
/// and skipped, never fatal, so one unresponsive app can't abort a layout pass.
public final class AccessibilityWindowControl: @unchecked Sendable, WindowControling {
    private let resolver: any WindowElementProviding
    private let logger: Logger

    public init(resolver: any WindowElementProviding, logger: Logger = .shared) {
        self.resolver = resolver
        self.logger = logger
    }

    public func apply(_ plan: WindowPlan) {
        for (windowID, frame) in plan {
            guard let element = resolver.element(for: windowID) else {
                // Vanished between plan and apply; the next reconcile fixes it.
                logger.debug("Skipping \(windowID): no live element")
                continue
            }
            setFrame(frame, on: element)
        }
    }

    public func focus(windowID: String) {
        guard let element = resolver.element(for: windowID) else {
            logger.debug("No element for \(windowID)")
            return
        }
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        if let pid = owningPID(of: element),
           let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateAllWindows])
        }
    }

    private func setFrame(_ frame: CGRect, on element: AXUIElement) {
        var point = frame.origin
        if let value = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        }
        var size = frame.size
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
    }

    private func owningPID(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        let error = AXUIElementGetPid(element, &pid)
        return error == .success ? pid : nil
    }
}