import AppKit

// Entry point for the Lumen menu-bar app.
//
// LSUIElement=1 in Info.plist keeps it out of the Dock; `.accessory` here is
// the runtime equivalent (belt and suspenders, and correct when launched
// directly from the build tree before the Info.plist takes effect).

let app = NSApplication.shared

guard #available(macOS 12.0, *) else {
    // The UI relies on SwiftUI/AppKit APIs available from macOS 12.
    FileHandle.standardError.write(Data("Lumen requires macOS 12 or later.\n".utf8))
    exit(1)
}

// NSApplication.delegate is weak; hold a strong reference for the app's life.
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
