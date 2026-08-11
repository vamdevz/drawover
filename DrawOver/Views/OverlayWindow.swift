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
                self?.setDrawingModeActive(active)
                self?.refreshAnnotationVisibility()
            }
            .store(in: &cancellables)

        appState.$isTextInputActive
            .sink { [weak self] _ in
                self?.refreshMousePassthrough()
            }
            .store(in: &cancellables)

        appState.$annotations
            .sink { [weak self] _ in
                self?.canvasViews.forEach { $0.needsDisplay = true }
            }
            .store(in: &cancellables)

        appState.$selectedAnnotationIDs
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

    func canvas(containingGlobalPoint point: CGPoint) -> DrawingCanvasView? {
        canvasViews.first { $0.screenFrame.contains(point) }
    }

    func dismissAllTextInputs() {
        canvasViews.forEach { $0.discardAllTextEditors() }
        refreshTextInputState()
    }

    func refreshTextInputState() {
        let editing = canvasViews.contains { $0.hasOpenTextEditors }
        appState?.isTextInputActive = editing
        refreshMousePassthrough()
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

        setDrawingModeActive(appState?.isDrawingModeActive ?? false)
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
        refreshMousePassthrough()
        windows.forEach { $0.orderFrontRegardless() }
    }

    /// Drop below system region-select UI (layer ~0) and stop competing for the drag.
    func beginSystemScreenshotYield() {
        for window in windows {
            window.level = .normal
        }
    }

    func endSystemScreenshotYield() {
        guard appState?.isAppEnabled == true else { return }
        for window in windows {
            window.level = .screenSaver
            window.orderFrontRegardless()
        }
        NotificationCenter.default.post(name: .bringToolbarToFront, object: nil)
    }

    func hideOverlaysForSnapshot() {
        windows.forEach { $0.orderOut(nil) }
    }

    func showOverlaysAfterSnapshot() {
        guard appState?.isAppEnabled == true else { return }
        windows.forEach { $0.orderFrontRegardless() }
    }

    /// Drawing mode shows annotations; mouse stays pass-through so apps underneath remain usable.
    /// DrawingPointerRouter intercepts drag gestures. Caption editing temporarily captures the mouse.
    private func setDrawingModeActive(_ enabled: Bool) {
        for window in windows {
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
        refreshMousePassthrough()
        if enabled {
            NotificationCenter.default.post(name: .bringToolbarToFront, object: nil)
        }
    }

    private func refreshMousePassthrough() {
        let drawing = appState?.isDrawingModeActive ?? false
        let editing = appState?.isTextInputActive ?? false
        // Default: click-through. Only capture while a caption field needs AppKit focus.
        let capture = drawing && editing
        for window in windows {
            window.ignoresMouseEvents = !capture
        }
    }

    private func refreshAnnotationVisibility() {
        canvasViews.forEach { $0.setNeedsDisplay($0.bounds) }
    }
}

final class OverlayWindow: NSPanel {
    var isDrawingActive = false {
        didSet {
            updateAppearance()
            if !isDrawingActive, !allowsTextEditing, isKeyWindow {
                resignKey()
            }
        }
    }

    var allowsTextEditing = false {
        didSet {
            if !allowsTextEditing, !isDrawingActive, isKeyWindow {
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

    /// Caption editing needs key focus; tool shortcuts use Carbon / global monitors.
    override var canBecomeKey: Bool { allowsTextEditing || (isDrawingActive && !ignoresMouseEvents) }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if allowsTextEditing || (isDrawingActive && !ignoresMouseEvents),
           event.type == .leftMouseDown || event.type == .rightMouseDown {
            if !ToolbarFrameTracker.contains(screenPoint: NSEvent.mouseLocation) {
                orderFrontRegardless()
                makeKey()
            }
        }
        super.sendEvent(event)
    }

    func claimKeyFocus() {
        guard allowsTextEditing || (isDrawingActive && !ignoresMouseEvents) else { return }
        orderFrontRegardless()
        makeKey()
    }
}
