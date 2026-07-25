import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let appState: AppState
    private let overlayController: OverlayController
    private var statusItem: NSStatusItem?
    private var toolbarController: ToolbarPanelController?
    private var settingsWindow: NSWindow?

    init(appState: AppState, overlayController: OverlayController) {
        self.appState = appState
        self.overlayController = overlayController
        super.init()
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: "DrawOver")
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        toolbarController = ToolbarPanelController(appState: appState)
        if appState.showToolbar && appState.isAppEnabled && !appState.isInvisibleMode {
            toolbarController?.show()
        }

        if appState.isAppEnabled {
            overlayController.showOverlays()
        }

        observeNotifications()
        updateStatusIcon()
    }

    /// Left-click: toggle Invisible Mode. Right-click: menu.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            statusItem?.popUpMenu(buildMenu())
            return
        }

        if !appState.isAppEnabled {
            appState.setAppEnabled(true)
            overlayController.showOverlays()
        }

        setInvisibleMode(!appState.isInvisibleMode)
        updateStatusIcon()
    }

    @discardableResult
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let enableItem = NSMenuItem(
            title: appState.isAppEnabled ? "Disable DrawOver" : "Enable DrawOver",
            action: #selector(toggleAppEnabled),
            keyEquivalent: ""
        )
        enableItem.target = self
        menu.addItem(enableItem)

        menu.addItem(.separator())

        let toggleLabel = appState.shortcutLabel(for: .toggleDrawing)
        let drawItem = NSMenuItem(
            title: appState.isDrawingModeActive ? "Stop Drawing (\(toggleLabel))" : "Start Drawing (\(toggleLabel))",
            action: #selector(toggleDrawing),
            keyEquivalent: ""
        )
        drawItem.target = self
        drawItem.isEnabled = appState.isAppEnabled
        menu.addItem(drawItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(
            title: "Clear All (\(appState.shortcutLabel(for: .clearAll)))",
            action: #selector(clearAll),
            keyEquivalent: ""
        )
        clearItem.target = self
        clearItem.isEnabled = appState.isAppEnabled
        menu.addItem(clearItem)

        let snapshotItem = NSMenuItem(
            title: "Snapshot (\(appState.shortcutLabel(for: .snapshot)))",
            action: #selector(takeSnapshot),
            keyEquivalent: ""
        )
        snapshotItem.target = self
        snapshotItem.isEnabled = appState.isAppEnabled
        menu.addItem(snapshotItem)

        menu.addItem(.separator())

        let invisibleItem = NSMenuItem(
            title: "Invisible Mode",
            action: #selector(toggleInvisibleMode),
            keyEquivalent: ""
        )
        invisibleItem.target = self
        invisibleItem.state = appState.isInvisibleMode ? .on : .off
        invisibleItem.isEnabled = appState.isAppEnabled
        menu.addItem(invisibleItem)

        let toolbarItem = NSMenuItem(
            title: appState.showToolbar ? "Hide Toolbar" : "Show Toolbar",
            action: #selector(toggleToolbar),
            keyEquivalent: ""
        )
        toolbarItem.target = self
        toolbarItem.isEnabled = appState.isAppEnabled && !appState.isInvisibleMode
        menu.addItem(toolbarItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit DrawOver", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = nil
        return menu
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            forName: .drawingModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusIcon()
        }

        NotificationCenter.default.addObserver(
            forName: .appEnabledChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppEnabledChanged()
        }

        NotificationCenter.default.addObserver(
            forName: .bringToolbarToFront,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.appState.isInvisibleMode {
                    self.toolbarController?.hide()
                } else {
                    self.toolbarController?.bringToFront()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .takeSnapshot,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.takeSnapshot()
            }
        }
    }

    private func handleAppEnabledChanged() {
        if appState.isAppEnabled {
            overlayController.showOverlays()
            if appState.showToolbar && !appState.isInvisibleMode {
                toolbarController?.show()
            } else {
                toolbarController?.hide()
            }
        } else {
            overlayController.hideOverlays()
            toolbarController?.hide()
        }
        updateStatusIcon()
    }

    @objc private func toggleAppEnabled() {
        appState.toggleAppEnabled()
    }

    @objc private func toggleDrawing() {
        appState.toggleDrawingMode()
        updateStatusIcon()
    }

    @objc private func clearAll() {
        appState.clearAll(dismissText: true)
    }

    @objc private func takeSnapshot() {
        let displayID = appState.snapshotDisplayID()
        let annotations = appState.annotations
        Task { @MainActor in
            await SnapshotService.captureFullScreen(
                displayID: displayID,
                annotations: annotations,
                hideChrome: { [weak self] in
                    self?.toolbarController?.hide()
                    self?.overlayController.prepareForSnapshot()
                    self?.overlayController.hideOverlaysForSnapshot()
                },
                restoreChrome: { [weak self] in
                    guard let self else { return }
                    self.overlayController.showOverlaysAfterSnapshot()
                    self.overlayController.restoreAfterSnapshot()
                    if self.appState.showToolbar, self.appState.isAppEnabled, !self.appState.isInvisibleMode {
                        self.toolbarController?.show()
                    }
                }
            )
        }
    }

    @objc private func toggleInvisibleMode() {
        setInvisibleMode(!appState.isInvisibleMode)
    }

    private func setInvisibleMode(_ enabled: Bool) {
        appState.isInvisibleMode = enabled
        if enabled {
            toolbarController?.hide()
            ToolbarFrameTracker.clear()
        } else {
            // Leaving invisible mode should always bring the floating toolbar back.
            appState.showToolbar = true
            toolbarController?.forceShow()
        }
        updateStatusIcon()
    }

    @objc private func toggleToolbar() {
        guard !appState.isInvisibleMode else { return }
        appState.showToolbar.toggle()
        if appState.showToolbar {
            toolbarController?.forceShow()
        } else {
            toolbarController?.hide()
        }
    }

    @objc private func openSettings() {
        // Menu-bar (accessory) apps often ignore SwiftUI Settings / showSettingsWindow:.
        // Always open an explicit window so the menu item is reliable.
        showSettingsWindow()
    }

    private func showSettingsWindow() {
        if settingsWindow == nil {
            let settingsView = SettingsView(appState: appState)
            let hosting = NSHostingController(rootView: settingsView)
            let window = NSWindow(contentViewController: hosting)
            window.title = "DrawOver Settings"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 520, height: 620))
            window.minSize = NSSize(width: 420, height: 420)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateStatusIcon() {
        let symbol: String
        if !appState.isAppEnabled {
            symbol = "pencil.slash"
        } else if appState.isInvisibleMode {
            symbol = "eye.slash"
        } else if appState.isDrawingModeActive {
            symbol = "pencil.and.outline"
        } else {
            symbol = "eye"
        }
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "DrawOver")
        statusItem?.button?.image?.isTemplate = true
        statusItem?.button?.toolTip = appState.isInvisibleMode
            ? "Invisible Mode on — click to show toolbar"
            : "Invisible Mode off — click to hide toolbar"
    }
}
