import AppKit

/// Manages a single inline text field on the drawing canvas.
@MainActor
final class CanvasTextEditorManager: NSObject {
    private weak var canvas: DrawingCanvasView?
    private var field: NSTextField?
    private var fieldID: UUID?
    private var captionContainerRect: CGRect?
    private var captionArrowAnchor: (from: CGPoint, to: CGPoint)?
    private var captionFontSize: CGFloat = 16

    private static let shapeCaptionGap: CGFloat = 4
    private static let captionHeight: CGFloat = 18
    private static let captionFont: CGFloat = 11

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
        captionArrowAnchor = nil
        captionFontSize = 16
        placeEditor(frame: CGRect(x: origin.x, y: origin.y, width: 200, height: 26), color: color)
    }

    /// Small caption field anchored below a rectangle or ellipse.
    func placeEditor(in container: CGRect, color: NSColor) {
        captionContainerRect = container
        captionArrowAnchor = nil
        captionFontSize = Self.captionFont
        let width = min(76, max(52, container.width * 0.38))
        placeEditor(frame: captionFrameBelow(container, width: width, height: Self.captionHeight), color: color)
    }

    /// Small caption below an arrow line (double-click the arrow).
    func placeEditor(forArrowFrom from: CGPoint, to: CGPoint, color: NSColor) {
        captionContainerRect = nil
        captionArrowAnchor = (from, to)
        captionFontSize = Self.captionFont
        let width: CGFloat = 68
        placeEditor(frame: captionFrameBelowArrow(from: from, to: to, width: width, height: Self.captionHeight), color: color)
    }

    private func placeEditor(frame: CGRect, color: NSColor) {
        guard let canvas else { return }
        if field != nil { commitAll() }

        let editor = NSTextField(frame: frame)
        editor.isBordered = true
        editor.isBezeled = true
        editor.bezelStyle = .roundedBezel
        editor.backgroundColor = .white
        editor.font = .systemFont(ofSize: captionFontSize, weight: .medium)
        editor.textColor = color
        editor.placeholderString = captionContainerRect != nil || captionArrowAnchor != nil ? "Caption…" : "Type here…"
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
        captionArrowAnchor = nil
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
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium)
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            let origin: CGPoint
            if let container = captionContainerRect {
                origin = captionTextOriginBelow(container, textSize: size)
            } else if let anchor = captionArrowAnchor {
                origin = captionTextOriginBelowArrow(from: anchor.from, to: anchor.to, textSize: size)
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
        captionArrowAnchor = nil
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

    /// Flipped view: maxY is the bottom edge of a shape.
    private func captionFrameBelow(_ container: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: container.midX - width / 2,
            y: container.maxY + Self.shapeCaptionGap,
            width: width,
            height: height
        )
    }

    private func captionTextOriginBelow(_ container: CGRect, textSize: CGSize) -> CGPoint {
        CGPoint(
            x: container.midX - textSize.width / 2,
            y: container.maxY + Self.shapeCaptionGap
        )
    }

    private func captionFrameBelowArrow(from: CGPoint, to: CGPoint, width: CGFloat, height: CGFloat) -> CGRect {
        let anchor = arrowCaptionAnchor(from: from, to: to)
        return CGRect(
            x: anchor.x - width / 2,
            y: anchor.y + Self.shapeCaptionGap,
            width: width,
            height: height
        )
    }

    private func captionTextOriginBelowArrow(from: CGPoint, to: CGPoint, textSize: CGSize) -> CGPoint {
        let anchor = arrowCaptionAnchor(from: from, to: to)
        return CGPoint(
            x: anchor.x - textSize.width / 2,
            y: anchor.y + Self.shapeCaptionGap
        )
    }

    /// Lowest point on the arrow segment (flipped coords: larger Y = lower on screen).
    private func arrowCaptionAnchor(from: CGPoint, to: CGPoint) -> CGPoint {
        if from.y == to.y {
            return CGPoint(x: (from.x + to.x) / 2, y: from.y)
        }
        if from.y >= to.y {
            return from
        }
        return to
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
            captionContainerRect = nil
            captionArrowAnchor = nil
            remove(field: field)
            canvas?.notifyTextEditorsChanged()
            FocusManager.releaseKeyboard()
            return true
        }
        return false
    }
}
