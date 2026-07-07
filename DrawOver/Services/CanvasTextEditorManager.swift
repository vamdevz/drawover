import AppKit

/// Manages a single inline text field on the drawing canvas.
@MainActor
final class CanvasTextEditorManager: NSObject {
    private weak var canvas: DrawingCanvasView?
    private var field: NSTextField?
    private var fieldID: UUID?
    private var captionContainerRect: CGRect?
    private var captionFontSize: CGFloat = 16

    var hasOpenEditors: Bool { field != nil }

    init(canvas: DrawingCanvasView) {
        self.canvas = canvas
        super.init()
    }

    func field(at point: CGPoint) -> NSTextField? {
        guard let field, field.frame.contains(point) else { return nil }
        return field
    }

    func placeEditor(at origin: CGPoint, color: NSColor) {
        captionContainerRect = nil
        captionFontSize = 16
        placeEditor(frame: CGRect(x: origin.x, y: origin.y, width: 200, height: 26), color: color)
    }

    /// Compact caption field anchored to the bottom of a shape.
    func placeEditor(in container: CGRect, color: NSColor) {
        captionContainerRect = container
        captionFontSize = 13
        let width: CGFloat = min(max(72, container.width * 0.55), max(container.width, 140))
        let height: CGFloat = 22
        placeEditor(frame: captionFrame(in: container, width: width, height: height), color: color)
    }

    /// Compact caption on an arrow (double-click the line).
    func placeEditor(forArrowAt point: CGPoint, color: NSColor) {
        captionContainerRect = nil
        captionFontSize = 13
        let width: CGFloat = 100
        let height: CGFloat = 22
        let origin = CGPoint(x: point.x - width / 2, y: point.y - height / 2)
        placeEditor(frame: CGRect(x: origin.x, y: origin.y, width: width, height: height), color: color)
    }

    private func placeEditor(frame: CGRect, color: NSColor) {
        guard let canvas else { return }
        if field != nil { commitAll() }

        let editor = NSTextField(frame: frame)
        editor.isBordered = true
        editor.isBezeled = true
        editor.bezelStyle = .roundedBezel
        editor.backgroundColor = .white
        editor.font = .systemFont(ofSize: captionFontSize, weight: .semibold)
        editor.textColor = color
        editor.placeholderString = captionContainerRect == nil ? "Type here…" : "Caption…"
        editor.delegate = self
        editor.focusRingType = .exterior

        let id = UUID()
        editor.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        fieldID = id
        field = editor
        canvas.addSubview(editor)

        focusField(editor)
        canvas.notifyTextEditorsChanged()
    }

    func commitAll() {
        guard let field else { return }
        commit(field: field)
    }

    func discardAll() {
        guard let field else { return }
        captionContainerRect = nil
        remove(field: field)
        canvas?.notifyTextEditorsChanged()
    }

    func focusField(_ editor: NSTextField) {
        guard let canvas, let window = canvas.overlayWindow else { return }
        window.allowsTextEditing = true
        window.makeKey()
        window.makeFirstResponder(editor)
    }

    private func commit(field: NSTextField) {
        guard let canvas, let appState = canvas.appState else { return }

        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let fontSize = captionFontSize
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            let origin: CGPoint
            if let container = captionContainerRect {
                origin = captionTextOrigin(in: container, textSize: size)
            } else {
                origin = field.frame.origin
            }

            appState.addAnnotation(Annotation(kind: .text(
                content: text,
                origin: origin,
                fontSize: fontSize,
                color: appState.nsStrokeColor
            )), displayID: canvas.displayID)
            canvas.needsDisplay = true
        }

        captionContainerRect = nil
        remove(field: field)
        canvas.notifyTextEditorsChanged()
        NotificationCenter.default.post(name: .bringToolbarToFront, object: nil)
    }

    private func remove(field: NSTextField) {
        if field === self.field {
            self.field = nil
            fieldID = nil
        }
        field.delegate = nil
        field.removeFromSuperview()
    }

    private static let shapeCaptionGap: CGFloat = 6

    private func captionFrame(in container: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: container.midX - width / 2,
            y: container.minY - height - Self.shapeCaptionGap,
            width: width,
            height: height
        )
    }

    private func captionTextOrigin(in container: CGRect, textSize: CGSize) -> CGPoint {
        CGPoint(
            x: container.midX - textSize.width / 2,
            y: container.minY - textSize.height - Self.shapeCaptionGap
        )
    }
}

extension CanvasTextEditorManager: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let field = control as? NSTextField else { return false }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commit(field: field)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            if canvas?.appState?.selectedTool == .text {
                canvas?.appState?.stopDrawing()
            } else {
                captionContainerRect = nil
                remove(field: field)
                canvas?.notifyTextEditorsChanged()
                FocusManager.releaseKeyboard()
            }
            return true
        }
        return false
    }
}
