import AppKit

@MainActor
enum ToolbarFrameTracker {
    private(set) static var screenFrame: CGRect = .zero

    static func update(from window: NSWindow?) {
        guard let window, window.isVisible else {
            screenFrame = .zero
            return
        }
        screenFrame = window.frame
    }

    static func contains(screenPoint: NSPoint) -> Bool {
        guard screenFrame != .zero else { return false }
        return screenFrame.insetBy(dx: -12, dy: -12).contains(screenPoint)
    }
}
