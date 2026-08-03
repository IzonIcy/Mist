import Testing
import Foundation
@testable import MistCore

/// Exercises the config pipeline end-to-end: TOML → validated `MistConfig`.
struct ConfigLoaderTests {

    private let loader = ConfigLoader()

    @Test func parsesGeneralSection() throws {
        let config = try loader.parse(text: """
        [general]
        gap = 12
        outer_gap = 20
        layout = "monocle"
        """)
        #expect(config.general.gap == 12)
        #expect(config.general.outerGap == 20)
        #expect(config.general.defaultLayout == .monocle)
    }

    @Test func defaultsWhenSectionMissing() throws {
        let config = try loader.parse(text: "")
        #expect(config.general.gap == 8)
        #expect(config.general.defaultLayout == .bsp)
    }

    @Test func parsesHotkeys() throws {
        let config = try loader.parse(text: """
        [hotkeys]
        focus_left = "cmd+alt+h"
        focus_right = "cmd+alt+l"
        """)
        #expect(config.hotkeys.count == 2)
        #expect(config.hotkeys[0].name == "focus_left")
    }

    @Test func rejectsUnknownLayout() {
        #expect(throws: MistError.self) {
            _ = try loader.parse(text: "[general]\nlayout = \"kaleidoscope\"")
        }
    }

    @Test func rejectsBadHotkeyModifier() {
        #expect(throws: MistError.self) {
            _ = try loader.parse(text: "[hotkeys]\nfocus_left = \"super+h\"")
        }
    }

    @Test func parsesRules() throws {
        let config = try loader.parse(text: """
        [[rules]]
        name = "Float Safari"
        window_app = "Safari"
        float = true
        """)
        #expect(config.rules.count == 1)
        #expect(config.rules[0].name == "Float Safari")
        let actions = config.rules[0].condition.matches(WindowSnapshot(appName: "Safari", title: "", bundleID: ""))
        #expect(actions == true)
    }

    @Test func fullDocument() throws {
        let source = """
        [general]
        gap = 8
        outer_gap = 16
        layout = "bsp"

        [hotkeys]
        focus_left = "cmd+alt+h"

        [[rules]]
        window_app = "Safari"
        float = true
        """
        let config = try loader.parse(text: source)
        #expect(config.hotkeys.count == 1)
        #expect(config.rules.count == 1)
    }
}