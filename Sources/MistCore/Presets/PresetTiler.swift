import Foundation
import CoreGraphics

/// What applying a preset resolves to: frames to apply, plus the apps it could
/// not find.
public struct PresetPlan: Equatable, Sendable {
    /// Frame per window id, top-left-origin display coordinates.
    public let frames: WindowPlan
    /// Planned window ids in tiling order, so the caller can raise them in a
    /// deterministic order. A dictionary cannot carry that.
    public let windowIDs: [String]
    /// Bundle ids from the preset with no window in the snapshot.
    public let missingBundleIDs: [String]

    public init(frames: WindowPlan, windowIDs: [String], missingBundleIDs: [String]) {
        self.frames = frames
        self.windowIDs = windowIDs
        self.missingBundleIDs = missingBundleIDs
    }
}

/// Turns a preset plus a window snapshot into frames and a missing-app report.
///
/// Pure by construction: no AX, no display lookups, no clocks. The app layer
/// hands in the snapshot it already scanned and applies whatever comes back.
public struct PresetTiler {
    public let preset: Preset
    public let display: CGRect
    public let config: LayoutConfig

    public init(preset: Preset, display: CGRect, config: LayoutConfig) {
        self.preset = preset
        self.display = display
        self.config = config
    }

    /// Collects the named apps' windows in `bundle_ids` order, tiles the ones
    /// the rules did not float, and reports the bundle ids with no window.
    ///
    /// A bundle id with no window counts as missing. The snapshot cannot tell
    /// "not running" from "running without windows", and both mean the preset
    /// cannot bring that app forward.
    public func plan(for windows: [Window]) -> PresetPlan {
        var matched: [Window] = []
        var missing: [String] = []
        for bundleID in preset.bundleIDs {
            let appWindows = windows.filter { $0.bundleID == bundleID }
            if appWindows.isEmpty {
                missing.append(bundleID)
            } else {
                matched.append(contentsOf: appWindows)
            }
        }

        let tiled = matched.filter { !$0.isFloating }
        let items = tiled.map { LayoutItem(id: LayoutItemID($0.id)) }
        let arranged = makeLayout(for: preset.layout).arrange(items: items, in: display, config: config)
        let frames = Dictionary(arranged.map { ($0.key.rawValue, $0.value) },
                                uniquingKeysWith: { first, _ in first })

        return PresetPlan(
            frames: frames,
            windowIDs: tiled.map(\.id),
            missingBundleIDs: missing
        )
    }
}
