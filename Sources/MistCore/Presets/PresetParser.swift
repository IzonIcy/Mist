import Foundation

/// Builds a `Preset` from one parsed `[[preset]]` table.
///
/// Expected shape:
/// ```toml
/// [[preset]]
/// name = "coding"
/// bundle_ids = ["com.mitchellh.ghostty", "com.apple.dt.Xcode"]
/// layout = "bsp"                  # optional, falls back to [general].layout
/// hotkey = "cmd+alt+1"            # optional
/// ```
///
/// Every failure names what is wrong and quotes the value, so a typo fails the
/// whole config load instead of binding a key that never fires.
struct PresetParser {
    let table: TOMLTable
    /// 0-based position in the document, used when the preset has no name.
    let index: Int
    /// `[general].layout`, used when the preset does not choose one.
    let defaultLayout: LayoutName

    func parse() throws -> Preset {
        let name = try parseName()
        let bundleIDs = try parseBundleIDs(name: name)
        let layout = try parseLayout(name: name)
        let hotkey = try parseHotkey(name: name)
        return Preset(name: name, bundleIDs: bundleIDs, layout: layout, hotkey: hotkey)
    }

    private func parseName() throws -> String {
        guard let raw = table.value(forKey: "name") else {
            throw MistError.invalidConfiguration("preset #\(index + 1) has no 'name'")
        }
        guard case let .string(name) = raw else {
            throw MistError.invalidConfiguration("preset #\(index + 1) has a 'name' that is not a string")
        }
        guard !name.isEmpty else {
            throw MistError.invalidConfiguration("preset #\(index + 1) has an empty name \"\"")
        }
        return name
    }

    private func parseBundleIDs(name: String) throws -> [String] {
        guard let raw = table.value(forKey: "bundle_ids") else {
            throw MistError.invalidConfiguration("preset '\(name)' has no 'bundle_ids'")
        }
        guard case let .array(items) = raw else {
            throw MistError.invalidConfiguration("preset '\(name)' has a 'bundle_ids' that is not an array")
        }
        var bundleIDs: [String] = []
        for item in items {
            guard case let .string(bundleID) = item else {
                throw MistError.invalidConfiguration(
                    "preset '\(name)' has a 'bundle_ids' entry that is not a string")
            }
            if !bundleIDs.contains(bundleID) {
                bundleIDs.append(bundleID)
            }
        }
        guard !bundleIDs.isEmpty else {
            throw MistError.invalidConfiguration("preset '\(name)' has an empty 'bundle_ids'")
        }
        return bundleIDs
    }

    private func parseLayout(name: String) throws -> LayoutName {
        guard let raw = table.value(forKey: "layout") else { return defaultLayout }
        guard case let .string(value) = raw else {
            throw MistError.invalidConfiguration("preset '\(name)' has a 'layout' that is not a string")
        }
        guard let layout = LayoutName(rawValue: value) else {
            let known = LayoutName.allCases.map(\.rawValue).joined(separator: ", ")
            throw MistError.invalidConfiguration(
                "preset '\(name)' has unknown layout '\(value)' (expected one of \(known))")
        }
        return layout
    }

    private func parseHotkey(name: String) throws -> Hotkey? {
        guard let raw = table.value(forKey: "hotkey") else { return nil }
        guard case let .string(value) = raw else {
            throw MistError.invalidConfiguration("preset '\(name)' has a 'hotkey' that is not a string")
        }
        do {
            return try HotkeyConfigurationParser.parseKeyString(value)
        } catch {
            throw MistError.invalidConfiguration("preset '\(name)' has an invalid hotkey '\(value)'")
        }
    }
}
