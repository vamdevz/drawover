import AppKit
import Carbon.HIToolbox
import SwiftUI

struct KeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var carbonModifiers: UInt32
    var onRecorded: (() -> Void)?

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onKeyRecorded = { code, mods in
            keyCode = code
            carbonModifiers = mods
            onRecorded?()
        }
        view.currentDisplay = KeyboardShortcut(
            action: .toggleDrawing,
            keyCode: keyCode,
            carbonModifiers: carbonModifiers
        ).displayString
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        nsView.currentDisplay = KeyboardShortcut(
            action: .toggleDrawing,
            keyCode: keyCode,
            carbonModifiers: carbonModifiers
        ).displayString
    }
}

final class KeyRecorderNSView: NSControl {
    var onKeyRecorded: ((UInt32, UInt32) -> Void)?
    var currentDisplay: String = "Click to record" {
        didSet { needsDisplay = true }
    }

    private var isRecording = false
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bg = isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor
        bg.setFill()
        bounds.fill()

        let border = isRecording ? NSColor.controlAccentColor : NSColor.separatorColor
        border.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text = isRecording ? "Press a key…" : currentDisplay
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }

        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        var mods: UInt32 = 0
        if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }

        onKeyRecorded?(UInt32(event.keyCode), mods)
        stopRecording()
    }

    private func startRecording() {
        isRecording = true
        needsDisplay = true
    }

    private func stopRecording() {
        isRecording = false
        needsDisplay = true
    }
}
