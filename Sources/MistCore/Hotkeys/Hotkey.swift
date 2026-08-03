import Foundation
import Carbon.HIToolbox

/// A physical key (keycode) combined with modifiers.
///
/// `keyCode` is a Carbon virtual key code so it round-trips directly with the
/// Carbon event tap / `CGEvent` machinery used to actually catch keys. Storing
/// the code (not a character) is deliberate: it makes the mapping
/// layout-independent at the cost of having to translate for display later.
public struct Hotkey: Equatable, Hashable, Sendable {
    /// Carbon virtual key code (see `kVK_*` constants).
    public let keyCode: UInt16
    /// Modifier flags currently held.
    public var modifiers: ModifierMask

    public init(keyCode: UInt16, modifiers: ModifierMask = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// User-readable rendering for logs/diagnostics, e.g. "⌘+8".
    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        parts.append(String(keyCode))
        return parts.joined(separator: "+")
    }
}

/// Modifier flags applicable to a hotkey.
public struct ModifierMask: OptionSet, Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let command = ModifierMask(rawValue: 1 << 0)
    public static let option = ModifierMask(rawValue: 1 << 1)
    public static let control = ModifierMask(rawValue: 1 << 2)
    public static let shift = ModifierMask(rawValue: 1 << 3)
}

/// A named, configured binding: which key triggers which command.
public struct HotkeyConfiguration: Equatable, Sendable {
    /// Stable name used in logs and the settings UI (e.g. `"focus_left"`).
    public var name: String
    /// The key combination.
    public var key: Hotkey
    /// The command/action this binding triggers (a `Command` identifier).
    public var action: String

    public init(name: String, key: Hotkey, action: String) {
        self.name = name
        self.key = key
        self.action = action
    }
}

/// Owns the live hotkey bindings.
///
/// The `Action` type below is a wire term for "string identifier"; mapping that
/// to a real closure happens at the app layer so this stays dependency-free.
public protocol HotkeyManaging: AnyObject {
    /// Replaces all bindings. Throws `MistError.hotkeyConflict` if two bindings
    /// claim the same `Hotkey`.
    func setBindings(_ bindings: [HotkeyConfiguration]) throws
    /// Removes all bindings.
    func clear()
    /// Returns the action bound to the given key, if any.
    func action(for key: Hotkey) -> String?
}

/// Default implementation backed by a concurrent dictionary of the bindings.
///
/// Only conflict detection is implemented here; wiring into a CGEvent tap is the
/// app target's job (it owns the event loop). This keeps `MistCore` pure.
public final class HotkeyManager {
    public init() {}

    private let lock = NSLock()
    private var map: [Hotkey: String] = [:]
    private var names: [String: Hotkey] = [:]
}

extension HotkeyManager: HotkeyManaging {
    public func setBindings(_ bindings: [HotkeyConfiguration]) throws {
        // Reject conflicts before mutating anything.
        var byKey: [Hotkey: String] = [:]
        for binding in bindings {
            if let existing = byKey[binding.key] {
                throw MistError.hotkeyConflict(key: describe(binding.key),
                                               firstAction: existing,
                                               secondAction: binding.action)
            }
            byKey[binding.key] = binding.action
        }

        lock.lock()
        defer { lock.unlock() }
        self.map = byKey
        self.names = Dictionary(uniqueKeysWithValues: bindings.filter { $0.name.count > 0 }.map { ($0.name, $0.key) })
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        map.removeAll()
        names.removeAll()
    }

    public func action(for key: Hotkey) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return map[key]
    }

    private func describe(_ key: Hotkey) -> String {
        key.description
    }
}