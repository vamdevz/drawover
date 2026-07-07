import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
enum SnapshotService {
    static func preferredDisplayID(lastActive: UInt32?) -> UInt32 {
        if let lastActive,
           NSScreen.screens.contains(where: { $0.displayID == lastActive }) {
            return lastActive
        }

        if let mouseScreen = screen(containing: NSEvent.mouseLocation) {
            return mouseScreen.displayID
        }

        if ToolbarFrameTracker.screenFrame != .zero {
            let center = NSPoint(
                x: ToolbarFrameTracker.screenFrame.midX,
                y: ToolbarFrameTracker.screenFrame.midY
            )
            if let toolbarScreen = screen(containing: center) {
                return toolbarScreen.displayID
            }
        }

        return CGMainDisplayID()
    }

    static func captureFullScreen(
        displayID: UInt32,
        annotations: [Annotation],
        hideChrome: () -> Void,
        restoreChrome: () -> Void
    ) async {
        hideChrome()
        try? await Task.sleep(nanoseconds: 150_000_000)

        let scale = NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor ?? 2.0

        if let base = await captureDisplay(displayID: displayID),
           let composited = compositeAnnotations(
               base: base,
               annotations: annotations,
               displayID: displayID,
               scale: scale
           ) {
            copyToClipboard(composited)
            showToast("Snapshot copied to clipboard")
        } else if let fallback = CGDisplayCreateImage(displayID),
                  let composited = compositeAnnotations(
                      base: NSImage(cgImage: fallback, size: NSSize(width: fallback.width, height: fallback.height)),
                      annotations: annotations,
                      displayID: displayID,
                      scale: scale
                  ) {
            copyToClipboard(composited)
            showToast("Snapshot copied to clipboard")
        } else {
            showToast("Snapshot failed — grant Screen Recording permission")
        }

        restoreChrome()
    }

    private static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private static func captureDisplay(displayID: UInt32) async -> NSImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                return nil
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = true
            config.captureResolution = .best

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } catch {
            return nil
        }
    }

    private static func compositeAnnotations(
        base: NSImage,
        annotations: [Annotation],
        displayID: UInt32,
        scale: CGFloat
    ) -> NSImage? {
        var proposed = NSRect(origin: .zero, size: base.size)
        guard let cgBase = base.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return nil
        }

        let screenAnnotations = annotations.filter { $0.displayID == displayID }
        guard !screenAnnotations.isEmpty else { return base }

        let pixelWidth = cgBase.width
        let pixelHeight = cgBase.height
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return base }

        context.draw(cgBase, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        let pointHeight = CGFloat(pixelHeight) / scale
        context.translateBy(x: 0, y: pointHeight)
        context.scaleBy(x: 1, y: -1)

        for annotation in screenAnnotations {
            annotation.kind.draw(in: context)
        }
        context.restoreGState()

        guard let output = context.makeImage() else { return base }
        return NSImage(cgImage: output, size: base.size)
    }

    private static func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private static func showToast(_ message: String) {
        let notification = NSUserNotification()
        notification.title = "DrawOver"
        notification.informativeText = message
        notification.soundName = nil
        NSUserNotificationCenter.default.deliver(notification)
    }
}
