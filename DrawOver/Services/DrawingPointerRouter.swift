import AppKit
import Combine

/// While drawing mode is on, keeps the overlay click-through so apps stay usable.
/// Left-button *drags* are routed to the canvas for drawing; plain clicks are passed through.
@MainActor
final class DrawingPointerRouter {
    private weak var appState: AppState?
    private weak var overlayController: OverlayController?
    private var cancellables = Set<AnyCancellable>()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Shared with the CGEvent callback (may run off the main thread).
    fileprivate let bridge = PointerTapBridge()

    func configure(appState: AppState, overlayController: OverlayController) {
        self.appState = appState
        self.overlayController = overlayController
        bridge.router = self

        Publishers.CombineLatest(appState.$isAppEnabled, appState.$isDrawingModeActive)
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled, drawing in
                if enabled && drawing {
                    self?.startTap()
                } else {
                    self?.stopTap()
                    self?.bridge.reset()
                }
            }
            .store(in: &cancellables)
    }

    private func startTap() {
        guard eventTap == nil else {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        let mask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: pointerTapCallback,
            userInfo: Unmanaged.passUnretained(bridge).toOpaque()
        ) else {
            return
        }

        eventTap = tap
        bridge.eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopTap() {
        bridge.eventTap = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    fileprivate func shouldHandleDrawingEvents() -> Bool {
        guard let appState else { return false }
        // Caption fields need normal AppKit delivery on the overlay.
        if appState.isTextInputActive { return false }
        return appState.isAppEnabled && appState.isDrawingModeActive
    }

    fileprivate func canvas(atGlobalPoint point: CGPoint) -> DrawingCanvasView? {
        overlayController?.canvas(containingGlobalPoint: point)
    }
}

/// Non-isolated bridge so the CGEvent tap callback can reach MainActor work safely.
final class PointerTapBridge: @unchecked Sendable {
    weak var router: DrawingPointerRouter?
    var eventTap: CFMachPort?

    private let lock = NSLock()
    private enum Phase {
        case idle
        case pending(start: CGPoint, flags: CGEventFlags, clickCount: Int64)
        case drawing
    }

    private var phase: Phase = .idle
    private let dragThreshold: CGFloat = 4
    static let injectedUserData: Int64 = 0xD40A_0E01

    func reset() {
        lock.lock()
        phase = .idle
        lock.unlock()
    }

    func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Avoid re-processing clicks we synthesized for pass-through.
        if event.getIntegerValueField(.eventSourceUserData) == Self.injectedUserData {
            return Unmanaged.passUnretained(event)
        }

        // CGEvent.location is Quartz (top-left origin). AppKit / our canvas use Cocoa (bottom-left).
        let quartzGlobal = event.location
        let cocoaGlobal = Self.cocoaPoint(fromQuartz: quartzGlobal)

        // Toolbar must keep receiving normal clicks.
        if ToolbarFrameTracker.containsThreadSafe(screenPoint: cocoaGlobal) {
            return Unmanaged.passUnretained(event)
        }

        let decision = onMain { () -> (Bool, Bool, CGPoint?, NSEvent.ModifierFlags) in
            guard let router, router.shouldHandleDrawingEvents() else {
                return (false, false, nil, [])
            }
            guard let canvas = router.canvas(atGlobalPoint: cocoaGlobal) else {
                return (false, false, nil, [])
            }
            let point = canvas.pointFromGlobalScreen(cocoaGlobal)
            let flags = Self.modifierFlags(from: event.flags)
            let clickCount = max(1, event.getIntegerValueField(.mouseEventClickState))
            let wantsImmediate = canvas.prefersImmediatePointerCapture(
                at: point,
                modifierFlags: flags,
                clickCount: Int(clickCount)
            )
            return (true, wantsImmediate, point, flags)
        }

        let shouldHandle = decision.0
        let immediate = decision.1
        let canvasPoint = decision.2
        let modifiers = decision.3

        guard shouldHandle, let canvasPoint else {
            return Unmanaged.passUnretained(event)
        }

        // Swallowed mouse events never reach NSEvent monitors — cancel Control-tap tool cycling.
        onMainAsync {
            NotificationCenter.default.post(name: .drawingPointerActivity, object: nil)
        }

        switch type {
        case .leftMouseDown:
            return handleMouseDown(
                event: event,
                cocoaGlobal: cocoaGlobal,
                canvasPoint: canvasPoint,
                modifiers: modifiers,
                immediate: immediate
            )
        case .leftMouseDragged:
            return handleMouseDragged(event: event, cocoaGlobal: cocoaGlobal, canvasPoint: canvasPoint)
        case .leftMouseUp:
            return handleMouseUp(event: event, cocoaGlobal: cocoaGlobal, canvasPoint: canvasPoint, modifiers: modifiers)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleMouseDown(
        event: CGEvent,
        cocoaGlobal: CGPoint,
        canvasPoint: CGPoint,
        modifiers: NSEvent.ModifierFlags,
        immediate: Bool
    ) -> Unmanaged<CGEvent>? {
        let clickCount = max(1, event.getIntegerValueField(.mouseEventClickState))

        if immediate {
            lock.lock()
            phase = .drawing
            lock.unlock()
            onMainAsync { [weak self] in
                guard let self, let router = self.router,
                      let canvas = router.canvas(atGlobalPoint: cocoaGlobal) else { return }
                canvas.handlePointerDown(at: canvasPoint, modifierFlags: modifiers, clickCount: Int(clickCount))
            }
            return nil
        }

        lock.lock()
        phase = .pending(start: cocoaGlobal, flags: event.flags, clickCount: clickCount)
        lock.unlock()
        return nil
    }

    private func handleMouseDragged(
        event: CGEvent,
        cocoaGlobal: CGPoint,
        canvasPoint: CGPoint
    ) -> Unmanaged<CGEvent>? {
        lock.lock()
        let current = phase
        lock.unlock()

        switch current {
        case .idle:
            return Unmanaged.passUnretained(event)

        case let .pending(start, flags, clickCount):
            let dx = cocoaGlobal.x - start.x
            let dy = cocoaGlobal.y - start.y
            if hypot(dx, dy) < dragThreshold {
                return nil
            }
            let startPoint = start
            // Prefer live drag flags so ⌃ held during the drag still creates an arrow.
            let merged = CGEventFlags(rawValue: flags.rawValue | event.flags.rawValue)
            let mods = Self.modifierFlags(from: merged)
            lock.lock()
            phase = .drawing
            lock.unlock()
            onMainAsync { [weak self] in
                guard let self, let router = self.router,
                      let canvas = router.canvas(atGlobalPoint: startPoint) else { return }
                let localStart = canvas.pointFromGlobalScreen(startPoint)
                canvas.handlePointerDown(at: localStart, modifierFlags: mods, clickCount: Int(clickCount))
                if let liveCanvas = router.canvas(atGlobalPoint: cocoaGlobal) {
                    liveCanvas.handlePointerDragged(at: canvasPoint)
                }
            }
            return nil

        case .drawing:
            onMainAsync { [weak self] in
                guard let self, let router = self.router,
                      let canvas = router.canvas(atGlobalPoint: cocoaGlobal) else { return }
                canvas.handlePointerDragged(at: canvasPoint)
            }
            return nil
        }
    }

    private func handleMouseUp(
        event: CGEvent,
        cocoaGlobal: CGPoint,
        canvasPoint: CGPoint,
        modifiers: NSEvent.ModifierFlags
    ) -> Unmanaged<CGEvent>? {
        lock.lock()
        let current = phase
        phase = .idle
        lock.unlock()

        switch current {
        case .idle:
            return Unmanaged.passUnretained(event)

        case let .pending(start, flags, clickCount):
            // Plain click — deliver to the app underneath (CGEvent wants Quartz coords).
            Self.postInjectedClick(at: Self.quartzPoint(fromCocoa: start), flags: flags, clickCount: clickCount)
            return nil

        case .drawing:
            onMainAsync { [weak self] in
                guard let self, let router = self.router,
                      let canvas = router.canvas(atGlobalPoint: cocoaGlobal) else { return }
                canvas.handlePointerUp(at: canvasPoint, modifierFlags: modifiers)
            }
            return nil
        }
    }

    /// Quartz global (CGEvent, top-left of main display) → Cocoa global (NSEvent / AppKit).
    private static func cocoaPoint(fromQuartz quartz: CGPoint) -> CGPoint {
        let height = CGDisplayBounds(CGMainDisplayID()).height
        return CGPoint(x: quartz.x, y: height - quartz.y)
    }

    private static func quartzPoint(fromCocoa cocoa: CGPoint) -> CGPoint {
        let height = CGDisplayBounds(CGMainDisplayID()).height
        return CGPoint(x: cocoa.x, y: height - cocoa.y)
    }

    private static func postInjectedClick(at quartzPoint: CGPoint, flags: CGEventFlags, clickCount: Int64) {
        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: quartzPoint,
            mouseButton: .left
        ),
        let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: quartzPoint,
            mouseButton: .left
        ) else { return }

        for event in [down, up] {
            event.flags = flags
            event.setIntegerValueField(.mouseEventClickState, value: clickCount)
            event.setIntegerValueField(.eventSourceUserData, value: injectedUserData)
            event.post(tap: .cghidEventTap)
        }
    }

    private static func modifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        let raw = flags.rawValue
        if raw & CGEventFlags.maskControl.rawValue != 0 { result.insert(.control) }
        if raw & CGEventFlags.maskAlternate.rawValue != 0 { result.insert(.option) }
        if raw & CGEventFlags.maskShift.rawValue != 0 { result.insert(.shift) }
        if raw & CGEventFlags.maskCommand.rawValue != 0 { result.insert(.command) }
        return result
    }

    private func onMain<T>(_ work: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(work)
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(work)
        }
    }

    private func onMainAsync(_ work: @MainActor @escaping () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            Task { @MainActor in
                work()
            }
        }
    }
}

private func pointerTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let bridge = Unmanaged<PointerTapBridge>.fromOpaque(userInfo).takeUnretainedValue()
    return bridge.handleEvent(type: type, event: event)
}
