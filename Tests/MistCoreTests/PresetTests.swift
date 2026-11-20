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

    private func errorMessage(_ source: String) -> String? {
        do {
            _ = try loader.parse(text: source)
            return nil
        } catch {
            return String(describing: error)
        }
    }
}
