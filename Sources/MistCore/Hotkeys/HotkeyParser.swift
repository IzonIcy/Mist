import Foundation
import Carbon.HIToolbox

/// Turns a config `[hotkeys]` table into hotkey bindings.
///
/// Config shape (flat map of binding name -> key string):
/// ```toml
/// [hotkeys]
/// focus_left  = "cmd+alt+h"
/// focus_right = "cmd+alt+l"
/// ```
///
/// The key string is `modifier+...+keyname`, e.g. `cmd+alt+8`. Parsing happens
/// here so typo'd modifiers/keys are reported as a helpful `invalidConfiguration`
/// rather than silently ignored.
struct HotkeyConfigurationParser {
    let table: TOMLTable

    func parse() throws -> [HotkeyConfiguration] {
        var result: [HotkeyConfiguration] = []
        for key in table.keys {
            guard let raw = table.string(forKey: key) else {
                throw MistError.invalidConfiguration("hotkey '\(key)' must be a string")
            }
            let hotkey = try Self.parseKeyString(raw)
            result.append(HotkeyConfiguration(name: key, key: hotkey, action: key))
        }
        return result
    }

    /// Parses `"cmd+alt+8"` into a `Hotkey`.
    static func parseKeyString(_ raw: String) throws -> Hotkey {
        let parts = raw.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last else {
            throw MistError.invalidConfiguration("empty hotkey '\(raw)'")
        }
        // kVK_ANSI_A is 0, so the sentinel must be nil — not zero.
        guard let keyCode = keyCode(for: last) else {
            throw MistError.invalidConfiguration("unrecognized key '\(last)' in hotkey '\(raw)'")
        }

        var mask: ModifierMask = []
        for modifier in parts.dropLast() {
            switch modifier.lowercased() {
            case "cmd", "command": mask.insert(.command)
            case "alt", "option": mask.insert(.option)
            case "ctrl", "control": mask.insert(.control)
            case "shift": mask.insert(.shift)
            default:
                throw MistError.invalidConfiguration("unknown modifier '\(modifier)' in hotkey '\(raw)'")
            }
        }
        return Hotkey(keyCode: keyCode, modifiers: mask)
    }

    /// Maps a key name (e.g. "h", "8", "return") to a Carbon key code.
    /// Returns nil for unknown key names. Note kVK_ANSI_A == 0, which is
    /// exactly why this returns an Optional instead of a zero sentinel.
    private static func keyCode(for name: String) -> UInt16? {
        switch name.lowercased() {
        case "a": return UInt16(kVK_ANSI_A)
        case "b": return UInt16(kVK_ANSI_B)
        case "c": return UInt16(kVK_ANSI_C)
        case "d": return UInt16(kVK_ANSI_D)
        case "e": return UInt16(kVK_ANSI_E)
        case "f": return UInt16(kVK_ANSI_F)
        case "g": return UInt16(kVK_ANSI_G)
        case "h": return UInt16(kVK_ANSI_H)
        case "i": return UInt16(kVK_ANSI_I)
        case "j": return UInt16(kVK_ANSI_J)
        case "k": return UInt16(kVK_ANSI_K)
        case "l": return UInt16(kVK_ANSI_L)
        case "m": return UInt16(kVK_ANSI_M)
        case "n": return UInt16(kVK_ANSI_N)
        case "o": return UInt16(kVK_ANSI_O)
        case "p": return UInt16(kVK_ANSI_P)
        case "q": return UInt16(kVK_ANSI_Q)
        case "r": return UInt16(kVK_ANSI_R)
        case "s": return UInt16(kVK_ANSI_S)
        case "t": return UInt16(kVK_ANSI_T)
        case "u": return UInt16(kVK_ANSI_U)
        case "v": return UInt16(kVK_ANSI_V)
        case "w": return UInt16(kVK_ANSI_W)
        case "x": return UInt16(kVK_ANSI_X)
        case "y": return UInt16(kVK_ANSI_Y)
        case "z": return UInt16(kVK_ANSI_Z)
        case "0": return UInt16(kVK_ANSI_0)
        case "1": return UInt16(kVK_ANSI_1)
        case "2": return UInt16(kVK_ANSI_2)
        case "3": return UInt16(kVK_ANSI_3)
        case "4": return UInt16(kVK_ANSI_4)
        case "5": return UInt16(kVK_ANSI_5)
        case "6": return UInt16(kVK_ANSI_6)
        case "7": return UInt16(kVK_ANSI_7)
        case "8": return UInt16(kVK_ANSI_8)
        case "9": return UInt16(kVK_ANSI_9)
        case "return", "enter": return UInt16(kVK_Return)
        case "tab": return UInt16(kVK_Tab)
        case "space": return UInt16(kVK_Space)
        case "backspace", "delete": return UInt16(kVK_ForwardDelete)
        default:
            return nil
        }
    }
}