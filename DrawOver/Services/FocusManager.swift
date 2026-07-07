import AppKit

@MainActor
enum FocusManager {
    /// Return keyboard focus to the previous app without hiding the toolbar.
    static func releaseKeyboard() {
        for window in NSApp.windows where window.isKeyWindow {
            window.resignKey()
        }
    }
}
