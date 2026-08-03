import Foundation

/// Maps a config `LayoutName` to the engine's concrete `Layout`.
///
/// This is the seam between config and engine: config speaks in raw strings
/// (`LayoutName`), the engine speaks in `Layout` conformance. Keeping the mapping
/// in one place means adding a named layout is a one-line change and nothing
/// downstream cares how the lookup happened.
public func makeLayout(for name: LayoutName) -> any Layout {
    switch name {
    case .bsp: return BSPLayout()
    case .horizontal: return HorizontalLayout()
    case .vertical: return VerticalLayout()
    case .stack: return StackLayout()
    case .monocle: return MonocleLayout()
    case .floating: return FloatingLayout()
    }
}