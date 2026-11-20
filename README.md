# Mist

[![CI](https://github.com/IzonIcy/Mist/actions/workflows/ci.yml/badge.svg)](https://github.com/IzonIcy/Mist/actions/workflows/ci.yml)

Mist is a tiling window manager for macOS, written in Swift with no third-party dependencies, for people who would rather read and edit a typed TOML config than debug a shell scripting layer.

There is no screenshot and no recording yet. [docs/demo.md](docs/demo.md) explains what blocks both and the steps that will produce them.

```sh
./Scripts/build-app.sh && cp -R build/Mist.app /Applications/
```

## Status

This section is the source of truth for what is wired.

Scan, reconcile, tile, and apply work against real windows. The `float` rule action applies, and the `focus_left`, `focus_right`, `focus_up`, `focus_down`, and `toggle_float` hotkeys are wired through a CGEventTap. Config hot-reloads live.

The `layout` rule selects the tiling layout. `workspace_1` through `workspace_9` switch workspaces: windows in the target workspace are restored and tiled, windows in other workspaces are minimized, and windows that no workspace claims stay visible everywhere.

Presets work. One hotkey focuses and tiles the windows of a named set of apps and logs the bundle ids that had no window. [Presets](#presets) has the config shape and two examples.

Runtime needs Accessibility and Input Monitoring grants. The logic in `MistCore` is unit-verified without either.

## What it does not do yet

- `monitor` records the display's workspace without moving the real window.
- `always_on_top`, `animate`, and `animation` are rejected at load time, not applied. The accessibility API exposes no window level, so nothing public raises another app's window, and Mist sets each frame in one call, so there is no transition to animate. A config that sets any of them fails with the value quoted.
- `swift test` needs the toolchain's testing plugin. It runs with Command Line Tools on this machine, but a stale SwiftPM cache can make the plugin fail to load; `rm -rf .build ~/Library/Caches/org.swift.swiftpm` clears it.

## Compared with yabai and AeroSpace

yabai and AeroSpace are the obvious alternatives, and both are more mature. They have shipped for years and they cover more window and configuration behavior than Mist does. If you need that coverage today, use one of them. What Mist offers instead is a smaller thing: one TOML file at a fixed path, layouts as pure functions that run in tests without a window server, and a codebase small enough to read in full when something goes wrong.

## Configuration

Config lives at `~/Library/Application Support/Mist/mist.toml` and hot-reloads when you edit it. [`Support/mist.toml`](Support/mist.toml) is a commented example covering layout, gaps, hotkeys, per-app rules, and presets.

Validation happens at parse time. A bad value fails with `MistError.invalidConfiguration` and the offending value quoted, so a binding that cannot work never binds silently.

### Layouts

Six layouts: `bsp`, `stack`, `horizontal`, `vertical`, `monocle`, and `floating`. Set the default with `layout` in the `[general]` table or per workspace with a `layout` rule.

### Rules

Rules match on app name, window title substring, or bundle ID, and the conditions within one rule are AND-ed. Actions are `float`, `monitor`, `workspace`, and `layout`. The status section above says which of those change real windows.

### Presets

A preset is a named set of apps you can put back on screen with one key. It focuses and tiles the windows of every running app whose bundle id it lists, in the order the ids appear, in the preset's layout. It then logs the bundle ids that had no window.

```toml
[[preset]]
name = "coding"
bundle_ids = ["com.mitchellh.ghostty", "com.apple.dt.Xcode", "com.apple.Safari"]
layout = "bsp"
hotkey = "cmd+alt+1"

[[preset]]
name = "call"
bundle_ids = ["us.zoom.xos", "com.tinyspeck.slackmacgap", "com.apple.Notes"]
layout = "vertical"
hotkey = "cmd+alt+2"
```

`name` and `bundle_ids` are required, `layout` defaults to `[general].layout`, and `hotkey` is optional. A preset hotkey cannot duplicate any other binding. A preset with no name, no bundle ids, an unknown layout, or a hotkey that does not parse fails the config load with the value quoted.

Applying a preset rescans the running windows, tiles the ones it names, and writes one info line to the log. That line is the report, and it names the missing apps, for example `Preset 'call' tiled 2 window(s); no window for com.apple.Notes`. There is no settings UI, so the log is where that lands.

## Architecture

Two targets in one Swift package:

- `MistCore` holds all logic and imports no AppKit. Config parsing, layout, the engine, and the event bus live here, which makes them testable headlessly.
- `Mist` is the menu-bar app. It owns the accessibility connection and applies the computed layout to real windows.

Keep new logic in `MistCore`. If it needs AppKit to run, it belongs in the app target.

```
Sources/MistCore/Accessibility/  Permission trust, window discovery (AX scan)
Sources/MistCore/Configuration/  TOML parser, config loader and mapper
Sources/MistCore/Core/           AppCoordinator, EventBus, Logger, MistError
Sources/MistCore/Displays/       Display model, CG display-frame provider
Sources/MistCore/Hotkeys/        Hotkey model, parser, conflict manager
Sources/MistCore/LayoutEngine/   BSP, stack, horizontal, vertical, monocle, floating
Sources/MistCore/Presets/        Preset model, parser, window planner
Sources/MistCore/Rules/          Rule model, conditions, actions
Sources/MistCore/WindowManager/  Window model, AX move/resize/focus, tiler, geometry
Sources/MistCore/Workspaces/     Workspace model, layout sharing
Sources/Mist/                    App target
Tests/MistCoreTests/
Support/mist.toml                Commented example config
```

A layout is a pure function: same items, rect, and config in, same frames out. That purity is what makes the engine testable and a new layout a self-contained conformance to `Layout`.

## Building

Requirements: macOS 14 or later, and a Swift 6 toolchain (the package declares tools version 6.0). `swift build` works with Command Line Tools alone.

```sh
swift build            # debug build
./Scripts/build-app.sh # assembles build/Mist.app, ad-hoc signed
```

`swift test` needs a full Xcode install. The CLI-only toolchain lacks the testing backend in some builds.

## Distribution

Mist ships as a real `.app` bundle. The repo is SwiftPM with no `.xcodeproj`, so the build script assembles the bundle from the compiled binary.

```sh
git clone <repo-url> && cd Mist
./Scripts/build-app.sh --release   # produces build/Mist.app
cp -R build/Mist.app /Applications/
```

No Homebrew and no casks. Clone, build, and copy it into `/Applications`.

The bundle is ad-hoc signed by default. For public distribution, set `MIST_SIGNING_IDENTITY` to a Developer ID and notarize with `codesign --deep --options runtime`.

MIT licensed.
