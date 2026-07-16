import AppKit
import Combine
import SwiftUI

/// Toolbar panel stays above drawing overlays and accepts clicks without activating the app.
final class ToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)) + 2)
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            orderFrontRegardless()
            makeKey()
            ToolbarFrameTracker.update(from: self)
            NotificationCenter.default.post(name: .toolbarDidReceiveClick, object: nil)
        }
        super.sendEvent(event)
    }
}

/// Allows tool buttons to respond on the first click while another app is active.
final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class ToolbarPanelController: NSWindowController {
    private let appState: AppState
    private var hostingView: ClickableHostingView<ToolbarView>?
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState

        let panel = ToolbarPanel(contentRect: NSRect(x: 100, y: 200, width: 72, height: 500))

        super.init(window: panel)

        let toolbar = ToolbarView(appState: appState, onDock: { [weak self] edge in
            self?.dock(to: edge)
        })
        let hosting = ClickableHostingView(rootView: toolbar)
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        hostingView = hosting

        positionInitially()
        observeAppState()
        window?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard appState.showToolbar, appState.isAppEnabled else { return }
        bringToFront()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func bringToFront() {
        guard let window else { return }
        window.orderFrontRegardless()
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)) + 2)
        ToolbarFrameTracker.update(from: window)
    }

    private func observeAppState() {
        appState.$toolbarDock
            .sink { [weak self] dock in
                switch dock {
                case .left: self?.dock(to: .left)
                case .right: self?.dock(to: .right)
                case .floating: break
                }
            }
            .store(in: &cancellables)

        appState.$showToolbar
            .combineLatest(appState.$isAppEnabled)
            .sink { [weak self] visible, enabled in
                if visible && enabled {
                    self?.bringToFront()
                } else {
                    self?.hide()
                }
            }
            .store(in: &cancellables)

        appState.$isDrawingModeActive
            .sink { [weak self] _ in
                self?.bringToFront()
            }
            .store(in: &cancellables)
    }

    private func positionInitially() {
        guard let screen = NSScreen.main, let window else { return }
        let frame = window.frame
        let x = screen.visibleFrame.maxX - frame.width - 16
        let y = screen.visibleFrame.midY - frame.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func dock(to edge: ToolbarDock) {
        guard let screen = NSScreen.main, let window else { return }
        let frame = window.frame
        let visible = screen.visibleFrame
        let y = visible.midY - frame.height / 2

        switch edge {
        case .left:
            window.setFrameOrigin(NSPoint(x: visible.minX + 8, y: y))
        case .right:
            window.setFrameOrigin(NSPoint(x: visible.maxX - frame.width - 8, y: y))
        case .floating:
            break
        }
        bringToFront()
    }
}

extension ToolbarPanelController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        ToolbarFrameTracker.update(from: window)
        if let screen = window?.screen {
            appState.markDisplayActive(screen.displayID)
        }
    }

    func windowDidResize(_ notification: Notification) {
        ToolbarFrameTracker.update(from: window)
    }
}

struct ToolbarView: View {
    @ObservedObject var appState: AppState
    var onDock: (ToolbarDock) -> Void

    private let presetColors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .white, .black
    ]

    var body: some View {
        VStack(spacing: 8) {
            header
            toolbarDivider
            toolButtons
            shapeToolSection
            if appState.selectedTool.supportsLineWidth {
                lineWidthControl
            }
            colorStrip
            actionButtons
            dockButtons
        }
        .padding(8)
        .frame(width: 64)
        .background(toolbarBackground)
        .opacity(appState.toolbarOpacity)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        )
        .animation(nil, value: appState.selectedTool)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var toolbarBackground: some View {
        if appState.toolbarUseTransparentBackground {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var header: some View {
        Button {
            guard appState.isAppEnabled else { return }
            appState.toggleDrawingMode()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: appState.isDrawingModeActive ? "pencil.and.outline" : "pencil.slash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(appState.isDrawingModeActive ? .green : .secondary)
                    .frame(height: 20)

                Circle()
                    .fill(appState.isDrawingModeActive ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
            .frame(width: 40, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarButtonStyle())
        .disabled(!appState.isAppEnabled)
        .opacity(appState.isAppEnabled ? 1 : 0.4)
        .help(appState.isDrawingModeActive ? "Click to stop · Esc to clear" : "Click to start drawing")
    }

    private var toolButtons: some View {
        VStack(spacing: 4) {
            ForEach(DrawingTool.toolbarTools) { tool in
                let isSelected = appState.selectedTool == tool && appState.isDrawingModeActive
                ToolButton(
                    icon: tool.icon,
                    isSelected: isSelected,
                    action: {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            appState.selectTool(tool)
                        }
                    }
                )
                .help(toolHelp(for: tool, isSelected: isSelected))
            }
        }
    }

    @ViewBuilder
    private var shapeToolSection: some View {
        if (appState.selectedTool == .rectangle || appState.selectedTool == .ellipse),
           appState.isDrawingModeActive {
            Button {
                appState.captionAfterShape.toggle()
            } label: {
                Image(systemName: appState.captionAfterShape ? "text.bubble.fill" : "text.bubble")
                    .font(.system(size: 13))
                    .frame(width: 36, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(appState.captionAfterShape ? Color.accentColor.opacity(0.25) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(appState.captionAfterShape ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
            }
            .buttonStyle(ToolbarButtonStyle())
            .help("Double-click a box or arrow to caption. ⌃-drag = arrow. ⌥-tap = delete.")
        }
    }

    private func toolHelp(for tool: DrawingTool, isSelected: Bool) -> String {
        let shortcut = shortcutDisplay(for: tool)
        let base = isSelected ? "\(tool.label) — click again to stop" : tool.label
        return shortcut.isEmpty ? base : "\(base) (\(shortcut))"
    }

    private func shortcutDisplay(for tool: DrawingTool) -> String {
        let action: ShortcutAction? = switch tool {
        case .pen: .toolPen
        case .highlighter: .toolHighlighter
        case .arrow: .toolArrow
        case .rectangle: .toolRectangle
        case .ellipse: .toolEllipse
        case .text: .toolText
        case .eraser: .toolEraser
        }
        guard let action else { return "" }
        return appState.shortcutStore.shortcut(for: action).displayString
    }

    private var colorStrip: some View {
        VStack(spacing: 4) {
            ForEach(presetColors, id: \.description) { color in
                Button {
                    appState.strokeColor = color
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    appState.strokeColor == color ? Color.accentColor : Color.clear,
                                    lineWidth: 2
                                )
                        )
                }
                .buttonStyle(ToolbarButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var lineWidthControl: some View {
        VStack(spacing: 4) {
            Text("Stroke")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("\(Int(appState.lineWidth))")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            HStack(spacing: 10) {
                Button {
                    appState.lineWidth = max(1, appState.lineWidth - 2)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)

                Button {
                    appState.lineWidth = min(40, appState.lineWidth + 2)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 4) {
            ActionButton(icon: "arrow.uturn.backward", help: "Undo (\(appState.shortcutLabel(for: .undo)))") {
                appState.undo()
            }
            ActionButton(icon: "trash", help: "Clear all (\(appState.shortcutLabel(for: .clearAll)))") {
                appState.clearAll(dismissText: true)
            }
            ActionButton(icon: "camera", help: "Snapshot (\(appState.shortcutLabel(for: .snapshot)))") {
                NotificationCenter.default.post(name: .takeSnapshot, object: nil)
            }
        }
    }

    private var dockButtons: some View {
        HStack(spacing: 2) {
            Button { onDock(.left); appState.toolbarDock = .left } label: {
                Image(systemName: "arrow.left.to.line")
                    .font(.system(size: 10))
            }
            .buttonStyle(ToolbarButtonStyle())
            .help("Dock left")

            Button { onDock(.right); appState.toolbarDock = .right } label: {
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: 10))
            }
            .buttonStyle(ToolbarButtonStyle())
            .help("Dock right")
        }
        .foregroundStyle(.secondary)
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

private struct ToolButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 36, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarButtonStyle())
    }
}

private struct ActionButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 36, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarButtonStyle())
        .help(help)
    }
}

extension Notification.Name {
    static let takeSnapshot = Notification.Name("DrawOver.takeSnapshot")
    static let toolbarDidReceiveClick = Notification.Name("DrawOver.toolbarDidReceiveClick")
}
