# Capturing the Mist demo

The demo shot is a macOS desktop with four windows arranged by Mist in a BSP
layout, plus the menu-bar item open. It has to be taken on a machine where Mist
holds the two TCC grants, so it cannot be produced by a plain CI runner.

## What blocks an automated capture

Mist needs Accessibility to read and move other apps' windows, and Input
Monitoring to receive its hotkeys. macOS attaches both grants to the signed app
the person approved, so a shell that launches `build/Mist.app/Contents/MacOS/Mist`
inherits the trust of whatever spawned it, which is not stable across machines.

The capture attempt on 2026-11-20 ran with AeroSpace holding the same windows.
Two tiling window managers on one desktop means the resulting geometry cannot be
attributed to either one, so the shot was not taken.

## Steps

1. Grant the two permissions. Open System Settings, Privacy & Security, then
   Accessibility and Input Monitoring, and add `/Applications/Mist.app`.
   Quit and relaunch Mist after granting.
2. Stop any other tiling window manager for the duration. AeroSpace and yabai
   both rewrite window frames on the same notifications Mist listens to.
3. Open four ordinary windows: three Finder windows on different folders, and
   one TextEdit document. Leave them where the system puts them.
4. Confirm Mist has tiled them. The menu-bar item's layout should read `bsp`,
   and the four frames should sit edge to edge with an 8pt gap.
5. Capture the whole display, not one window, so the layout is visible:

   ```sh
   screencapture -x docs/images/demo.png
   ```

6. Open the menu-bar item and capture the strip, if the menu is worth showing
   on its own:

   ```sh
   peekaboo see --app Mist --no-elements
   ```

## Placeholder

`docs/images/demo.png` is intentionally absent. The README refers to this file
instead of embedding a shot that does not exist. Replace the reference with the
image once the steps above produce one.
