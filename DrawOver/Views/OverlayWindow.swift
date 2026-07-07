import AppKit
import Combine

@MainActor
final class OverlayController: ObservableObject {
    private var windows: [OverlayWindow] = []
    private var canvasViews: [DrawingCanvasView] = []
    private var cancellables = Set<AnyCancellable>()
    private weak var appState: AppState?

    func configure(appState: AppState) {
        self.appState = appState

        appState.$isAppEnabled
            .sink { [weak self] enabled in
                if enabled {
                    self?.showOverlays()
                } else {
                    self?.hideOverlays()
                }
            }
            .store(in: &cancellables)

        appState.$isDrawingModeActive
            .sink { [weak self] active in
                self?.setInteractionEnabled(active)
                self?.refreshAnnotationVisibility()
            }
            .store(in: &cancellables)

        appState.$annotations
            .sink { [weak self] _ in
                self?.canvasViews.forEach { $0.needsDisplay = true }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: .annotationsCleared,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.canvasViews.forEach { $0.discardAllTextEditors() }
        }

        NotificationCenter.default.addObserver(
            forName: .commitAllTextEditors,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.canvasViews.forEach { $0.commitAllTextEditors() }
        }

        NotificationCenter.default.addObserver(
            forName: .textEditorsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshTextInputState()
        }

        NotificationCenter.default.addObserver(
            forName: .cancelCanvasInteraction,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.canvasViews.forEach { $0.cancelInteraction() }
        }

        NotificationCenter.default.addObserver(
            forName: .toolbarDidReceiveClick,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.releaseTextEditingFocus()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard appState.isAppEnabled else { return }
            self?.showOverlays()
        }
    }

    func dismissAllTextInputs() {
        canvasViews.forEach { $0.discardAllTextEditors() }
        refreshTextInputState()
    }

    func refreshTextInputState() {
        let editing = canvasViews.contains { $0.hasOpenTextEditors }
        appState?.isTextInputActive = editing
    }

    func releaseTextEditingFocus() {
        windows.forEach { $0.allowsTextEditing = false }
        canvasViews.forEach { $0.syncOverlayKeyState() }
    }

    func showOverlays() {
        hideOverlays()
        guard appState?.isAppEnabled == true else { return }

        for screen in NSScreen.screens {
            let displayID = screen.displayID
            let window = OverlayWindow(screen: screen)
            let canvas = DrawingCanvasView(frame: window.contentView?.bounds ?? screen.frame)
            canvas.autoresizingMask = [.width, .height]
            canvas.appState = appState
            canvas.displayID = displayID
            canvas.screenFrame = screen.frame
            canvas.overlayWindow = window

            window.contentView = canvas
            window.orderFrontRegardless()

            windows.append(window)
            canvasViews.append(canvas)
        }

        setInteractionEnabled(appState?.isDrawingModeActive ?? false)
    }

    func hideOverlays() {
        canvasViews.forEach { $0.discardAllTextEditors() }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        canvasViews.removeAll()
    }

    func prepareForSnapshot() {
        NotificationCenter.default.post(name: .commitAllTextEditors, object: nil)
        for window in windows {
            window.isDrawingActive = false
            window.backgroundColor = .clear
        }
        canvasViews.forEach { $0.displayIfNeeded() }
    }

    func restoreAfterSnapshot() {
        guard appState?.isAppEnabled == true else { return }
        let drawing = appState?.isDrawingModeActive ?? false
        for window in windows {
            window.isDrawingActive = drawing
        }
        windows.forEach { $0.orderFrontRegardless() }
    }

    func hideOverlaysForSnapshot() {
        windows.forEach { $0.orderOut(nil) }
    }

    func showOverlaysAfterSnapshot() {
        guard appState?.isAppEnabled == true else { return }
        windows.forEach { $0.orderFrontRegardless() }
    }

    private func setInteractionEnabled(_ enabled: Bool) {
        for window in windows {
            // Capture mouse while drawing so Finder/desktop doesn't receive drag gestures.
            window.ignoresMouseEvents = !enabled
            window.isDrawingActive = enabled
            if !enabled {
                window.allowsTextEditing = false
            }
        }
        if !enabled {
            canvasViews.forEach { view in
                view.cancelInteraction()
                view.syncOverlayKeyState()
            }
        }
        if enabled {
            NotificationCenter.default.post(name: .bringToolbarToFront, object: nil)
        }
    }

    private func refreshAnnotationVisibility() {
        canvasViews.forEach { $0.setNeedsDisplay($0.bounds) }
    }
}

final class OverlayWindow: NSPanel {
    var isDrawingActive = false {
        didSet { updateAppearance() }
    }

    var allowsTextEditing = false {
        didSet {
            if !allowsTextEditing, isKeyWindow {
                resignKey()
            }
        }
    }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        setFrame(screen.frame, display: true)

        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
    }

    private func updateAppearance() {
        if isDrawingActive {
            backgroundColor = NSColor.black.withAlphaComponent(0.02)
        } else {
            backgroundColor = .clear
        }
    }

    override var canBecomeKey: Bool { allowsTextEditing }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if isDrawingActive, event.type == .leftMouseDown || event.type == .rightMouseDown {
            if !ToolbarFrameTracker.contains(screenPoint: NSEvent.mouseLocation) {
                orderFrontRegardless()
            }
        }
        super.sendEvent(event)
    }
}
