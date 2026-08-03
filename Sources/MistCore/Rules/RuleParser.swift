import Foundation

/// Builds a `Rule` from a parsed `[[rules]]` TOML table.
///
/// Expected shape:
/// ```toml
/// [[rules]]
/// name = "Float Safari"          # optional
/// [rules.window]
/// app = "Safari"                 # any of app / title_contains / bundle_id
/// title_contains = "Picture-in-Picture"
/// float = true                   # action fields
/// always_on_top = true
/// monitor = 2
/// workspace = "main"
/// layout = "bsp"
/// ```
///
/// Conditions are AND-ed together when more than one is present. This is the
/// only place that knows how a config table becomes a `Rule`; the engine itself
/// is untouched when new conditions/actions are added.
struct RuleParser {
    let table: TOMLTable

    func parse() throws -> Rule {
        let name = table.string(forKey: "name")
        let conditions = Self.extractConditions(from: table)

        guard !conditions.isEmpty else {
            throw MistError.invalidConfiguration("rule \(name ?? "<unnamed>") has no condition")
        }

        // Actions
        var actions: [RuleAction] = []
        if let b = table.bool(forKey: "float") {
            actions.append(.float(b))
        }
        if let b = table.bool(forKey: "always_on_top") {
            actions.append(.alwaysOnTop(b))
        }
        if let m = table.integer(forKey: "monitor") {
            actions.append(.monitor(Int(m)))
        }
        if let ws = table.string(forKey: "workspace") {
            actions.append(.workspace(ws))
        }
        if let layout = table.string(forKey: "layout"), let layoutName = LayoutName(rawValue: layout) {
            actions.append(.layout(layoutName))
        }

        guard !actions.isEmpty else {
            throw MistError.invalidConfiguration("rule '\(name ?? "<unnamed>")' has no action")
        }

        return Rule(name: name, condition: CompoundCondition(conditions: conditions), actions: actions)
    }

    /// Reads conditions from the parsed rule table.
    ///
    /// Accepts two equivalent inscriptions so the config stays friendly:
    ///   nested  → `[rules.window]` + `app` / `title_contains` / `bundle_id`
    ///   flat    → `window_app` / `window_title_contains` / `window_bundle_id`
    private static func extractConditions(from table: TOMLTable) -> [RuleCondition] {
        var conditions: [RuleCondition] = []

        // Nested form: [rules.window] { app = ..., title_contains = ..., bundle_id = ... }
        if case let .table(w)? = table.value(forKey: "window") {
            if let app = w.string(forKey: "app") {
                conditions.append(AppNameCondition(value: app))
            }
            if let title = w.string(forKey: "title_contains") {
                conditions.append(TitleContainsCondition(substring: title))
            }
            if let bundle = w.string(forKey: "bundle_id") {
                conditions.append(BundleIDCondition(bundleID: bundle))
            }
        }

        // Flat form: window_app = "Safari", window_title_contains = "...", ...
        if let app = table.string(forKey: "window_app") {
            conditions.append(AppNameCondition(value: app))
        }
        if let title = table.string(forKey: "window_title_contains") {
            conditions.append(TitleContainsCondition(substring: title))
        }
        if let bundle = table.string(forKey: "window_bundle_id") {
            conditions.append(BundleIDCondition(bundleID: bundle))
        }

        return conditions
    }
}

/// AND-composes multiple conditions.
struct CompoundCondition: RuleCondition {
    let conditions: [RuleCondition]
    func matches(_ w: WindowSnapshot) -> Bool {
        conditions.allSatisfy { $0.matches(w) }
    }
    var description: String {
        conditions.map(\.description).joined(separator: " && ")
    }
}