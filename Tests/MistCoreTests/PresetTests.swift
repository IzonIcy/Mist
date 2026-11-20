import Testing
import Foundation
import CoreGraphics
@testable import MistCore

/// Parsing, validation, and application of `[[preset]]` entries.
struct PresetParsingTests {

    private let loader = ConfigLoader()

    @Test func parsesEveryField() throws {
        let config = try loader.parse(text: """
        [[preset]]
        name = "coding"
        bundle_ids = ["com.apple.dt.Xcode", "com.mitchellh.ghostty"]
        layout = "horizontal"
        hotkey = "cmd+alt+1"
        """)
        #expect(config.presets.count == 1)
        let preset = try #require(config.presets.first)
        #expect(preset.name == "coding")
        #expect(preset.bundleIDs == ["com.apple.dt.Xcode", "com.mitchellh.ghostty"])
        #expect(preset.layout == .horizontal)
        #expect(preset.hotkey == (try HotkeyConfigurationParser.parseKeyString("cmd+alt+1")))
    }

    @Test func layoutDefaultsToTheGeneralLayout() throws {
        let config = try loader.parse(text: """
        [general]
        layout = "monocle"

        [[preset]]
        name = "calls"
        bundle_ids = ["us.zoom.xos"]
        """)
        #expect(config.presets.first?.layout == .monocle)
    }

    @Test func presetHotkeyBecomesABinding() throws {
        let config = try loader.parse(text: """
        [hotkeys]
        focus_left = "cmd+alt+h"

        [[preset]]
        name = "coding"
        bundle_ids = ["com.apple.dt.Xcode"]
        hotkey = "cmd+alt+1"
        """)
        #expect(config.hotkeyBindings.count == 2)
        #expect(config.hotkeyBindings.contains { $0.action == "preset:coding" })
        #expect(Preset.name(fromAction: "preset:coding") == "coding")
        #expect(Preset.name(fromAction: "focus_left") == nil)
    }

    @Test func presetWithoutHotkeyAddsNoBinding() throws {
        let config = try loader.parse(text: """
        [[preset]]
        name = "coding"
        bundle_ids = ["com.apple.dt.Xcode"]
        """)
        #expect(config.hotkeyBindings.isEmpty)
    }

    @Test func rejectsPresetWithoutName() {
        let message = errorMessage("""
        [[preset]]
        bundle_ids = ["com.apple.dt.Xcode"]
        """)
        #expect(message?.contains("preset #1 has no 'name'") == true)
    }

    @Test func rejectsPresetWithoutBundleIDs() {
        let message = errorMessage("""
        [[preset]]
        name = "coding"
        """)
        #expect(message?.contains("preset 'coding' has no 'bundle_ids'") == true)
    }

    @Test func rejectsEmptyBundleIDs() {
        let message = errorMessage("""
        [[preset]]
        name = "coding"
        bundle_ids = []
        """)
        #expect(message?.contains("preset 'coding' has an empty 'bundle_ids'") == true)
    }

    @Test func rejectsUnknownPresetLayout() {
        let message = errorMessage("""
        [[preset]]
        name = "coding"
        bundle_ids = ["com.apple.dt.Xcode"]
        layout = "kaleidoscope"
        """)
        #expect(message?.contains("unknown layout 'kaleidoscope'") == true)
    }

    @Test func rejectsUnparseablePresetHotkey() {
        let message = errorMessage("""
        [[preset]]
        name = "coding"
        bundle_ids = ["com.apple.dt.Xcode"]
        hotkey = "cmd+frobnicate"
        """)
        #expect(message?.contains("invalid hotkey 'cmd+frobnicate'") == true)
    }

    @Test func rejectsPresetHotkeyAlreadyBound() {
        let message = errorMessage("""
        [hotkeys]
        focus_left = "cmd+alt+h"

        [[preset]]
        name = "coding"
        bundle_ids = ["com.apple.dt.Xcode"]
        hotkey = "cmd+alt+h"
        """)
        #expect(message?.contains("preset 'coding'") == true)
        #expect(message?.contains("'focus_left'") == true)
    }

    @Test func rejectsPresetHotkeyCollidingWithAnotherPreset() {
        let message = errorMessage("""
        [[preset]]
        name = "coding"
        bundle_ids = ["com.apple.dt.Xcode"]
        hotkey = "cmd+alt+1"

        [[preset]]
        name = "calls"
        bundle_ids = ["us.zoom.xos"]
        hotkey = "cmd+alt+1"
        """)
        #expect(message?.contains("preset 'calls'") == true)
        #expect(message?.contains("'preset:coding'") == true)
    }

    @Test func rejectsDuplicatePresetNames() {
        let message = errorMessage("""
        [[preset]]
        name = "coding"
        bundle_ids = ["com.apple.dt.Xcode"]

        [[preset]]
        name = "coding"
        bundle_ids = ["com.mitchellh.ghostty"]
        """)
        #expect(message?.contains("duplicate preset name 'coding'") == true)
    }

    @Test func shippedExampleConfigLoads() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let config = try loader.load(from: root.appendingPathComponent("Support/mist.toml"))
        #expect(config.presets.map(\.name) == ["coding", "call"])
        #expect(config.hotkeyBindings.count == config.hotkeys.count + 2)
    }

    private func errorMessage(_ source: String) -> String? {
        do {
            _ = try loader.parse(text: source)
            return nil
        } catch {
            return String(describing: error)
        }
    }
}

/// The pure preset planner: a window snapshot in, frames and a missing-app
/// report out.
struct PresetApplyTests {

    private let display = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    private let spacing = LayoutConfig(gap: 0, outerGap: 0)

    @Test func tilesOnlyTheNamedAppsAndReportsTheMissingOne() {
        let preset = Preset(name: "coding",
                            bundleIDs: ["com.apple.dt.Xcode", "us.zoom.xos", "com.mitchellh.ghostty"],
                            layout: .horizontal)
        let plan = PresetTiler(preset: preset, display: display, config: spacing).plan(for: [
            window("x1", bundle: "com.apple.dt.Xcode"),
            window("z1", bundle: "us.zoom.xos"),
            window("s1", bundle: "com.apple.Safari"),
        ])
        #expect(plan.windowIDs == ["x1", "z1"])
        #expect(plan.missingBundleIDs == ["com.mitchellh.ghostty"])
        #expect(plan.frames["s1"] == nil)
        #expect(plan.frames.count == 2)
        #expect(plan.frames["x1"]?.minX == 0)
        #expect(plan.frames["z1"]?.minX == 800)
        #expect(plan.frames["x1"]?.width == 800)
    }

    @Test func tilesInBundleListOrderNotScanOrder() {
        let preset = Preset(name: "calls",
                            bundleIDs: ["us.zoom.xos", "com.apple.dt.Xcode"],
                            layout: .horizontal)
        let plan = PresetTiler(preset: preset, display: display, config: spacing).plan(for: [
            window("x1", bundle: "com.apple.dt.Xcode"),
            window("z1", bundle: "us.zoom.xos"),
        ])
        #expect(plan.windowIDs == ["z1", "x1"])
        #expect(plan.frames["z1"]?.minX == 0)
    }

    @Test func skipsFloatingWindowsWithoutCallingThemMissing() {
        let preset = Preset(name: "coding", bundleIDs: ["com.apple.dt.Xcode"], layout: .horizontal)
        let plan = PresetTiler(preset: preset, display: display, config: spacing).plan(for: [
            window("x1", bundle: "com.apple.dt.Xcode"),
            window("x2", bundle: "com.apple.dt.Xcode", floating: true),
        ])
        #expect(plan.windowIDs == ["x1"])
        #expect(plan.frames["x2"] == nil)
        #expect(plan.missingBundleIDs.isEmpty)
    }

    @Test func reportsEveryBundleWhenNothingIsRunning() {
        let preset = Preset(name: "coding",
                            bundleIDs: ["com.apple.dt.Xcode", "com.mitchellh.ghostty"],
                            layout: .bsp)
        let plan = PresetTiler(preset: preset, display: display, config: spacing).plan(for: [])
        #expect(plan.frames.isEmpty)
        #expect(plan.windowIDs.isEmpty)
        #expect(plan.missingBundleIDs == ["com.apple.dt.Xcode", "com.mitchellh.ghostty"])
    }

    private func window(_ id: String, bundle: String, floating: Bool = false) -> Window {
        Window(id: id,
               displayIdentifier: "display-1",
               appName: bundle,
               title: id,
               bundleID: bundle,
               frame: CGRect(x: 40, y: 40, width: 400, height: 300),
               isFloating: floating)
    }
}

/// Config keys Mist refuses to honour, so they fail the load instead of being
/// recorded and ignored.
struct ConfigRejectionTests {

    private let loader = ConfigLoader()

    @Test func rejectsAlwaysOnTopAndQuotesTheValue() {
        let message = errorMessage("""
        [[rules]]
        name = "PiP"
        window_app = "Safari"
        always_on_top = true
        """)
        #expect(message?.contains("always_on_top = true") == true)
        #expect(message?.contains("rule 'PiP'") == true)
    }

    @Test func rejectsAlwaysOnTopEvenWhenFalse() {
        let message = errorMessage("""
        [[rules]]
        window_app = "Safari"
        always_on_top = false
        """)
        #expect(message?.contains("always_on_top = false") == true)
    }

    private func errorMessage(_ source: String) -> String? {
        do {
            _ = try loader.parse(text: source)
            return nil
        } catch {
            return String(describing: error)
        }
    }
}

/// The animation settings are refused for the same reason always_on_top is:
/// there is nothing behind them to drive.
struct AnimationRejectionTests {

    private let loader = ConfigLoader()

    @Test func rejectsAnimateAndQuotesTheValue() {
        let message = errorMessage("[general]\nanimate = true")
        #expect(message?.contains("animate = true") == true)
        #expect(message?.contains("unsupported") == true)
    }

    @Test func rejectsAnimationCurveAndQuotesTheValue() {
        let message = errorMessage("[general]\nanimation = \"spring\"")
        #expect(message?.contains("animation = \"spring\"") == true)
        #expect(message?.contains("unsupported") == true)
    }

    private func errorMessage(_ source: String) -> String? {
        do {
            _ = try loader.parse(text: source)
            return nil
        } catch {
            return String(describing: error)
        }
    }
}
