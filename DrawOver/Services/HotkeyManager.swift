import AppKit
import Carbon.HIToolbox
import Combine

final class HotkeyManager {
    private var hotkeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    private let hotkeySignature: OSType = {
        var value: OSType = 0
        for byte in "DRWR".utf8 {
            value = (value << 8) + OSType(byte)
        }
        return value
    }()

    func register(appState: AppState) {
        self.appState = appState
        installHandlerIfNeeded()

        Task { @MainActor in
            self.observeAppState(appState)
            self.reloadShortcuts()
        }

        NotificationCenter.default.addObserver(
            forName: .shortcutsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadShortcuts()
            }
        }
    }

    @MainActor
    private func observeAppState(_ appState: AppState) {
        Publishers.CombineLatest3(
            appState.$isAppEnabled,
            appState.$isDrawingModeActive,
            appState.$isTextInputActive
        )
        .sink { [weak self] _, _, _ in
            self?.reloadShortcuts()
        }
        .store(in: &cancellables)
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.handleHotkey(event: event)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    @MainActor
    private func reloadShortcuts() {
        unregisterAll()
        guard let appState, appState.isAppEnabled else { return }

        let globalActions: [ShortcutAction] = [.toggleDrawing, .clearAll, .undo, .snapshot]
        let toolActions: [ShortcutAction] = [
            .toolPen, .toolHighlighter, .toolArrow, .toolRectangle,
            .toolEllipse, .toolText, .toolEraser
        ]

        var actions = globalActions

        if appState.isDrawingModeActive {
            // Esc must work even while a text field is open.
            actions.append(.stopDrawing)
            if !appState.isTextInputActive {
                actions.append(contentsOf: toolActions)
            }
        }

        for action in actions {
            registerHotkey(ShortcutStore.shared.shortcut(for: action))
        }
    }

    private func registerHotkey(_ shortcut: KeyboardShortcut) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotkeySignature, id: shortcut.action.hotkeyID)
        RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        hotkeyRefs.append(ref)
    }

    private func unregisterAll() {
        hotkeyRefs.forEach { if let ref = $0 { UnregisterEventHotKey(ref) } }
        hotkeyRefs.removeAll()
    }

    @MainActor
    private func handleHotkey(event: EventRef?) {
        guard let event, let appState, appState.isAppEnabled else { return }

        var hotkeyID = EventHotKeyID()
        GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )

        guard let action = ShortcutAction.allCases.first(where: { $0.hotkeyID == hotkeyID.id }) else { return }

        if appState.isTextInputActive, action != .stopDrawing {
            return
        }

        switch action {
        case .toggleDrawing:
            appState.toggleDrawingMode()
        case .stopDrawing:
            appState.clearDrawingAndStayActive()
        case .clearAll:
            appState.clearAll(dismissText: true)
        case .undo:
            appState.undo()
        case .snapshot:
            NotificationCenter.default.post(name: .takeSnapshot, object: nil)
        case .toolPen, .toolHighlighter, .toolArrow, .toolRectangle, .toolEllipse, .toolText, .toolEraser:
            if let tool = action.linkedTool {
                appState.selectTool(tool)
            }
        }
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

extension Notification.Name {
    static let drawingModeChanged = Notification.Name("DrawOver.drawingModeChanged")
}
