import Foundation

/// A named set of apps, bound to one layout and an optional hotkey.
///
/// Presets are the "put my desk back" gesture: one key brings a fixed set of
/// apps to the front and tiles only those windows. They are validated at parse
/// time like rules, so a preset that cannot work never binds.
public struct Preset: Equatable, Sendable {
    /// The name used in config and on the hotkey wire.
    public let name: String
    /// Bundle ids the preset collects, in the order they should be tiled.
    public let bundleIDs: [String]
    /// The layout that arranges them.
    public let layout: LayoutName
    /// The key that applies the preset, if it has one.
    public let hotkey: Hotkey?

    public init(name: String, bundleIDs: [String], layout: LayoutName, hotkey: Hotkey? = nil) {
        self.name = name
        self.bundleIDs = bundleIDs
        self.layout = layout
        self.hotkey = hotkey
    }

    /// Wire name for a preset action, so `[hotkeys]` and `[[preset]]` share one
    /// spelling and the dispatcher stays a string switch.
    public static let actionPrefix = "preset:"

    /// The action identifier this preset's hotkey carries.
    public var action: String { Self.actionPrefix + name }

    /// Recovers the preset name from an action identifier, or nil when the
    /// identifier is not a preset action.
    public static func name(fromAction action: String) -> String? {
        guard action.hasPrefix(actionPrefix) else { return nil }
        return String(action.dropFirst(actionPrefix.count))
    }
}

extension MistConfig {
    /// Every binding the app should register: the `[hotkeys]` table plus one
    /// synthetic binding per preset that declares a hotkey.
    ///
    /// Kept on the config so conflict detection sees one flat list, the same
    /// shape `HotkeyManager` consumes.
    public var hotkeyBindings: [HotkeyConfiguration] {
        hotkeys + presets.compactMap { preset in
            preset.hotkey.map { HotkeyConfiguration(name: preset.action, key: $0, action: preset.action) }
        }
    }
}
