import AppKit
import Carbon.HIToolbox
import Combine

/// Esc undo, tool switching, and Control-tap to cycle all tools while drawing.
@MainActor
final class DrawingInputMonitor {
    private weak var appState: AppState?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var pointerActivityObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    /// Control was pressed with no other modifiers yet; cancel if another key/mouse arrives.
    private var controlTapCandidate = false
    private var controlWasDown = false
    private var controlDownAt: Date?

    func configure(appState: AppState) {
        self.appState = appState

        Publishers.CombineLatest3(
            appState.$isDrawingModeActive,
            appState.$isAppEnabled,
            appState.$toolsOnlyWhileDrawing
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] drawing, enabled, toolsOnlyWhileDrawing in
            let shouldListen = enabled && (drawing || !toolsOnlyWhileDrawing)
            if shouldListen {
                self?.start()
            } else {
                self?.stop()
            }
        }
        .store(in: &cancellables)
    }

    private func start() {
        guard globalKeyMonitor == nil else { return }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.noteKeyDownWhileControlMayBeHeld()
                self?.handleKeyEvent(event)
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.noteKeyDownWhileControlMayBeHeld()
            if self.handleKeyEvent(event) {
                return nil
            }
            return event
        }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.cancelControlTapCandidate()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseDragged]) { [weak self] event in
            self?.cancelControlTapCandidate()
            return event
        }

        pointerActivityObserver = NotificationCenter.default.addObserver(
            forName: .drawingPointerActivity,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cancelControlTapCandidate()
        }
    }

    private func stop() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
            self.globalFlagsMonitor = nil
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let pointerActivityObserver {
            NotificationCenter.default.removeObserver(pointerActivityObserver)
            self.pointerActivityObserver = nil
        }
        controlTapCandidate = false
        controlWasDown = false
        controlDownAt = nil
    }

    private func cancelControlTapCandidate() {
        controlTapCandidate = false
    }

    private func noteKeyDownWhileControlMayBeHeld() {
        if controlWasDown {
            cancelControlTapCandidate()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard let appState, appState.isAppEnabled, appState.isDrawingModeActive else {
            controlTapCandidate = false
            controlWasDown = false
            controlDownAt = nil
            return
        }

        // Ignore Control taps while typing a caption.
        if appState.isTextInputActive {
            controlTapCandidate = false
            controlWasDown = event.modifierFlags.contains(.control)
            controlDownAt = nil
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let controlDown = flags.contains(.control)
        let otherMods = flags.intersection([.option, .command, .shift])

        if controlDown, !controlWasDown {
            // Control just pressed — only a candidate if no other modifiers are held.
            controlTapCandidate = otherMods.isEmpty
            controlDownAt = Date()
        } else if !controlDown, controlWasDown {
            // Control released — treat as a tap only if short and unused for ⌃-drag / ⌃+key.
            let duration = controlDownAt.map { Date().timeIntervalSince($0) } ?? 1
            if controlTapCandidate, otherMods.isEmpty, duration < 0.4 {
                appState.togglePenAndRectangle()
            }
            controlTapCandidate = false
            controlDownAt = nil
        } else if controlDown, !otherMods.isEmpty {
            cancelControlTapCandidate()
        }

        controlWasDown = controlDown
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let appState, appState.isAppEnabled else { return false }

        if event.keyCode == UInt16(kVK_Escape) {
            guard appState.isDrawingModeActive else { return false }
            appState.handleEscapeKey()
            return true
        }

        if isDeleteKey(event) {
            guard appState.isDrawingModeActive, !appState.isTextInputActive else { return false }
            return appState.deleteSelectedAnnotations()
        }

        return handleToolShortcut(event, appState: appState)
    }

    private func isDeleteKey(_ event: NSEvent) -> Bool {
        let code = event.keyCode
        return code == UInt16(kVK_Delete) || code == UInt16(kVK_ForwardDelete)
    }

    private func handleToolShortcut(_ event: NSEvent, appState: AppState) -> Bool {
        if appState.toolsOnlyWhileDrawing && !appState.isDrawingModeActive {
            return false
        }

        let toolActions: [ShortcutAction] = [
            .toolPen, .toolRectangle, .toolArrow, .toolPerson,
            .toolTriangle, .toolEllipse, .toolText, .toolEraser, .toolHighlighter
        ]

        for action in toolActions {
            let shortcut = appState.shortcutStore.shortcut(for: action)
            guard matches(event, shortcut: shortcut), let tool = action.linkedTool else { continue }
            appState.selectToolFromShortcut(tool)
            return true
        }
        return false
    }

    private func matches(_ event: NSEvent, shortcut: KeyboardShortcut) -> Bool {
        guard UInt32(event.keyCode) == shortcut.keyCode else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods == shortcut.carbonModifiers
    }
}
