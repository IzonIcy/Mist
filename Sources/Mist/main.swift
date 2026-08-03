import AppKit

// Entry point for the Mist executable target.
//
// Using an explicit `main.swift` (rather than `@main`) reads cleanly for a
// menu-bar app and avoids depending on a Storyboard or nib for launch. The app
// stays resident in the status bar; there is no dock icon by design.

private let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // status-bar app: no Dock icon
app.run()