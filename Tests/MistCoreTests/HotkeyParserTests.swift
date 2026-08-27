import Testing
import Carbon.HIToolbox
@testable import MistCore

/// Regression coverage for `parseKeyString` — kVK_ANSI_A is 0, so the
/// parser must distinguish "the letter a" from "unknown key" without a
/// zero sentinel.
struct HotkeyParserTests {

    @Test func parsesLetterAWhoseKeyCodeIsZero() throws {
        let hotkey = try HotkeyConfigurationParser.parseKeyString("cmd+alt+a")
        #expect(hotkey.keyCode == UInt16(kVK_ANSI_A))
    }

    @Test func parsesModifiersAndKeys() throws {
        let hotkey = try HotkeyConfigurationParser.parseKeyString("ctrl+shift+return")
        #expect(hotkey.keyCode == UInt16(kVK_Return))
    }

    @Test func unknownKeyThrows() {
        #expect(throws: MistError.self) {
            _ = try HotkeyConfigurationParser.parseKeyString("cmd+frobnicate")
        }
    }
}
