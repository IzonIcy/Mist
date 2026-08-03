import Foundation

/// A value in a TOML document.
///
/// TOML 1.0 supports a closed set of value types; this enum mirrors them. Being
/// an enum (rather than a bag of `Any`) means the parser and the config mapper
/// can `switch` over it exhaustively, so adding a new TOML datatype later (e.g.
/// a date/time type) is a deliberate, compiler-checked change.
///
/// Original keys order is preserved for tables so the configuration model can
/// fail with a helpful "did you mean…" instead of a cryptic one.
public indirect enum TOMLValue: Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case float(Double)
    case bool(Bool)
    case array([TOMLValue])
    case table(TOMLTable)
}

/// An ordered map of TOML keys to values.
///
/// `Dictionary` has no ordering guarantee, but diagnostics ("wrong key at line
/// N") and round-tripping both want insertion order, so this wraps an ordered
/// key list plus a store.
public struct TOMLTable: Equatable, Sendable {
    /// Keys in the order they appeared in source.
    public private(set) var keys: [String]
    /// The values, keyed by name.
    private var storage: [String: TOMLValue]

    public init() {
        self.keys = []
        self.storage = [:]
    }

    /// Inserts or replaces `value` for `key`.
    public mutating func set(_ value: TOMLValue, forKey key: String) {
        if storage[key] == nil {
            keys.append(key)
        }
        storage[key] = value
    }

    /// Reads a value, or `nil` if absent.
    public func value(forKey key: String) -> TOMLValue? {
        storage[key]
    }

    /// Reads a string value if present and a string.
    public func string(forKey key: String) -> String? {
        guard case let .string(v) = storage[key] else { return nil }
        return v
    }

    /// Reads an integer value if present and an integer.
    public func integer(forKey key: String) -> Int64? {
        guard case let .integer(v) = storage[key] else { return nil }
        return v
    }

    /// Reads a float value if present and a float.
    public func float(forKey key: String) -> Double? {
        guard case let .float(v) = storage[key] else { return nil }
        return v
    }

    /// Reads a boolean value if present and a boolean.
    public func bool(forKey key: String) -> Bool? {
        guard case let .bool(v) = storage[key] else { return nil }
        return v
    }

    /// The number of entries.
    public var count: Int { keys.count }
}

/// Extension used by config mapping helpers to get values with friendly fallback.
extension TOMLTable {
    /// Reads an integer, applying a default if absent.
    public func integer(forKey key: String, default defaultValue: Int64) -> Int64 {
        integer(forKey: key) ?? defaultValue
    }
}

/// A fully parsed TOML document: its root table plus an optional `path` that the
/// source was read from (useful for diagnostics and hot reload).
public struct TOMLDocument: Equatable, Sendable {
    /// The root table.
    public var root: TOMLTable
    /// Where the source came from, used only for messages.
    public var sourceName: String

    public init(root: TOMLTable = TOMLTable(), sourceName: String = "<memory>") {
        self.root = root
        self.sourceName = sourceName
    }
}