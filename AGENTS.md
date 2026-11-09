# Mist

A tiling window manager for macOS. Swift, SwiftPM, no third-party dependencies.

## Targets

- `MistCore` holds all logic and imports no AppKit. Config parsing, layout, the engine, and the event bus live here, which makes them testable headlessly.
- `Mist` is the menu-bar app. It owns the accessibility connection and applies the layout to real windows.

Keep new logic in `MistCore`. If it needs AppKit to run, it belongs in the app target.

## Commands

```sh
swift build                 # debug build
./Scripts/build-app.sh      # assembles build/Mist.app
swift test                  # needs a full Xcode install, not just Command Line Tools
```

## Layout

```
Sources/MistCore/Accessibility/  permission trust, AX scan
Sources/MistCore/Configuration/  TOML parser, loader, mapper
Sources/MistCore/Hotkeys/        hotkey model, parser, conflict manager
Sources/MistCore/LayoutEngine/   BSP, stack, horizontal, vertical, monocle, floating
Sources/MistCore/Rules/          rule model, conditions, actions
Sources/MistCore/Workspaces/     workspace model, layout sharing
Sources/Mist/                    app target
Tests/MistCoreTests/
Support/mist.toml                commented example config
```

## Known limitations

The README status block is the source of truth for what is wired. As of November 2026, the `layout` rule selects the tiling layout and `workspace_1` through `workspace_9` switch workspaces by minimizing windows outside the target. `monitor` and `always_on_top` still do not change the real window. Do not describe those as working.

## Conventions

- Config is validated at parse time and errors are `MistError.invalidConfiguration` with the offending value quoted. A binding that cannot work should fail loudly, not bind and stay silent.
- Pure functions in `MistCore`, side effects at the app boundary.
- Every rule action or hotkey action needs a test in `Tests/MistCoreTests`.

## Verification

`swift build` must pass. For logic changes, add a test and run `swift test` on a toolchain that has the testing backend. For anything that touches the accessibility layer, say plainly that it was not verified headlessly.
