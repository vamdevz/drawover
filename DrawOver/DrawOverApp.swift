import AppKit
import SwiftUI

@main
struct DrawOverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(appState: appDelegate.appState)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private let overlayController = OverlayController()
    private let drawingInputMonitor = DrawingInputMonitor()
    private var menuBarController: MenuBarController?
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlayController.configure(appState: appState)
        drawingInputMonitor.configure(appState: appState)
        menuBarController = MenuBarController(appState: appState, overlayController: overlayController)
        menuBarController?.setup()

        hotkeyManager = HotkeyManager()
        hotkeyManager?.register(appState: appState)

        requestAccessibilityIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var shortcutStore: ShortcutStore

    init(appState: AppState) {
        self.appState = appState
        self._shortcutStore = ObservedObject(wrappedValue: appState.shortcutStore)
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }
            toolbarTab
                .tabItem { Label("Toolbar", systemImage: "sidebar.right") }
            shortcutsTab
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(minWidth: 500, minHeight: 520)
        .padding()
    }

    private var generalTab: some View {
        Form {
            Section("App") {
                Toggle("DrawOver enabled", isOn: Binding(
                    get: { appState.isAppEnabled },
                    set: { appState.setAppEnabled($0) }
                ))
                Text("When disabled, no hotkeys fire and overlays are hidden. Use the menu bar to re-enable without quitting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Drawing") {
                Toggle("Drawing mode active", isOn: $appState.isDrawingModeActive)
                    .disabled(!appState.isAppEnabled)
                Picker("Default tool", selection: $appState.selectedTool) {
                    ForEach(DrawingTool.allCases) { tool in
                        Label(tool.label, systemImage: tool.icon).tag(tool)
                    }
                }
                .disabled(!appState.isAppEnabled)
                Toggle("Clear annotations when turning drawing off", isOn: $appState.clearOnToggleOff)
                Toggle("Clear annotations when switching tools", isOn: $appState.clearOnToolSwitch)
                Toggle("Auto-caption every new box", isOn: $appState.captionAfterShape)
                Toggle("Tool hotkeys only while drawing", isOn: $appState.toolsOnlyWhileDrawing)
                Text("Rectangle tool: drag = box, ⌃-drag = arrow. Double-click a box or arrow line to caption. ⇧-draw = caption on new box. Tips on the toolbar are reference only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                Text("Grant **Accessibility** for global hotkeys and **Screen Recording** for snapshots in System Settings → Privacy & Security.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var toolbarTab: some View {
        Form {
            Section("Visibility") {
                Toggle("Show toolbar", isOn: $appState.showToolbar)
            }

            Section("Appearance") {
                Toggle("Transparent background (vibrancy)", isOn: $appState.toolbarUseTransparentBackground)
                Slider(value: $appState.toolbarOpacity, in: 0.3...1.0) {
                    Text("Opacity")
                }
            }

            Section("Position") {
                Picker("Dock", selection: $appState.toolbarDock) {
                    Text("Floating").tag(ToolbarDock.floating)
                    Text("Left edge").tag(ToolbarDock.left)
                    Text("Right edge").tag(ToolbarDock.right)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsTab: some View {
        Form {
            Section {
                Text("Click a shortcut field and press your desired key. Prefer **⌥** or **⌃** modifiers for toggle/clear so typing isn't interrupted. Press **Esc** to cancel recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reset all shortcuts to defaults") {
                    shortcutStore.resetToDefaults()
                }
            }

            Section("Actions") {
                ShortcutRecorderRow(action: .toggleDrawing, store: shortcutStore)
                ShortcutRecorderRow(action: .stopDrawing, store: shortcutStore)
                ShortcutRecorderRow(action: .clearAll, store: shortcutStore)
                ShortcutRecorderRow(action: .undo, store: shortcutStore)
                ShortcutRecorderRow(action: .redo, store: shortcutStore)
                ShortcutRecorderRow(action: .snapshot, store: shortcutStore)
            }

            Section("Tools") {
                ForEach([ShortcutAction.toolPen, .toolHighlighter, .toolArrow, .toolRectangle, .toolEllipse, .toolText, .toolEraser]) { action in
                    ShortcutRecorderRow(action: action, store: shortcutStore)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutRecorderRow: View {
    let action: ShortcutAction
    @ObservedObject var store: ShortcutStore

    var body: some View {
        HStack {
            Text(action.label)
            Spacer()
            KeyRecorderView(
                keyCode: Binding(
                    get: { store.shortcut(for: action).keyCode },
                    set: { store.update(action: action, keyCode: $0, carbonModifiers: store.shortcut(for: action).carbonModifiers) }
                ),
                carbonModifiers: Binding(
                    get: { store.shortcut(for: action).carbonModifiers },
                    set: { store.update(action: action, keyCode: store.shortcut(for: action).keyCode, carbonModifiers: $0) }
                )
            )
            .frame(width: 120, height: 28)
        }
    }
}
