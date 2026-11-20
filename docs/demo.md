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
4. Confirm Mist has tiled them. The four frames sit edge to edge with an 8pt
   gap. Open the menu-bar item and confirm its first line reads `Accessibility
   Permission: Granted`; that line is the only status the menu carries, and it
   is what proves the grant landed.
5. Capture the whole display, not one window, so the layout is visible:

   ```sh
   screencapture -x docs/images/demo.png
   ```

6. Open the menu-bar item and capture the strip if the permission line is worth
   showing on its own. The menu holds that line, a separator, and Quit, so it is
   only worth a shot when the line reads Granted.

## The video

The same session can produce a sixty second video, and it is the better artifact because presets are a key press and a still cannot show one. Do the screenshot steps first, then record this.

Add two presets to `~/Library/Application Support/Mist/mist.toml` if the example file does not already carry them:

```toml
[[preset]]
name = "write"
bundle_ids = ["com.apple.Safari", "com.apple.Notes"]
hotkey = "cmd+alt+1"
layout = "bsp"

[[preset]]
name = "call"
bundle_ids = ["com.apple.Safari", "com.apple.Notes", "com.apple.mail"]
hotkey = "cmd+alt+2"
```

Leave out any bundle id for an app that is not installed, and expect the log line to name it. The take:

1. **0:00** The desktop with four windows already tiled by Mist.
2. **0:08** Press `cmd+alt+1`. The two windows the preset names tile into a BSP layout and the other two are left where they are.
3. **0:22** Press `cmd+alt+2`. A third window joins and the layout reflows around three.
4. **0:36** Open the menu-bar item so the permission line reads Granted, then close it. The menu carries no layout or preset list, so do not wait for one.
5. **0:48** Edit `mist.toml` in a visible editor, change `[general].gap`, and save. The config hot-reloads and the frames move without a restart. This is the point a still cannot make.

Hold on the reloaded layout. Stop the capture there.

### Seeing the log line

Preset results go to stderr, and a bundled app has nowhere to put stderr, so run the binary from a terminal when you want the line on camera:

```sh
/Applications/Mist.app/Contents/MacOS/Mist
```

The line looks like `Preset 'call' tiled 2 window(s); no window for com.apple.mail`. Running the binary this way inherits the terminal's TCC trust, so grant Accessibility to the terminal as well as to the app if you record this variant. Recording the `.app` on its own and leaving the log out is the simpler take.

### Recording and checking it

Full screen, not one window, because the point is several windows moving:

```sh
screencapture -v -D 1 demo.mov
```

Do not trust the file's duration. Pull frames and check they differ, and that the frame at 45 seconds shows the gap changed:

```sh
for t in 5 15 25 40 50 56; do
    ffmpeg -loglevel error -ss "$t" -i demo.mov -frames:v 1 "frame-$t.png" -y
done
```

```sh
ffmpeg -i demo.mov -c:v libx264 -pix_fmt yuv420p -crf 28 -an demo.mp4
```

Upload it through the GitHub issue composer, paste the `user-attachments` URL on its own line under "Status", and delete the sentence that says there is no recording.

## Placeholder

`docs/images/demo.png` is intentionally absent, and so is `demo.mp4`. The README refers to this file instead of embedding media that does not exist. Replace the reference with the image and the video once the steps above produce them.
