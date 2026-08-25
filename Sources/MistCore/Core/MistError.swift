import Foundation

/// The root error type for every failure the app knows how to *name*.
///
/// The charter says never to ignore errors: every failure should carry
/// context. This single type lets each layer describe failures in a way that
/// can be surfaced to the log and, where appropriate, the user, without anyone
/// guessing from a raw `Code`.
public enum MistError: Error, CustomStringConvertible {
    /// A file could not be read.
    case readFailed(path: String, underlying: Error)

    /// A file could not be written (e.g. saving an updated config).
    case writeFailed(path: String, underlying: Error)

    /// TOML source could not be parsed. `field` names the offending key and
    /// `line` is 1-based; both are optional when the failure is structural.
    case configParseFailed(field: String?, line: Int?, message: String)

    /// Configuration parsed but failed semantic validation.
    case invalidConfiguration(String)

    /// A display could not be resolved from its identifier.
    case displayNotFound(String)

    /// A required accessibility operation failed (missing permission, element
    /// went away, etc.). Never crashes; callers catch and downgrade.
    case accessibility(description: String, underlying: Error?)

    /// Two distinct actions claim the same hotkey.
    case hotkeyConflict(key: String, firstAction: String, secondAction: String)

    /// A described failure with no more precise category.
    case unresolved(String)

    public var description: String {
        switch self {
        case let .readFailed(path, underlying):
            return "Could not read '\(path)': \(underlying)"
        case let .writeFailed(path, underlying):
            return "Could not write '\(path)': \(underlying)"
        case let .configParseFailed(field, line, message):
            var out = "Invalid TOML"
            if let field { out += " (field '\(field)')" }
            if let line { out += " at line \(line)" }
            return "\(out): \(message)"
        case let .invalidConfiguration(message):
            return "Invalid configuration: \(message)"
        case let .displayNotFound(id):
            return "Display '\(id)' no longer exists"
        case let .accessibility(desc, underlying):
            var out = "Accessibility failure: \(desc)"
            if let underlying = underlying { out += " (\(underlying))" }
            return out
        case let .hotkeyConflict(key, firstAction, secondAction):
            return "Hotkey \(key) is bound to both '\(firstAction)' and '\(secondAction)'"
        case let .unresolved(message):
            return message
        }
    }
}

