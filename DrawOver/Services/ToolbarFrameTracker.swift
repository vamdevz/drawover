import AppKit

enum ToolbarFrameTracker {
    private static let lock = NSLock()
    private static var storedFrame: CGRect = .zero

    @MainActor
    static var screenFrame: CGRect {
        lock.lock()
        defer { lock.unlock() }
        return storedFrame
    }

    @MainActor
    static func update(from window: NSWindow?) {
        lock.lock()
        defer { lock.unlock() }
        guard let window, window.isVisible else {
            storedFrame = .zero
            return
        }
        storedFrame = window.frame
    }

    @MainActor
    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        storedFrame = .zero
    }

    @MainActor
    static func contains(screenPoint: NSPoint) -> Bool {
        containsThreadSafe(screenPoint: screenPoint)
    }

    /// Safe to call from the CGEvent tap callback.
    static func containsThreadSafe(screenPoint: NSPoint) -> Bool {
        lock.lock()
        let frame = storedFrame
        lock.unlock()
        guard frame != .zero else { return false }
        return frame.insetBy(dx: -12, dy: -12).contains(screenPoint)
    }
}
