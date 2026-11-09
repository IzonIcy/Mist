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

    @Test func parsesKnownActionNames() throws {
        var table = TOMLTable()
        table.set(.string("cmd+alt+h"), forKey: "focus_left")
        table.set(.string("cmd+alt+space"), forKey: "toggle_float")

        let bindings = try HotkeyConfigurationParser(table: table).parse()
        #expect(bindings.map(\.action) == ["focus_left", "toggle_float"])
    }

    @Test func parsesWorkspaceActions() throws {
        var table = TOMLTable()
        table.set(.string("cmd+alt+3"), forKey: "workspace_3")

        let bindings = try HotkeyConfigurationParser(table: table).parse()
        #expect(bindings.first?.action == "workspace_3")
    }

    @Test func unknownActionNameThrows() {
        var table = TOMLTable()
        table.set(.string("cmd+alt+h"), forKey: "focus_lefft")

        #expect(throws: MistError.self) {
            _ = try HotkeyConfigurationParser(table: table).parse()
        }
    }
}
