import Foundation

/// The minimal, immutable facts about a window that rules can match on.
///
/// Kept deliberately small and separate from `WindowManager.Window` so the rules
/// engine is pure and testable: it takes a snapshot, it doesn't reach into a
/// live `AXUIElement`. This is the entire surface a `RuleCondition` sees.
public struct WindowSnapshot: Equatable, Sendable {
    public let appName: String
    public let title: String
    public let bundleID: String
    /// The window's current display identifier, if any.
    public let displayIdentifier: String?

    public init(appName: String, title: String, bundleID: String, displayIdentifier: String? = nil) {
        self.appName = appName
        self.title = title
        self.bundleID = bundleID
        self.displayIdentifier = displayIdentifier
    }
}

/// A condition that a window must satisfy for a rule to fire.
///
/// This is the extension seam: to support a new condition, conform a new type
/// to `RuleCondition` and teach `RuleParser` how to build it. Nothing else in
/// the engine changes. That is the extensibility the charter asks for.
public protocol RuleCondition: Sendable {
    /// Whether `condition(+snapshot)` holds.
    func matches(_ window: WindowSnapshot) -> Bool

    /// Short human description for diagnostics.
    var description: String { get }
}

/// Matches when the app name equals the given value.
public struct AppNameCondition: RuleCondition {
    public let value: String
    public init(value: String) { self.value = value }
    public func matches(_ w: WindowSnapshot) -> Bool { w.appName == value }
    public var description: String { "app == \"\(value)\"" }
}

/// Matches when the title contains the given substring (case-sensitive).
public struct TitleContainsCondition: RuleCondition {
    public let substring: String
    public init(substring: String) { self.substring = substring }
    public func matches(_ w: WindowSnapshot) -> Bool { w.title.contains(substring) }
    public var description: String { "title contains \"\(substring)\"" }
}

/// Matches when the bundle identifier equals the given value.
public struct BundleIDCondition: RuleCondition {
    public let bundleID: String
    public init(bundleID: String) { self.bundleID = bundleID }
    public func matches(_ w: WindowSnapshot) -> Bool { w.bundleID == bundleID }
    public var description: String { "bundleID == \"\(bundleID)\"" }
}

/// The set of things a rule can *do*. Kept small now; the enum is closed so the
/// window manager's application of a matched rule must handle every action.
public enum RuleAction: Equatable, Sendable {
    case float(Bool)
    case alwaysOnTop(Bool)
    case monitor(Int)          // display index (1-based, as in config)
    case workspace(String)     // workspace id to move the window into
    case layout(LayoutName)    // default layout for the target workspace
}

/// A single configuration rule: a condition plus a set of actions.
///
/// Not `Equatable` / `Hashable` because `condition` is an existential
/// (`any RuleCondition`) whose underlying types aren't comparable.
public struct Rule: Sendable {
    /// Free-form comment/label, optional.
    public let name: String?
    /// The (possibly compound) condition.
    public let condition: RuleCondition
    /// Actions to apply when the condition matches.
    public let actions: [RuleAction]

    public init(name: String?, condition: RuleCondition, actions: [RuleAction]) {
        self.name = name
        self.condition = condition
        self.actions = actions
    }

    /// Whether `window` satisfies this rule.
    public func matches(_ window: WindowSnapshot) -> Bool {
        condition.matches(window)
    }
}

/// A closed set of conditions the parser knows how to build.
///
/// The parser in `RuleParser` switches over these tokens; adding a condition type
/// means adding a case here and a branch in the parser.
enum ConditionKind: String {
    case appName = "app"
    case titleContains
    case bundleID
}

/// Evaluates a batch of rules against a window, returning every action produced
/// by matching rules.
public struct RuleEngine {
    private let rules: [Rule]

    public init(rules: [Rule]) {
        self.rules = rules
    }

    /// All actions from every rule that matches `window`, in rule order.
    public func actions(for window: WindowSnapshot) -> [RuleAction] {
        rules.flatMap { rule in
            rule.matches(window) ? rule.actions : []
        }
    }
}