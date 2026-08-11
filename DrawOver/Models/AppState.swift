import AppKit
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    /// Master switch — when false, hotkeys and overlays are inactive.
    @Published var isAppEnabled = true
    @Published var isDrawingModeActive = false
    @Published var isTextInputActive = false
    @Published var selectedTool: DrawingTool = .rectangle
    @Published var strokeColor: Color = .red
    @Published var lineWidth: CGFloat = 3
    @Published var annotations: [Annotation] = []
    /// Click a stroke to select; Delete / Forward Delete removes the selection.
    @Published var selectedAnnotationIDs: Set<UUID> = []
    @Published var toolbarDock: ToolbarDock = .floating
    @Published var showToolbar = true
    /// When true, the floating toolbar is hidden; control DrawOver via menu bar + keyboard shortcuts.
    @Published var isInvisibleMode = true
    @Published var toolbarOpacity: Double = 0.92
    @Published var toolbarUseTransparentBackground = true
    @Published var clearOnToggleOff = true
    @Published var clearOnToolSwitch = false
    @Published var toolsOnlyWhileDrawing = true
    @Published var captionAfterShape = false
    /// When true, freehand pen strokes snap to lines / circles / rectangles / triangles.
    @Published var penAutoSnapShapes = false
    /// Control-tap cycles either all toolbar tools or only Pen ↔ Rectangle.
    @Published var controlTapToolCycle: ControlTapToolCycle = .allTools
    @Published var spotlightDimOpacity: CGFloat = 0.55

    /// Last screen the user drew on or moved the toolbar to — used for snapshots.
    private(set) var lastActiveDisplayID: UInt32?

    let shortcutStore = ShortcutStore.shared

    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    private var cancellables = Set<AnyCancellable>()
    private var lastEscapeTime: Date?
    private var lastToolShortcutAt: Date?
    private let escapeDoubleTapInterval: TimeInterval = 0.45
    private let toolShortcutDebounce: TimeInterval = 0.25

    init() {
        loadPreferences()
        observePreferences()
    }

    var nsStrokeColor: NSColor {
        NSColor(strokeColor)
    }

    func setAppEnabled(_ enabled: Bool) {
        guard isAppEnabled != enabled else { return }
        if !enabled {
            if isDrawingModeActive {
                if clearOnToggleOff { clearAll(dismissText: true) }
                isDrawingModeActive = false
            }
            isTextInputActive = false
        }
        isAppEnabled = enabled
        NotificationCenter.default.post(name: .appEnabledChanged, object: nil)
        NotificationCenter.default.post(name: .drawingModeChanged, object: nil)
    }

    func toggleAppEnabled() {
        setAppEnabled(!isAppEnabled)
    }

    /// Esc undoes once; a second Esc within ~0.45s exits drawing mode (green dot off).
    func handleEscapeKey() {
        guard isAppEnabled, isDrawingModeActive else { return }

        let now = Date()
        if let last = lastEscapeTime, now.timeIntervalSince(last) <= escapeDoubleTapInterval {
            lastEscapeTime = nil
            stopDrawing()
            return
        }

        lastEscapeTime = now
        NotificationCenter.default.post(name: .cancelCanvasInteraction, object: nil)
        undo()
    }

    /// Clears the canvas but keeps drawing mode active (green dot stays on).
    func clearDrawingAndStayActive() {
        guard isAppEnabled, isDrawingModeActive else { return }
        clearAll(dismissText: true, recordUndo: true)
        FocusManager.releaseKeyboard()
        NotificationCenter.default.post(name: .cancelCanvasInteraction, object: nil)
        NotificationCenter.default.post(name: .bringToolbarToFront, object: nil)
    }

    /// Turn off drawing mode (green dot off) — used by the green dot and tool re-click.
    func stopDrawing() {
        guard isAppEnabled, isDrawingModeActive else { return }

        // Save any typed labels before clearing.
        NotificationCenter.default.post(name: .commitAllTextEditors, object: nil)
        NotificationCenter.default.post(name: .annotationsCleared, object: nil)

        if clearOnToggleOff {
            annotations.removeAll()
        }
        isTextInputActive = false
        clearSelection()

        isDrawingModeActive = false
        lastEscapeTime = nil
        FocusManager.releaseKeyboard()
        NotificationCenter.default.post(name: .cancelCanvasInteraction, object: nil)
        NotificationCenter.default.post(name: .bringToolbarToFront, object: nil)
    }

    /// Scribbble parity: toggle on to draw, toggle off to clear and exit.
    func toggleDrawingMode() {
        guard isAppEnabled else { return }

        if isDrawingModeActive {
            stopDrawing()
        } else {
            isDrawingModeActive = true
            NotificationCenter.default.post(name: .bringToolbarToFront, object: nil)
        }
    }

    func clearAll(dismissText: Bool = true, recordUndo: Bool = true) {
        if dismissText {
            NotificationCenter.default.post(name: .annotationsCleared, object: nil)
            isTextInputActive = false
        }
        if recordUndo, !annotations.isEmpty {
            pushUndo()
        }
        annotations.removeAll()
        clearSelection()
    }

    func addAnnotation(_ annotation: Annotation, displayID: UInt32) {
        pushUndo()
        var tagged = annotation
        tagged.displayID = displayID
        annotations.append(tagged)
    }

    func beginUndoableChange() {
        pushUndo()
    }

    func removeAnnotations(withIDs ids: Set<UUID>, recordUndo: Bool = true) {
        guard !ids.isEmpty else { return }
        if recordUndo { pushUndo() }
        annotations.removeAll { ids.contains($0.id) }
        selectedAnnotationIDs.subtract(ids)
    }

    func selectAnnotations(_ ids: Set<UUID>) {
        selectedAnnotationIDs = ids
    }

    func clearSelection() {
        selectedAnnotationIDs = []
    }

    /// Removes the current selection (Delete / Forward Delete).
    @discardableResult
    func deleteSelectedAnnotations() -> Bool {
        guard !selectedAnnotationIDs.isEmpty else { return false }
        let ids = selectedAnnotationIDs
        removeAnnotations(withIDs: ids)
        clearSelection()
        return true
    }

    func updateTextAnnotation(id: UUID, origin: CGPoint) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        guard case let .text(content, _, fontSize, color) = annotations[idx].kind else { return }
        annotations[idx].kind = .text(content: content, origin: origin, fontSize: fontSize, color: color)
    }

    func translateAnnotations(ids: Set<UUID>, by delta: CGPoint) {
        guard delta.x != 0 || delta.y != 0 else { return }
        for idx in annotations.indices where ids.contains(annotations[idx].id) {
            annotations[idx].kind = annotations[idx].kind.translated(by: delta)
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        trimHistoryStack(&redoStack)
        NotificationCenter.default.post(name: .annotationsCleared, object: nil)
        isTextInputActive = false
        clearSelection()
        annotations = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        trimHistoryStack(&undoStack)
        NotificationCenter.default.post(name: .annotationsCleared, object: nil)
        isTextInputActive = false
        clearSelection()
        annotations = next
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Select a tool — re-clicking the active tool toggles drawing off; picking a tool while off turns drawing on.
    func selectTool(_ tool: DrawingTool) {
        guard isAppEnabled else { return }

        if isDrawingModeActive && selectedTool == tool {
            stopDrawing()
            return
        }

        NotificationCenter.default.post(name: .commitAllTextEditors, object: nil)
        NotificationCenter.default.post(name: .annotationsCleared, object: nil)
        isTextInputActive = false

        if clearOnToolSwitch && isDrawingModeActive && selectedTool != tool {
            annotations.removeAll()
        }
        clearSelection()

        selectedTool = tool
        if tool.supportsLineWidth {
            lineWidth = tool.defaultLineWidth
        }

        if !isDrawingModeActive {
            isDrawingModeActive = true
        }

        NotificationCenter.default.post(name: .cancelCanvasInteraction, object: nil)
        NotificationCenter.default.post(name: .bringToolbarToFront, object: nil)
    }

    /// Keyboard shortcut entry point — debounced so Carbon + NSEvent monitors don't
    /// double-fire and accidentally toggle drawing off.
    func selectToolFromShortcut(_ tool: DrawingTool) {
        guard isAppEnabled else { return }

        let now = Date()
        if let last = lastToolShortcutAt, now.timeIntervalSince(last) < toolShortcutDebounce {
            return
        }
        lastToolShortcutAt = now

        if isTextInputActive {
            NotificationCenter.default.post(name: .commitAllTextEditors, object: nil)
            isTextInputActive = false
        }

        // Switching tools via shortcut should never stop drawing when choosing a new tool.
        if isDrawingModeActive && selectedTool == tool {
            return
        }

        NotificationCenter.default.post(name: .commitAllTextEditors, object: nil)
        NotificationCenter.default.post(name: .annotationsCleared, object: nil)
        isTextInputActive = false

        if clearOnToolSwitch && isDrawingModeActive && selectedTool != tool {
            annotations.removeAll()
        }
        clearSelection()

        selectedTool = tool
        if tool.supportsLineWidth {
            lineWidth = tool.defaultLineWidth
        }

        if !isDrawingModeActive {
            isDrawingModeActive = true
        }

        NotificationCenter.default.post(name: .cancelCanvasInteraction, object: nil)
        NotificationCenter.default.post(name: .bringToolbarToFront, object: nil)
    }

    func setTool(_ tool: DrawingTool) {
        selectTool(tool)
    }

    /// Tap Control alone to cycle tools while drawing (see `controlTapToolCycle`).
    func togglePenAndRectangle() {
        guard isAppEnabled, isDrawingModeActive else { return }
        let cycle = controlTapToolCycle.tools
        guard !cycle.isEmpty else { return }
        let next: DrawingTool
        if let idx = cycle.firstIndex(of: selectedTool) {
            next = cycle[(idx + 1) % cycle.count]
        } else {
            next = cycle[0]
        }
        selectToolFromShortcut(next)
    }

    func markDisplayActive(_ displayID: UInt32) {
        guard displayID != 0 else { return }
        lastActiveDisplayID = displayID
    }

    func snapshotDisplayID() -> UInt32 {
        SnapshotService.preferredDisplayID(lastActive: lastActiveDisplayID)
    }

    func shortcutLabel(for action: ShortcutAction) -> String {
        shortcutStore.shortcut(for: action).displayString
    }

    private func pushUndo() {
        redoStack.removeAll()
        undoStack.append(annotations)
        trimHistoryStack(&undoStack)
    }

    private func trimHistoryStack(_ stack: inout [[Annotation]]) {
        if stack.count > 50 {
            stack.removeFirst()
        }
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "isAppEnabled") != nil {
            isAppEnabled = defaults.bool(forKey: "isAppEnabled")
        }
        showToolbar = defaults.object(forKey: "showToolbar") as? Bool ?? true
        if defaults.object(forKey: "isInvisibleMode") != nil {
            isInvisibleMode = defaults.bool(forKey: "isInvisibleMode")
        } else {
            isInvisibleMode = true
            defaults.set(true, forKey: "isInvisibleMode")
        }
        toolbarOpacity = defaults.object(forKey: "toolbarOpacity") as? Double ?? 0.92
        toolbarUseTransparentBackground = defaults.object(forKey: "toolbarUseTransparentBackground") as? Bool ?? true
        clearOnToggleOff = defaults.object(forKey: "clearOnToggleOff") as? Bool ?? true
        if defaults.bool(forKey: "clearOnToolSwitchDefaultOffApplied") {
            clearOnToolSwitch = defaults.object(forKey: "clearOnToolSwitch") as? Bool ?? false
        } else {
            clearOnToolSwitch = false
            defaults.set(false, forKey: "clearOnToolSwitch")
            defaults.set(true, forKey: "clearOnToolSwitchDefaultOffApplied")
        }
        toolsOnlyWhileDrawing = defaults.object(forKey: "toolsOnlyWhileDrawing") as? Bool ?? true
        captionAfterShape = defaults.object(forKey: "captionAfterShape") as? Bool ?? false
        penAutoSnapShapes = defaults.object(forKey: "penAutoSnapShapes") as? Bool ?? false
        if let raw = defaults.string(forKey: "controlTapToolCycle"),
           let cycle = ControlTapToolCycle(rawValue: raw) {
            controlTapToolCycle = cycle
        }
        if let dock = defaults.string(forKey: "toolbarDock"), let value = ToolbarDock(rawValue: dock) {
            toolbarDock = value
        }
    }

    private func observePreferences() {
        $isAppEnabled.dropFirst().sink { UserDefaults.standard.set($0, forKey: "isAppEnabled") }.store(in: &cancellables)
        $showToolbar.dropFirst().sink { UserDefaults.standard.set($0, forKey: "showToolbar") }.store(in: &cancellables)
        $isInvisibleMode
            .dropFirst()
            .sink { [weak self] enabled in
                UserDefaults.standard.set(enabled, forKey: "isInvisibleMode")
                // Turning Invisible Mode off should restore the floating toolbar.
                if !enabled {
                    self?.showToolbar = true
                }
            }
            .store(in: &cancellables)
        $toolbarOpacity.dropFirst().sink { UserDefaults.standard.set($0, forKey: "toolbarOpacity") }.store(in: &cancellables)
        $toolbarUseTransparentBackground.dropFirst().sink { UserDefaults.standard.set($0, forKey: "toolbarUseTransparentBackground") }.store(in: &cancellables)
        $clearOnToggleOff.dropFirst().sink { UserDefaults.standard.set($0, forKey: "clearOnToggleOff") }.store(in: &cancellables)
        $clearOnToolSwitch.dropFirst().sink { UserDefaults.standard.set($0, forKey: "clearOnToolSwitch") }.store(in: &cancellables)
        $toolsOnlyWhileDrawing.dropFirst().sink { UserDefaults.standard.set($0, forKey: "toolsOnlyWhileDrawing") }.store(in: &cancellables)
        $captionAfterShape.dropFirst().sink { UserDefaults.standard.set($0, forKey: "captionAfterShape") }.store(in: &cancellables)
        $penAutoSnapShapes.dropFirst().sink { UserDefaults.standard.set($0, forKey: "penAutoSnapShapes") }.store(in: &cancellables)
        $controlTapToolCycle.dropFirst().sink { UserDefaults.standard.set($0.rawValue, forKey: "controlTapToolCycle") }.store(in: &cancellables)
        $toolbarDock.dropFirst().sink { UserDefaults.standard.set($0.rawValue, forKey: "toolbarDock") }.store(in: &cancellables)

        $isDrawingModeActive.dropFirst().sink { _ in
            NotificationCenter.default.post(name: .drawingModeChanged, object: nil)
        }.store(in: &cancellables)
    }
}

extension Notification.Name {
    static let appEnabledChanged = Notification.Name("DrawOver.appEnabledChanged")
    static let bringToolbarToFront = Notification.Name("DrawOver.bringToolbarToFront")
    static let cancelCanvasInteraction = Notification.Name("DrawOver.cancelCanvasInteraction")
    /// Posted when the click-through pointer router consumes a mouse gesture (so Control-tap doesn't fire).
    static let drawingPointerActivity = Notification.Name("DrawOver.drawingPointerActivity")
}

extension NSScreen {
    var displayID: UInt32 {
        let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return id?.uint32Value ?? CGMainDisplayID()
    }
}
