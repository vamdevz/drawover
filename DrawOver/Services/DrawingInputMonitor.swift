import AppKit
import Carbon.HIToolbox
import Combine

/// Handles Esc-to-exit while drawing. Uses a global monitor so Esc works even when another app is focused.
@MainActor
final class DrawingInputMonitor {
    private weak var appState: AppState?
    private var globalKeyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func configure(appState: AppState) {
        self.appState = appState

        Publishers.CombineLatest(appState.$isDrawingModeActive, appState.$isAppEnabled)
            .sink { [weak self] drawing, enabled in
                if drawing && enabled {
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
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            Task { @MainActor in
                guard let appState = self?.appState else { return }
                guard appState.isAppEnabled, appState.isDrawingModeActive else { return }
                appState.stopDrawing()
            }
        }
    }

    private func stop() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }
}
