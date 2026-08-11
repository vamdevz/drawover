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

    private var screenshotFlagsMonitor: Any?
    private var screenshotFlagsLocalMonitor: Any?
    private var screenshotKeyMonitor: Any?
    private var screenshotKeyLocalMonitor: Any?
    private var screenshotPollTimer: Timer?
    private var isYieldingToScreenshot = false

    /// Shared with the CGEvent callback (may run off the main thread).
    fileprivate let bridge = PointerTapBridge()

    func configure(appState: AppState, overlayController: OverlayController) {
        self.appState = appState
        self.overlayController = overlayController
        bridge.router = self
        bridge.onScreenshotArmRequest = { [weak self] in
            Task { @MainActor in
                self?.armScreenshotYield()
            }
        }

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
        startScreenshotYieldMonitoring()

        guard eventTap == nil else {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        // Mouse only — do not tap key/flags here (avoids work on every modifier change).
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
        stopScreenshotYieldMonitoring()
        setYieldingToScreenshot(false)
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

    // MARK: - Screenshot yield

    private func startScreenshotYieldMonitoring() {
        if screenshotFlagsMonitor == nil {
            screenshotFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                Task { @MainActor in
                    self?.notePossibleScreenshotChord(event.modifierFlags)
                }
            }
            screenshotFlagsLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.notePossibleScreenshotChord(event.modifierFlags)
                return event
            }
        }

        if screenshotKeyMonitor == nil {
            screenshotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard Self.isScreenshotShortcut(event) else { return }
                Task { @MainActor in
                    self?.armScreenshotYield()
                }
            }
            screenshotKeyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if Self.isScreenshotShortcut(event) {
                    self?.armScreenshotYield()
                }
                return event
            }
        }

        // Lightweight poll: only reads an atomic cache updated off the main thread.
        if screenshotPollTimer == nil {
            SystemScreenshotUI.startBackgroundPolling()
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshScreenshotYield()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            screenshotPollTimer = timer
        }
    }

    private func stopScreenshotYieldMonitoring() {
        if let screenshotFlagsMonitor {
            NSEvent.removeMonitor(screenshotFlagsMonitor)
        }
        if let screenshotFlagsLocalMonitor {
            NSEvent.removeMonitor(screenshotFlagsLocalMonitor)
        }
        if let screenshotKeyMonitor {
            NSEvent.removeMonitor(screenshotKeyMonitor)
        }
        if let screenshotKeyLocalMonitor {
            NSEvent.removeMonitor(screenshotKeyLocalMonitor)
        }
        screenshotFlagsMonitor = nil
        screenshotFlagsLocalMonitor = nil
        screenshotKeyMonitor = nil
        screenshotKeyLocalMonitor = nil

        screenshotPollTimer?.invalidate()
        screenshotPollTimer = nil
        SystemScreenshotUI.stopBackgroundPolling()
    }

    /// MX Master mapping: ⌘⌃⇧4 — modifiers are visible even when the "4" is swallowed by the system.
    private func notePossibleScreenshotChord(_ flags: NSEvent.ModifierFlags) {
        let f = flags.intersection(.deviceIndependentFlagsMask)
        if f.contains(.command), f.contains(.shift), f.contains(.control) {
            armScreenshotYield()
        }
    }

    private static func isScreenshotShortcut(_ event: NSEvent) -> Bool {
        // kVK_ANSI_3/4/5 = 20/21/23
        guard event.keyCode == 20 || event.keyCode == 21 || event.keyCode == 23 else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.command) && flags.contains(.shift)
    }

    private func armScreenshotYield() {
        bridge.armScreenshotPassThrough(duration: 20)
        NotificationCenter.default.post(name: .cancelCanvasInteraction, object: nil)
        setYieldingToScreenshot(true)
    }

    private func refreshScreenshotYield() {
        let uiActive = SystemScreenshotUI.isActiveCached
        if uiActive {
            bridge.armScreenshotPassThrough(duration: 1.5)
        }
        setYieldingToScreenshot(uiActive || bridge.isScreenshotArmed)
    }

    private func setYieldingToScreenshot(_ yield: Bool) {
        // Always publish arm state to the bridge; only touch windows/tap when it changes.
        bridge.setScreenshotYielding(yield)

        guard isYieldingToScreenshot != yield else { return }
        isYieldingToScreenshot = yield

        if yield {
            bridge.resetDrawingPhaseOnly()
            NotificationCenter.default.post(name: .cancelCanvasInteraction, object: nil)
            overlayController?.beginSystemScreenshotYield()
        } else {
            overlayController?.endSystemScreenshotYield()
        }
        // Keep the event tap enabled — pass-through is handled per-event in the bridge.
        // Disabling the tap entirely previously left drawing stuck off.
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    fileprivate func shouldHandleDrawingEvents() -> Bool {
        guard let appState else { return false }
        if isYieldingToScreenshot { return false }
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
    var onScreenshotArmRequest: (() -> Void)?

    private let lock = NSLock()
    private enum Phase {
        case idle
        case pending(start: CGPoint, flags: CGEventFlags, clickCount: Int64)
        case drawing
    }

    private var phase: Phase = .idle
    private let dragThreshold: CGFloat = 4
    static let injectedUserData: Int64 = 0xD40A_0E01

    private var screenshotArmed = false
    private var screenshotArmedUntil: CFAbsoluteTime = 0
    /// Mirrors router yield — read on the tap thread without hopping to main / spawning processes.
    private var screenshotYielding = false

    var isScreenshotArmed: Bool {
        lock.lock()
        defer { lock.unlock() }
        if screenshotArmed, CFAbsoluteTimeGetCurrent() > screenshotArmedUntil {
            screenshotArmed = false
        }
        return screenshotArmed
    }

    func setScreenshotYielding(_ yielding: Bool) {
        lock.lock()
        screenshotYielding = yielding
        lock.unlock()
    }

    func reset() {
        lock.lock()
        phase = .idle
        screenshotArmed = false
        screenshotArmedUntil = 0
        screenshotYielding = false
        lock.unlock()
    }

    func resetDrawingPhaseOnly() {
        lock.lock()
        phase = .idle
        lock.unlock()
    }

    func armScreenshotPassThrough(duration: CFTimeInterval = 20) {
        lock.lock()
        phase = .idle
        screenshotArmed = true
        let until = CFAbsoluteTimeGetCurrent() + duration
        if until > screenshotArmedUntil {
            screenshotArmedUntil = until
        }
        lock.unlock()
    }

    func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.injectedUserData {
            return Unmanaged.passUnretained(event)
        }

        // Fast path: while screenshot yield is on, never swallow mouse events.
        // Must not call pgrep / window APIs here — that froze the whole input system.
        if isPassingThroughForScreenshot() {
            return Unmanaged.passUnretained(event)
        }

        let quartzGlobal = event.location
        let cocoaGlobal = Self.cocoaPoint(fromQuartz: quartzGlobal)

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
            let flags = Self.appKitModifiers(from: event.flags)
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

    private func isPassingThroughForScreenshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if screenshotYielding { return true }
        if screenshotArmed, CFAbsoluteTimeGetCurrent() <= screenshotArmedUntil {
            return true
        }
        if screenshotArmed, CFAbsoluteTimeGetCurrent() > screenshotArmedUntil {
            screenshotArmed = false
        }
        return false
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
            let merged = CGEventFlags(rawValue: flags.rawValue | event.flags.rawValue)
            let mods = Self.appKitModifiers(from: merged)
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

    private static func appKitModifiers(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
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

/// Detects interactive screenshot capture without blocking the event tap or main thread.
private enum SystemScreenshotUI {
    private static let stateLock = NSLock()
    private static var cachedActive = false
    private static var pollTimer: DispatchSourceTimer?
    private static let pollQueue = DispatchQueue(label: "com.drawover.screenshot-poll", qos: .utility)

    static var isActiveCached: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cachedActive
    }

    static func startBackgroundPolling() {
        pollQueue.async {
            guard pollTimer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: pollQueue)
            timer.schedule(deadline: .now(), repeating: 0.4)
            timer.setEventHandler {
                let active = detectScreencaptureRunning()
                stateLock.lock()
                cachedActive = active
                stateLock.unlock()
            }
            pollTimer = timer
            timer.resume()
        }
    }

    static func stopBackgroundPolling() {
        pollQueue.async {
            pollTimer?.cancel()
            pollTimer = nil
            stateLock.lock()
            cachedActive = false
            stateLock.unlock()
        }
    }

    /// Runs only on `pollQueue` — never from the CGEvent callback.
    private static func detectScreencaptureRunning() -> Bool {
        // Exact process names only (avoid broad -f matches that stay true forever).
        pgrep(exactName: "screencapture") || pgrep(exactName: "screencaptureui")
    }

    private static func pgrep(exactName: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        proc.arguments = ["-x", exactName]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
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
