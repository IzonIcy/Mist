import Foundation

/// A small, correct, hand-written TOML 1.0 parser.
///
/// Why hand-written? The charter says to prefer Apple APIs and avoid third-party
/// dependencies, and a config file is a hostile surface for supply-chain risk.
/// The trade-off is scope: this implements the *practical* subset Mist's config
/// needs, correctly, rather than the entire spec. Anything unsupported is
/// rejected with a positioned error instead of being silently mis-parsed.
///
/// Supported:
///   - comments (`#`) and blank lines
///   - bare or quoted (basic or literal) keys, and dotted keys
///   - values: basic strings (with escapes), literal strings, integers,
///     floats, booleans, and arrays of those scalars
///   - `[table]` headers and `[[array-of-tables]]` headers
///
/// Not yet supported (rejected with a `MistError` naming the line):
///   - multi-line (`"""`) strings, datetimes, inline tables, nested arrays
///
/// Known limitation (pre-existing): sub-tables of array-of-tables entries
/// (`[[t]]` combined with `[t.u]`) attach in dictionary order at assembly
/// time, so mixing both for the same root name may mis-nest instead of
/// erroring. Mist's config schema doesn't use this shape.
public struct TOMLParser {
    private let sourceName: String
    private var chars: [Character]
    private var index = 0
    private var line = 1
    private var arrayDepth = 0

    /// Maximum nested-array depth. Hand-written recursive descent + hostile
    /// input means unbounded recursion is a stack overflow waiting to happen;
    /// this turns `a = [[[[[…` into a positioned error instead of a crash.
    private static let maxArrayDepth = 16

    /// Creates a parser for `source`, labelled `sourceName` in errors.
    ///
    /// Normalizes UTF-8 BOM and CRLF/CR line endings up front so files saved
    /// by Windows/cross-platform editors parse instead of failing with a
    /// cryptic "expected end of line".
    public init(source: String, sourceName: String) {
        self.sourceName = sourceName
        let bomStripped = source.hasPrefix("\u{feff}") ? String(source.dropFirst()) : source
        self.chars = Array(bomStripped
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n"))
    }

    private var atEnd: Bool { index >= chars.count }
    private var current: Character? { atEnd ? nil : chars[index] }

    /// Parses the source text into a document.
    ///
    /// Keys given *before* any `[header]` land in the root table. Keys that follow
    /// a `[header]` land in that header's table. Array-of-table headers collect
    /// each subsequent block into a new table appended to an array value.
    public mutating func parse() throws -> TOMLDocument {
        var tables: [String: TOMLTable] = [:]
        var arrayTables: [String: [TOMLValue]] = [:]
        var currentSection: String? = nil
        var currentIsArray = false
        var root = TOMLTable()

        while let ch = current {
            if ch == " " || ch == "\t" || ch == "\n" {
                advance()
            } else if ch == "#" {
                skipComment()
            } else if ch == "[" {
                let (keys, isArray) = try parseHeader()
                if keys.isEmpty {
                    currentSection = nil
                    currentIsArray = false
                } else {
                    let name = keys.joined(separator: ".")
                    if isArray {
                        // TOML 1.0 also forbids redefining a table as an
                        // array-of-tables (or vice versa).
                        guard tables[name] == nil else {
                            throw fail("'\(name)' already defined as a table")
                        }
                        arrayTables[name, default: []].append(.table(TOMLTable()))
                        currentIsArray = true
                    } else {
                        // TOML 1.0: redefining a table is an error, not a
                        // reset. Silently discarding the earlier keys would
                        // make users lose config data invisibly.
                        guard tables[name] == nil, arrayTables[name] == nil else {
                            throw fail("duplicate table '\(name)'")
                        }
                        tables[name] = TOMLTable()
                        currentIsArray = false
                    }
                    currentSection = name
                }
                try expectLineEnd()
            } else {
                let keys = try parseDottedKey()
                skipInlineSpace()
                try expectCharacter("=")
                skipInlineSpace()
                let value = try parseValue()
                try expectLineEnd()

                if let section = currentSection {
                    if currentIsArray {
                        guard var list = arrayTables[section],
                              case .table(let lastTable) = list.last else {
                            throw fail("internal: missing array table")
                        }
                        let updated = try setNested(into: lastTable, keys: keys, value: value)
                        list[list.count - 1] = .table(updated)
                        arrayTables[section] = list
                    } else {
                        var t = tables[section] ?? TOMLTable()
                        t = try setNested(into: t, keys: keys, value: value)
                        tables[section] = t
                    }
                } else {
                    root = try setNested(into: root, keys: keys, value: value)
                }
            }
        }

        // Attach non-root tables into the root as dotted table values.
        for (name, table) in tables {
            root = try attach(tableValue: .table(table), at: name, into: root)
        }
        for (name, list) in arrayTables {
            root = try attach(tableValue: .array(list), at: name, into: root)
        }

        return TOMLDocument(root: root, sourceName: sourceName)
    }

    // MARK: scanning helpers

    private mutating func advance() {
        if index >= chars.count { return }
        if chars[index] == "\n" { line += 1 }
        index += 1
    }

    private mutating func skipInlineSpace() {
        while let c = current, c == " " || c == "\t" { advance() }
    }

    private mutating func skipComment() {
        while let c = current, c != "\n" { advance() }
    }

    private mutating func expectLineEnd() throws {
        skipInlineSpace()
        if let c = current, c == "#" { skipComment() }
        guard current == nil || current == "\n" else {
            throw fail("expected end of line")
        }
        // consume the newline, if present
        if let c = current, c == "\n" { advance() }
    }

    private mutating func expectCharacter(_ expected: Character) throws {
        guard let c = current, c == expected else {
            throw fail("expected '\(expected)'")
        }
        advance()
    }

    // MARK: header & keys

    private mutating func parseHeader() throws -> ([String], isArray: Bool) {
        advance() // consume '['
        var isArray = false
        if current == "[" {
            isArray = true
            advance()
        }
        skipInlineSpace()
        let keys = try parseDottedKey()
        skipInlineSpace()
        try expectCharacter("]")
        if isArray { try expectCharacter("]") }
        return (keys, isArray)
    }

    private mutating func parseDottedKey() throws -> [String] {
        var keys: [String] = []
        keys.append(try parseKey())
        while true {
            skipInlineSpace()
            if current == "." {
                advance()
                skipInlineSpace()
                keys.append(try parseKey())
            } else {
                break
            }
        }
        return keys
    }

    private mutating func parseKey() throws -> String {
        if current == "\"" { return try parseBasicString() }
        if current == "'" { advance(); return try parseLiteralString(terminator: "'") }
        var out = ""
        while let c = current, !" \t\n.=#[]".contains(c) {
            out.append(c)
            advance()
        }
        guard !out.isEmpty else { throw fail("expected key") }
        return out
    }

    // MARK: values

    private mutating func parseValue() throws -> TOMLValue {
        switch current {
        case "\""?:
            return .string(try parseBasicString())
        case "'"?:
            advance()
            return .string(try parseLiteralString(terminator: "'"))
        case "["?:
            return try parseArray()
        case "t"?:
            try expectKeyword("true")
            return .bool(true)
        case "f"?:
            try expectKeyword("false")
            return .bool(false)
        default:
            return try parseNumber()
        }
    }

    private mutating func expectKeyword(_ word: String) throws {
        for ch in word {
            guard current == ch else { throw fail("expected '\(word)'") }
            advance()
        }
    }

    private mutating func parseBasicString() throws -> String {
        advance() // consume opening quote
        var out = ""
        while let c = current {
            if c == "\"" {
                advance()
                return out
            }
            if c == "\\" {
                advance()
                guard let e = current else { throw fail("unterminated escape") }
                advance()
                switch e {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "\\": out.append("\\")
                case "\"": out.append("\"")
                default: throw fail("invalid escape '\\\(e)'")
                }
            } else {
                out.append(c)
                advance()
            }
        }
        throw fail("unterminated string")
    }

    private mutating func parseLiteralString(terminator: Character) throws -> String {
        var out = ""
        while let c = current {
            if c == terminator {
                advance()
                return out
            }
            out.append(c)
            advance()
        }
        throw fail("unterminated literal string")
    }

    private mutating func parseArray() throws -> TOMLValue {
        arrayDepth += 1
        defer { arrayDepth -= 1 }
        guard arrayDepth <= Self.maxArrayDepth else {
            throw fail("arrays nested deeper than \(Self.maxArrayDepth) levels")
        }
        advance() // consume '['
        var items: [TOMLValue] = []
        while true {
            skipInlineSpace()
            if current == nil || current == "\n" { throw fail("unterminated array") }
            if current == "]" {
                advance()
                return .array(items)
            }
            if !items.isEmpty {
                guard current == "," else { throw fail("expected ',' in array") }
                advance()
                skipInlineSpace()
            }
            items.append(try parseValue())
        }
    }

    private mutating func parseNumber() throws -> TOMLValue {
        var token = ""
        while let c = current, c.isNumber || c == "-" || c == "+" || c == "." || c == "_" || c == "e" || c == "E" {
            token.append(c)
            advance()
        }
        let normalized = token.replacingOccurrences(of: "_", with: "")
        if let i = Int64(normalized) {
            return .integer(i)
        }
        if let d = Double(normalized) {
            return .float(d)
        }
        throw fail("unrecognized value '\(token)'")
    }

    // MARK: table assembly

    /// Sets `value` at a dotted `keys` path inside `table`, creating intermediate
    /// tables as needed. Duplicate leaf keys are rejected with a positioned error.
    ///
    /// Deliberately recursive: `TOMLTable` is a value type, so mutating a nested
    /// path means rebuilding every ancestor on the way back up. The recursion
    /// mirrors exactly that — one key at a time, bottom-up.
    private func setNested(into table: TOMLTable, keys: [String], value: TOMLValue) throws -> TOMLTable {
        guard let first = keys.first, !keys.isEmpty else {
            throw fail("empty key path")
        }
        guard keys.count > 1 else {
            var copy = table
            guard copy.value(forKey: first) == nil else {
                throw fail("duplicate key '\(first)'")
            }
            copy.set(value, forKey: first)
            return copy
        }

        var copy = table
        let rest = Array(keys.dropFirst())
        let child: TOMLTable
        if let existing = copy.value(forKey: first), case let .table(t) = existing {
            child = t
        } else {
            child = TOMLTable()
        }
        copy.set(.table(try setNested(into: child, keys: rest, value: value)), forKey: first)
        return copy
    }

    /// Attaches a parsed section (`[header]` or `[[header]]`) value into `root`
    /// under its dotted key path.
    private func attach(tableValue: TOMLValue, at name: String, into root: TOMLTable) throws -> TOMLTable {
        let keys = name.split(separator: ".").map(String.init)
        guard !keys.isEmpty else { return root }
        return try setNested(into: root, keys: keys, value: tableValue)
    }

    private func fail(_ message: String) -> MistError {
        .configParseFailed(field: nil, line: line, message: message)
    }
}