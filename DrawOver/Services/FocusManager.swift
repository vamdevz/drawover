import AppKit

@MainActor
enum FocusManager {
    /// Return keyboard focus without dismissing overlays or the toolbar.
    static func releaseKeyboard() {
        for window in NSApp.windows where window.isKeyWindow {
            window.resignKey()
        }
    }
}
