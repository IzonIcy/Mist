import Foundation

/// Loads and validates Mist's configuration from a TOML file.
///
/// Responsibilities, in order: read the file, delegate syntax parsing to
/// `TOMLParser`, map the resulting tree into a `MistConfig`, and semantically
/// validate it. Each stage throws a `MistError` that says exactly what and where
/// so the UI / log can present a helpful message instead of a crash.
public struct ConfigLoader {
    /// Default config filename under the user's config directory.
    public static let defaultFileName = "mist.toml"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// The default config URL, e.g. `~/.config/mist/mist.toml`.
    public func defaultConfigURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("Mist").appendingPathComponent(Self.defaultFileName)
    }

    /// Loads configuration from a file at `url`.
    ///
    /// - Throws: `MistError.readFailed` if the file can't be read,
    ///   `MistError.configParseFailed` if the TOML is invalid, or
    ///   `MistError.invalidConfiguration` if it doesn't validate.
    public func load(from url: URL) throws -> MistConfig {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MistError.readFailed(path: url.path, underlying: error)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw MistError.invalidConfiguration("config is not valid UTF-8")
        }
        return try parse(text: text, sourceName: url.path)
    }

    /// Parses and validates configuration from raw `text`.
    public func parse(text: String, sourceName: String = "<memory>") throws -> MistConfig {
        var parser = TOMLParser(source: text, sourceName: sourceName)
        let document = try parser.parse()
        return try ConfigMapper(document: document).map()
    }
}

/// Converts a parsed `TOMLDocument` into a validated `MistConfig`.
private struct ConfigMapper {
    let document: TOMLDocument

    func map() throws -> MistConfig {
        let root = document.root
        return MistConfig(
            general: try mapGeneral(root.value(forKey: "general")),
            hotkeys: try mapHotkeys(root.value(forKey: "hotkeys")),
            rules: try mapRules(root.value(forKey: "rules"))
        )
    }

    func mapGeneral(_ raw: TOMLValue?) throws -> GeneralSettings {
        guard let raw else { return GeneralSettings() }
        guard case let .table(t) = raw else {
            throw MistError.invalidConfiguration("'general' must be a table")
        }
        return GeneralSettings(
            gap: clampNonNegative(t.integer(forKey: "gap")),
            outerGap: clampNonNegative(t.integer(forKey: "outer_gap")),
            defaultLayout: try mapLayout(t.string(forKey: "layout")),
            animate: t.bool(forKey: "animate") ?? true,
            animationSpeed: mapSpeed(t.string(forKey: "animation"))
        )
    }

    func mapLayout(_ raw: String?) throws -> LayoutName {
        guard let raw else { return .bsp }
        guard let name = LayoutName(rawValue: raw) else {
            throw MistError.invalidConfiguration(
                "unknown layout '\(raw)' (expected one of \(LayoutName.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        return name
    }

    func mapSpeed(_ raw: String?) -> AnimationSpeed {
        if let raw, let style = AnimationSpeed(rawValue: raw) {
            return style
        }
        return .spring
    }

    func mapHotkeys(_ raw: TOMLValue?) throws -> [HotkeyConfiguration] {
        guard let raw else { return [] }
        guard case let .table(t) = raw else {
            throw MistError.invalidConfiguration("'hotkeys' must be a table")
        }
        return try HotkeyConfigurationParser(table: t).parse()
    }

    func mapRules(_ raw: TOMLValue?) throws -> [Rule] {
        guard let raw else { return [] }
        guard case let .array(items) = raw else {
            throw MistError.invalidConfiguration("'rules' must be an array of tables")
        }
        var rules: [Rule] = []
        for item in items {
            guard case let .table(t) = item else {
                throw MistError.invalidConfiguration("each rule must be a table")
            }
            rules.append(try RuleParser(table: t).parse())
        }
        return rules
    }
}

/// Clamp a configured integer gap to `>= 0`; defaults to 8 when absent.
private func clampNonNegative(_ raw: Int64?) -> Int {
    guard let raw else { return 8 }
    return max(0, Int(raw))
}

private extension MistError {
    static func invalid(_ message: String) -> MistError { .invalidConfiguration(message) }
}