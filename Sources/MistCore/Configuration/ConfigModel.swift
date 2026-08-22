import Foundation

/// The fully-validated configuration model Mist runs on.
///
/// This is the "golden" value type every runtime module consumes. It is separate
/// from the raw TOML tree (`TOMLTable`) so parsing (syntax) and validation
/// (semantics) are two distinct phases — a malformed doc can never be
/// half-applied, because conversion is all-or-nothing.
public struct MistConfig: Sendable {
    /// Values from the `[general]` section.
    public var general: GeneralSettings
    /// Values from the `[hotkeys]` section.
    public var hotkeys: [HotkeyConfiguration]
    /// Values from the `[[rules]]` array-of-tables section.
    public var rules: [Rule]

    public init(general: GeneralSettings = GeneralSettings(),
                hotkeys: [HotkeyConfiguration] = [],
                rules: [Rule] = []) {
        self.general = general
        self.hotkeys = hotkeys
        self.rules = rules
    }
}

/// The `[general]` section.
public struct GeneralSettings: Equatable, Sendable {
    /// Gap (points) around each window inside the layout grid.
    public var gap: Int
    /// Gap (points) between the layout grid and the screen edges.
    public var outerGap: Int
    /// Default layout for new workspaces.
    public var defaultLayout: LayoutName
    /// Whether layout animations are enabled.
    public var animate: Bool
    /// Curve family used when `animate` is true.
    public var animationSpeed: AnimationSpeed
    /// Focus whatever window sits under the cursor as it moves.
    public var focusFollowsMouse: Bool

    public init(gap: Int = 8,
                outerGap: Int = 16,
                defaultLayout: LayoutName = .bsp,
                animate: Bool = true,
                animationSpeed: AnimationSpeed = .spring,
                focusFollowsMouse: Bool = false) {
        self.gap = gap
        self.outerGap = outerGap
        self.defaultLayout = defaultLayout
        self.animate = animate
        self.animationSpeed = animationSpeed
        self.focusFollowsMouse = focusFollowsMouse
    }
}

/// A user-facing layout name from the config (kept dependency-free so the
/// config module need not import the layout engine).
public enum LayoutName: String, CaseIterable, Sendable {
    case bsp
    case horizontal
    case vertical
    case stack
    case monocle
    case floating
}