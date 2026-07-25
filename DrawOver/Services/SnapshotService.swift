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
        requestScreenRecordingIfNeeded()

        hideChrome()
        try? await Task.sleep(nanoseconds: 200_000_000)

        let scale = NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor ?? 2.0
        var captured: NSImage?
        var failureReason: String?

        if let image = await captureDisplay(displayID: displayID) {
            captured = image
        } else if let fallback = CGDisplayCreateImage(displayID) {
            captured = NSImage(
                cgImage: fallback,
                size: NSSize(width: fallback.width, height: fallback.height)
            )
        } else {
            failureReason = "Snapshot failed — enable Screen Recording for DrawOver in System Settings → Privacy & Security."
        }

        if let base = captured,
           let composited = compositeAnnotations(
               base: base,
               annotations: annotations,
               displayID: displayID,
               scale: scale
           ) {
            copyToClipboard(composited)
            showFeedback("Snapshot copied to clipboard")
        } else if let reason = failureReason {
            showFeedback(reason, isError: true)
        } else {
            showFeedback("Snapshot failed — could not capture this display.", isError: true)
        }

        restoreChrome()
    }

    private static func requestScreenRecordingIfNeeded() {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
    }

    private static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private static func captureDisplay(displayID: UInt32) async -> NSImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                return nil
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false
            config.capturesAudio = false
            if #available(macOS 14.0, *) {
                config.captureResolution = .best
            }

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
        // Prefer TIFF so Preview / Slack / Notes paste reliably.
        if let tiff = image.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        } else {
            pasteboard.writeObjects([image])
        }
    }

    private static func showFeedback(_ message: String, isError: Bool = false) {
        if isError {
            let alert = NSAlert()
            alert.messageText = "DrawOver"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }

        showToast(message)
    }

    private static func showToast(_ message: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSView(frame: panel.contentView?.bounds ?? .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        container.layer?.cornerRadius = 10

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.frame = container.bounds.insetBy(dx: 12, dy: 10)
        label.autoresizingMask = [.width, .height]
        container.addSubview(label)
        panel.contentView = container

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let origin = NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.minY + 48
            )
            panel.setFrameOrigin(origin)
        }

        panel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            panel.orderOut(nil)
        }
    }
}
