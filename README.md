# Mist

[![CI](https://github.com/IzonIcy/Mist/actions/workflows/ci.yml/badge.svg)](https://github.com/IzonIcy/Mist/actions/workflows/ci.yml)

A tiling window manager for macOS, built from the ground up as a modern, open,
well-typed alternative to yabai / aerospace.

> **Status: wiring landed.** Config schema, layout engine, rules, hotkeys, and
> animations are in. The AX layer is now wired end-to-end: scan → reconcile →
> tile → apply frames to real windows, plus focus. Runtime still needs a GUI +
> Accessibility grant to observe; the pure middleware is unit-verified.

## Why

The existing options are either closed-source, abandoned, or sprawling C.
Mist is:
- **Open source** — still free, still MIT-licensed.
- **Type-safe** — Swift enums/structs instead of stringly-typed config handling.
- **Boring on purpose** — the config is a file, mirrors are explicit, and
  complexity is actively fought.

## Architecture

Two targets:

- **`MistCore`** — all logic, no AppKit. Parses config, computes layout, runs
  the engine, owns the events. Unit-testable headlessly.
- **`Mist`** — the macOS menu-bar app. Owns the accessibility connection and
  renders windows into the grid the engine computes.

Directory layout under `Sources/MistCore/`:

```
Accessibility/  Permission trust + monitor, window discovery (AX scan).
Animations/     Motion curves + reduce-motion support.
Core/           AppCoordinator, EventBus, Logger, MistError.
Configuration/  TOML parser, config loader/mapper, LayoutName.
Displays/       Display model + CG display-frame provider.
Hotkeys/        Hotkey model + parser + conflict-checking manager.
LayoutEngine/   BSP/stack/horizontal/vertical/monocle/floating.
Rules/          Rule, conditions, actions.
WindowManager/  Window model + manager, AX control (move/resize/focus), tiler, geometry.
Workspaces/     Workspace model + layout sharing.
```

## Building

Requirements: macOS 14+, Swift 5.9+, Command Line Tools.

```sh
swift build            # debug
./Scripts/build-app.sh # assembles build/Mist.app (ad-hoc signed)
```

### Tests

`swift test` is the target. Note: running the suite locally currently needs a
full Xcode install (the CLI-only `swift test` lacks the testing backend in some
CLT builds). The logic is verified headlessly via the release of a self-check
harness; restore the suite once a normal toolchain is available.

## Configuration

Config lives at `~/Library/Application Support/Mist/mist.toml` (TOML,
hot-reloaded). See [`Support/mist.toml`](Support/mist.toml) for a commented
example covering layout, gaps, hotkeys, and per-app rules.

## Distribution

Mist ships as a real `.app` bundle (the repo is SwiftPM, no `.xcodeproj`) that
the build script assembles from the compiled binary. Grab it with:

```sh
git clone <repo-url> && cd Mist
./Scripts/build-app.sh --release   # produces build/Mist.app
cp -R build/Mist.app /Applications/
```

No Homebrew, no casks — just clone, build, and drag it into `/Applications`.

Signing: ad-hoc by default. For public distribution set `MIST_SIGNING_IDENTITY`
to a Developer ID and notarize (`codesign --deep --options runtime`).