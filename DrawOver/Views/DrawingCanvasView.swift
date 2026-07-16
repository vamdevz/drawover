import AppKit

final class DrawingCanvasView: NSView {
    var appState: AppState?
    var displayID: UInt32 = 0
    var screenFrame: CGRect = .zero
    weak var overlayWindow: OverlayWindow?

    private var currentPoints: [CGPoint] = []
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private lazy var textEditors = CanvasTextEditorManager(canvas: self)
    private var draggingTextID: UUID?
    private var textDragOffset: CGPoint = .zero
    private var draggingField: NSTextField?
    private var pendingFieldFocus: NSTextField?
    private var pendingDragStart: CGPoint = .zero
    private var fieldDragOffset: CGPoint = .zero

    private var pendingTextDragID: UUID?
    private var pendingTextDragStart: CGPoint = .zero

    private enum ShapeDragMode {
        case box
        case arrow
    }

    private var shapeDragMode: ShapeDragMode = .box
    private var arrowAnchorRect: CGRect?

    var hasOpenTextEditors: Bool { textEditors.hasOpenEditors }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }

        // Canvas owns caption interactions (text tool, shape caption, or caption drag).
        if handlesCaptionInput || shapeToolCaptures(point: point), appState?.isDrawingModeActive == true {
            return self
        }

        for subview in subviews.reversed() {
            let local = convert(point, to: subview)
            if let hit = subview.hitTest(local) {
                return hit
            }
        }
        return self
    }

    private var handlesCaptionInput: Bool {
        guard let appState else { return false }
        if appState.selectedTool == .text { return true }
        if textEditors.hasOpenEditors { return true }
        return false
    }

    private var isShapeToolActive: Bool {
        guard let tool = appState?.selectedTool else { return false }
        return tool == .rectangle || tool == .ellipse
    }

    private func shapeToolCaptures(point: CGPoint) -> Bool {
        isShapeToolActive && textAnnotation(at: point, generous: true) != nil
    }

    override func mouseDown(with event: NSEvent) {
        guard appState?.isDrawingModeActive == true else { return }
        appState?.markDisplayActive(displayID)
        if ToolbarFrameTracker.contains(screenPoint: NSEvent.mouseLocation) { return }

        let point = convert(event.locationInWindow, from: nil)

        if event.modifierFlags.contains(.option), isShapeToolActive {
            if deleteAnnotationAtPoint(point) { return }
        }

        if event.clickCount == 2 {
            if textEditors.hasOpenEditors { textEditors.commitAll() }
            let color = appState?.nsStrokeColor ?? .red
            if let container = shapeAnnotationRect(at: point) {
                textEditors.placeEditor(in: container, color: color)
                return
            }
            if let arrow = arrowAnnotation(at: point),
               case let .arrow(from, to, _, _) = arrow.kind {
                textEditors.placeEditor(forArrowFrom: from, to: to, color: color)
                return
            }
        }

        if handlesCaptionInput {
            handleCaptionMouseDown(at: point)
            return
        }

        if isShapeToolActive, let annotation = textAnnotation(at: point, generous: true) {
            beginPendingTextDrag(annotation: annotation, at: point)
            return
        }

        performMouseDown(at: point)
    }

    private func beginPendingTextDrag(annotation: Annotation, at point: CGPoint) {
        guard case let .text(_, origin, _, _) = annotation.kind else { return }
        pendingTextDragID = annotation.id
        pendingTextDragStart = point
        textDragOffset = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    private func handleCaptionMouseDown(at point: CGPoint) {
        if let field = textEditors.field(at: point) {
            pendingFieldFocus = field
            pendingDragStart = point
            fieldDragOffset = CGPoint(x: point.x - field.frame.origin.x, y: point.y - field.frame.origin.y)
            return
        }

        if let annotation = textAnnotation(at: point) {
            beginDraggingText(annotation: annotation, at: point)
            return
        }

        if textEditors.hasOpenEditors {
            textEditors.commitAll()
            return
        }

        guard appState?.selectedTool == .text else { return }
        textEditors.placeEditor(at: point, color: appState?.nsStrokeColor ?? .red)
    }

    override func mouseDragged(with event: NSEvent) {
        guard appState?.isDrawingModeActive == true else { return }
        let point = convert(event.locationInWindow, from: nil)

        if let id = draggingTextID {
            appState?.updateTextAnnotation(
                id: id,
                origin: CGPoint(x: point.x - textDragOffset.x, y: point.y - textDragOffset.y)
            )
            needsDisplay = true
            return
        }

        if let field = draggingField {
            field.setFrameOrigin(CGPoint(x: point.x - fieldDragOffset.x, y: point.y - fieldDragOffset.y))
            return
        }

        if let field = pendingFieldFocus {
            if distance(point, pendingDragStart) > 4 {
                overlayWindow?.makeFirstResponder(nil)
                draggingField = field
                pendingFieldFocus = nil
                field.setFrameOrigin(CGPoint(x: point.x - fieldDragOffset.x, y: point.y - fieldDragOffset.y))
            }
            return
        }

        if let pendingID = pendingTextDragID {
            if draggingTextID == nil, distance(point, pendingTextDragStart) > 4 {
                appState?.beginUndoableChange()
                draggingTextID = pendingID
                pendingTextDragID = nil
            }
            if let id = draggingTextID {
                appState?.updateTextAnnotation(
                    id: id,
                    origin: CGPoint(x: point.x - textDragOffset.x, y: point.y - textDragOffset.y)
                )
                needsDisplay = true
            }
            return
        }

        guard !handlesCaptionInput else { return }
        performMouseDragged(at: point)
    }

    override func mouseUp(with event: NSEvent) {
        guard appState?.isDrawingModeActive == true else { return }
        let point = convert(event.locationInWindow, from: nil)

        if draggingTextID != nil {
            draggingTextID = nil
            NotificationCenter.default.post(name: .bringToolbarToFront, object: nil)
            return
        }

        if pendingTextDragID != nil {
            pendingTextDragID = nil
            return
        }

        if draggingField != nil {
            draggingField = nil
            NotificationCenter.default.post(name: .bringToolbarToFront, object: nil)
            return
        }

        if let field = pendingFieldFocus {
            textEditors.focusField(field)
            pendingFieldFocus = nil
            return
        }

        guard !handlesCaptionInput else { return }
        performMouseUp(at: point)
        NotificationCenter.default.post(name: .bringToolbarToFront, object: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        guard appState?.isDrawingModeActive == true else {
            context.clear(dirtyRect)
            return
        }

        drawSpotlightMask(in: context)

        for annotation in screenAnnotations {
            annotation.kind.draw(in: context)
        }

        if let start = dragStart, let current = dragCurrent {
            if isShapeToolActive, shapeDragMode == .arrow {
                drawArrowPreview(from: arrowStart(toward: current), to: current, in: context)
            } else if let tool = appState?.selectedTool {
                drawPreview(tool: tool, start: start, current: current, in: context)
            }
        }
    }

    func cancelInteraction() {
        dragStart = nil
        dragCurrent = nil
        currentPoints = []
        draggingTextID = nil
        pendingTextDragID = nil
        draggingField = nil
        pendingFieldFocus = nil
        shapeDragMode = .box
        arrowAnchorRect = nil
        needsDisplay = true
    }

    func commitAllTextEditors() {
        textEditors.commitAll()
        notifyTextEditorsChanged()
    }

    func discardAllTextEditors() {
        textEditors.discardAll()
        notifyTextEditorsChanged()
    }

    func notifyTextEditorsChanged() {
        NotificationCenter.default.post(name: .textEditorsChanged, object: self)
        syncOverlayKeyState()
    }

    func syncOverlayKeyState() {
        let editing = textEditors.hasOpenEditors
        overlayWindow?.allowsTextEditing = editing
        if !editing {
            FocusManager.releaseKeyboard()
        }
    }

    private var screenAnnotations: [Annotation] {
        (appState?.annotations ?? []).filter { $0.displayID == displayID }
    }

    private func drawSpotlightMask(in context: CGContext) {
        let spotlights = screenAnnotations.compactMap { annotation -> CGRect? in
            if case let .spotlight(rect, _, dimOpacity) = annotation.kind {
                _ = dimOpacity
                return rect
            }
            return nil
        }

        guard !spotlights.isEmpty else { return }

        let dimOpacity = appState?.spotlightDimOpacity ?? 0.55
        context.setFillColor(NSColor.black.withAlphaComponent(dimOpacity).cgColor)

        var path = CGMutablePath()
        path.addRect(bounds)
        for rect in spotlights {
            path.addRoundedRect(in: rect, cornerWidth: 12, cornerHeight: 12)
        }
        context.addPath(path)
        context.fillPath(using: .evenOdd)
    }

    private func drawArrowPreview(from: CGPoint, to: CGPoint, in context: CGContext) {
        let color = appState?.nsStrokeColor ?? .red
        let width = appState?.lineWidth ?? 3
        AnnotationKind.arrow(from: from, to: to, lineWidth: width, color: color).draw(in: context)
    }

    private func drawPreview(tool: DrawingTool, start: CGPoint, current: CGPoint, in context: CGContext) {
        let color = appState?.nsStrokeColor ?? .red
        let width = appState?.lineWidth ?? 3

        switch tool {
        case .pen, .highlighter:
            if currentPoints.count > 1 {
                let kind = AnnotationKind.stroke(
                    points: currentPoints,
                    lineWidth: width,
                    color: color,
                    opacity: tool == .highlighter ? 0.35 : 1,
                    isHighlighter: tool == .highlighter
                )
                kind.draw(in: context)
            }
        case .arrow:
            AnnotationKind.arrow(from: start, to: current, lineWidth: width, color: color).draw(in: context)
        case .rectangle:
            AnnotationKind.rectangle(rect: rectFrom(start, current), lineWidth: width, color: color, filled: false).draw(in: context)
        case .ellipse:
            AnnotationKind.ellipse(rect: rectFrom(start, current), lineWidth: width, color: color, filled: false).draw(in: context)
        default:
            break
        }
    }

    private func performMouseDown(at point: CGPoint) {
        if isShapeToolActive {
            if NSEvent.modifierFlags.contains(.control) {
                shapeDragMode = .arrow
                if let shape = shapeAnnotation(at: point), let rect = boundsForShape(shape) {
                    arrowAnchorRect = rect
                } else {
                    arrowAnchorRect = nil
                }
                dragStart = point
                dragCurrent = point
                return
            }

            shapeDragMode = .box
            arrowAnchorRect = nil
            if shapeAnnotation(at: point) != nil {
                return
            }
        }

        switch appState?.selectedTool {
        case .eraser:
            eraseNear(point)
        default:
            dragStart = point
            dragCurrent = point
            currentPoints = [point]
        }
    }

    private func performMouseDragged(at point: CGPoint) {
        dragCurrent = point

        if appState?.selectedTool == .pen || appState?.selectedTool == .highlighter {
            currentPoints.append(point)
        }

        if appState?.selectedTool == .eraser {
            eraseNear(point)
        }

        needsDisplay = true
    }

    private func performMouseUp(at point: CGPoint) {
        guard let tool = appState?.selectedTool, let start = dragStart else { return }

        let color = appState?.nsStrokeColor ?? .red
        let width = appState?.lineWidth ?? 3

        switch tool {
        case .pen:
            if currentPoints.count > 1 {
                appState?.addAnnotation(Annotation(kind: .stroke(
                    points: currentPoints, lineWidth: width, color: color, opacity: 1, isHighlighter: false
                )), displayID: displayID)
            }
        case .highlighter:
            if currentPoints.count > 1 {
                appState?.addAnnotation(Annotation(kind: .stroke(
                    points: currentPoints, lineWidth: width, color: color, opacity: 0.35, isHighlighter: true
                )), displayID: displayID)
            }
        case .arrow:
            if distance(start, point) > 4 {
                appState?.addAnnotation(Annotation(kind: .arrow(from: start, to: point, lineWidth: width, color: color)), displayID: displayID)
            }
        case .rectangle:
            if shapeDragMode == .arrow {
                let from = arrowStart(toward: point)
                if distance(from, point) > 4 {
                    appState?.addAnnotation(Annotation(kind: .arrow(from: from, to: point, lineWidth: width, color: color)), displayID: displayID)
                }
            } else {
                let rect = rectFrom(start, point)
                if rect.width > 2, rect.height > 2 {
                    appState?.addAnnotation(Annotation(kind: .rectangle(rect: rect, lineWidth: width, color: color, filled: false)), displayID: displayID)
                }
            }
        case .ellipse:
            if shapeDragMode == .arrow {
                let from = arrowStart(toward: point)
                if distance(from, point) > 4 {
                    appState?.addAnnotation(Annotation(kind: .arrow(from: from, to: point, lineWidth: width, color: color)), displayID: displayID)
                }
            } else {
                let rect = rectFrom(start, point)
                if rect.width > 2, rect.height > 2 {
                    appState?.addAnnotation(Annotation(kind: .ellipse(rect: rect, lineWidth: width, color: color, filled: false)), displayID: displayID)
                }
            }
        default:
            break
        }

        dragStart = nil
        dragCurrent = nil
        currentPoints = []
        shapeDragMode = .box
        arrowAnchorRect = nil
        needsDisplay = true
    }

    private func eraseNear(_ point: CGPoint) {
        guard let state = appState else { return }
        let threshold = state.lineWidth

        let remaining = state.annotations.filter { annotation in
            guard annotation.displayID == displayID else { return true }
            return !annotationIntersects(annotation, point: point, threshold: threshold)
        }

        if remaining.count != state.annotations.count {
            state.annotations = remaining
            needsDisplay = true
        }
    }

    private func annotationIntersects(_ annotation: Annotation, point: CGPoint, threshold: CGFloat) -> Bool {
        switch annotation.kind {
        case let .stroke(points, lineWidth, _, _, _):
            let hit = max(lineWidth, threshold)
            for i in 0..<(points.count - 1) {
                if distanceToSegment(point, points[i], points[i + 1]) < hit {
                    return true
                }
            }
        case let .arrow(from, to, lineWidth, _):
            if distanceToSegment(point, from, to) < max(lineWidth, threshold) { return true }
        case let .rectangle(rect, _, _, _), let .ellipse(rect, _, _, _), let .spotlight(rect, _, _):
            if rect.insetBy(dx: -threshold, dy: -threshold).contains(point) { return true }
        case let .text(content, origin, fontSize, _):
            if AnnotationKind.textBounds(content: content, origin: origin, fontSize: fontSize).contains(point) { return true }
        case let .measure(from, to, _):
            if distanceToSegment(point, from, to) < threshold { return true }
        }
        return false
    }

    private func rectFrom(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        if dx == 0, dy == 0 { return distance(p, a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)))
        let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return distance(p, projection)
    }

    private func textAnnotation(at point: CGPoint, generous: Bool = false) -> Annotation? {
        let padding: CGFloat = generous ? 24 : 10
        return screenAnnotations.reversed().first { annotation in
            guard case let .text(content, origin, fontSize, _) = annotation.kind else { return false }
            return AnnotationKind.textBounds(content: content, origin: origin, fontSize: fontSize, padding: padding).contains(point)
        }
    }

    private func arrowAnnotation(at point: CGPoint) -> Annotation? {
        guard let state = appState else { return nil }
        let threshold = max(state.lineWidth, 12)
        return screenAnnotations.reversed().first { annotation in
            guard case let .arrow(from, to, lineWidth, _) = annotation.kind else { return false }
            return distanceToSegment(point, from, to) < max(lineWidth, threshold)
        }
    }

    private func shapeAnnotationRect(at point: CGPoint) -> CGRect? {
        shapeAnnotation(at: point).flatMap { boundsForShape($0) }
    }

    private func shapeAnnotation(at point: CGPoint) -> Annotation? {
        screenAnnotations.reversed().first { annotation in
            guard let rect = boundsForShape(annotation) else { return false }
            return rect.insetBy(dx: -6, dy: -6).contains(point)
        }
    }

    private func boundsForShape(_ annotation: Annotation) -> CGRect? {
        switch annotation.kind {
        case let .rectangle(rect, _, _, _), let .ellipse(rect, _, _, _):
            return rect
        default:
            return nil
        }
    }

    private func arrowStart(toward target: CGPoint) -> CGPoint {
        if let rect = arrowAnchorRect {
            return rectEdgePoint(rect: rect, toward: target)
        }
        return dragStart ?? target
    }

    /// Ray from rect center through `target`, snapped to the shape border (callout leader).
    private func rectEdgePoint(rect: CGRect, toward target: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var dx = target.x - center.x
        var dy = target.y - center.y
        if abs(dx) < 0.001, abs(dy) < 0.001 { dy = -1 }

        var candidates: [CGPoint] = []
        if dx != 0 {
            candidates.append(CGPoint(x: rect.minX, y: center.y + ((rect.minX - center.x) / dx) * dy))
            candidates.append(CGPoint(x: rect.maxX, y: center.y + ((rect.maxX - center.x) / dx) * dy))
        }
        if dy != 0 {
            candidates.append(CGPoint(x: center.x + ((rect.minY - center.y) / dy) * dx, y: rect.minY))
            candidates.append(CGPoint(x: center.x + ((rect.maxY - center.y) / dy) * dx, y: rect.maxY))
        }

        let hits = candidates.filter { rect.insetBy(dx: -0.5, dy: -0.5).contains($0) }
        return hits
            .filter { (($0.x - center.x) * dx + ($0.y - center.y) * dy) > 0 }
            .min(by: { distance($0, target) < distance($1, target) })
            ?? CGPoint(x: rect.midX, y: rect.minY)
    }

    @discardableResult
    private func deleteAnnotationAtPoint(_ point: CGPoint) -> Bool {
        if deleteShape(at: point) { return true }
        return deleteArrow(at: point)
    }

    @discardableResult
    private func deleteArrow(at point: CGPoint) -> Bool {
        guard let state = appState else { return false }
        let threshold = max(state.lineWidth, 10)

        guard let hit = screenAnnotations.reversed().first(where: { annotation in
            guard case let .arrow(from, to, lineWidth, _) = annotation.kind else { return false }
            return distanceToSegment(point, from, to) < max(lineWidth, threshold)
        }) else { return false }

        state.removeAnnotations(withIDs: [hit.id])
        needsDisplay = true
        NotificationCenter.default.post(name: .bringToolbarToFront, object: nil)
        return true
    }

    @discardableResult
    private func deleteShape(at point: CGPoint) -> Bool {
        guard let shape = shapeAnnotation(at: point), let state = appState else { return false }

        var ids: Set<UUID> = [shape.id]
        if let shapeRect = boundsForShape(shape) {
            let hitRect = shapeRect.insetBy(dx: -8, dy: -8)
            for annotation in screenAnnotations {
                guard case let .text(content, origin, fontSize, _) = annotation.kind else { continue }
                let textBounds = AnnotationKind.textBounds(content: content, origin: origin, fontSize: fontSize, padding: 4)
                if hitRect.intersects(textBounds) {
                    ids.insert(annotation.id)
                }
            }
        }

        state.removeAnnotations(withIDs: ids)
        needsDisplay = true
        NotificationCenter.default.post(name: .bringToolbarToFront, object: nil)
        return true
    }

    private func beginDraggingText(annotation: Annotation, at point: CGPoint) {
        guard case let .text(_, origin, _, _) = annotation.kind else { return }
        appState?.beginUndoableChange()
        draggingTextID = annotation.id
        textDragOffset = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }
}

extension Notification.Name {
    static let textEditorsChanged = Notification.Name("DrawOver.textEditorsChanged")
    static let commitAllTextEditors = Notification.Name("DrawOver.commitAllTextEditors")
}
