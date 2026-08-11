import AppKit
import Carbon.HIToolbox

enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case toggleDrawing
    case clearAll
    case undo
    case redo
    case snapshot
    case stopDrawing
    case toolPen
    case toolRectangle
    case toolArrow
    case toolHighlighter
    case toolEllipse
    case toolTriangle
    case toolPerson
    case toolText
    case toolEraser

    var id: String { rawValue }

    var label: String {
        switch self {
        case .toggleDrawing: return "Toggle drawing"
        case .clearAll: return "Clear all"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .snapshot: return "Snapshot"
        case .stopDrawing: return "Undo (Esc) / exit (Esc×2)"
        case .toolPen: return "Pen"
        case .toolRectangle: return "Rectangle"
        case .toolArrow: return "Arrow"
        case .toolHighlighter: return "Marker"
        case .toolEllipse: return "Circle"
        case .toolTriangle: return "Triangle"
        case .toolPerson: return "Person"
        case .toolText: return "Text"
        case .toolEraser: return "Eraser"
        }
    }

    var hotkeyID: UInt32 {
        switch self {
        case .toggleDrawing: return 1
        case .clearAll: return 2
        case .undo: return 3
        case .redo: return 14
        case .snapshot: return 4
        case .stopDrawing: return 5
        case .toolPen: return 6
        case .toolHighlighter: return 7
        case .toolArrow: return 8
        case .toolRectangle: return 9
        case .toolEllipse: return 10
        case .toolText: return 11
        case .toolEraser: return 12
        case .toolTriangle: return 13
        case .toolPerson: return 15
        }
    }

    var linkedTool: DrawingTool? {
        switch self {
        case .toolPen: return .pen
        case .toolHighlighter: return .highlighter
        case .toolArrow: return .arrow
        case .toolRectangle: return .rectangle
        case .toolEllipse: return .ellipse
        case .toolTriangle: return .triangle
        case .toolPerson: return .person
        case .toolText: return .text
        case .toolEraser: return .eraser
        default: return nil
        }
    }
}

struct KeyboardShortcut: Codable, Equatable, Identifiable {
    let action: ShortcutAction
    var keyCode: UInt32
    var carbonModifiers: UInt32

    var id: String { action.rawValue }

    var displayString: String {
        KeyboardShortcut.displayString(keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    static func displayString(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    private static func keyCodeToString(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Fwd Del"
        case kVK_Tab: return "Tab"
        default: return "Key \(keyCode)"
        }
    }

    static func fromEvent(_ event: NSEvent) -> KeyboardShortcut? {
        guard let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty else { return nil }
        let keyCode = UInt32(event.keyCode)
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
        return KeyboardShortcut(action: .toggleDrawing, keyCode: keyCode, carbonModifiers: mods)
    }
}

@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    @Published private(set) var shortcuts: [ShortcutAction: KeyboardShortcut] = [:]

    private let storageKey = "DrawOver.keyboardShortcuts"

    init() {
        load()
    }

    static var defaults: [ShortcutAction: KeyboardShortcut] {
        [
            // Control+Shift+D avoids stealing plain "d" while typing in other apps.
            .toggleDrawing: KeyboardShortcut(action: .toggleDrawing, keyCode: UInt32(kVK_ANSI_D), carbonModifiers: UInt32(controlKey | shiftKey)),
            .clearAll: KeyboardShortcut(action: .clearAll, keyCode: UInt32(kVK_ANSI_C), carbonModifiers: UInt32(optionKey)),
            .undo: KeyboardShortcut(action: .undo, keyCode: UInt32(kVK_ANSI_Z), carbonModifiers: UInt32(cmdKey)),
            .redo: KeyboardShortcut(action: .redo, keyCode: UInt32(kVK_ANSI_Z), carbonModifiers: UInt32(cmdKey | shiftKey)),
            .snapshot: KeyboardShortcut(action: .snapshot, keyCode: UInt32(kVK_ANSI_S), carbonModifiers: UInt32(cmdKey)),
            .stopDrawing: KeyboardShortcut(action: .stopDrawing, keyCode: UInt32(kVK_Escape), carbonModifiers: 0),
            .toolPen: KeyboardShortcut(action: .toolPen, keyCode: UInt32(kVK_ANSI_1), carbonModifiers: UInt32(controlKey)),
            .toolRectangle: KeyboardShortcut(action: .toolRectangle, keyCode: UInt32(kVK_ANSI_2), carbonModifiers: UInt32(controlKey)),
            .toolArrow: KeyboardShortcut(action: .toolArrow, keyCode: UInt32(kVK_ANSI_3), carbonModifiers: UInt32(controlKey)),
            .toolPerson: KeyboardShortcut(action: .toolPerson, keyCode: UInt32(kVK_ANSI_4), carbonModifiers: UInt32(controlKey)),
            .toolTriangle: KeyboardShortcut(action: .toolTriangle, keyCode: UInt32(kVK_ANSI_5), carbonModifiers: UInt32(controlKey)),
            .toolEllipse: KeyboardShortcut(action: .toolEllipse, keyCode: UInt32(kVK_ANSI_6), carbonModifiers: UInt32(controlKey)),
            .toolText: KeyboardShortcut(action: .toolText, keyCode: UInt32(kVK_ANSI_7), carbonModifiers: UInt32(controlKey)),
            .toolEraser: KeyboardShortcut(action: .toolEraser, keyCode: UInt32(kVK_ANSI_8), carbonModifiers: UInt32(controlKey)),
            .toolHighlighter: KeyboardShortcut(action: .toolHighlighter, keyCode: UInt32(kVK_ANSI_9), carbonModifiers: UInt32(controlKey)),
        ]
    }

    func shortcut(for action: ShortcutAction) -> KeyboardShortcut {
        shortcuts[action] ?? Self.defaults[action]!
    }

    func update(action: ShortcutAction, keyCode: UInt32, carbonModifiers: UInt32) {
        shortcuts[action] = KeyboardShortcut(action: action, keyCode: keyCode, carbonModifiers: carbonModifiers)
        save()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    func update(_ shortcut: KeyboardShortcut) {
        shortcuts[shortcut.action] = shortcut
        save()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    func resetToDefaults() {
        shortcuts = Self.defaults
        save()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    func allShortcuts() -> [KeyboardShortcut] {
        ShortcutAction.allCases.map { shortcut(for: $0) }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: KeyboardShortcut].self, from: data) {
            shortcuts = decoded.reduce(into: [:]) { result, pair in
                if let action = ShortcutAction(rawValue: pair.key) {
                    result[action] = KeyboardShortcut(
                        action: action,
                        keyCode: pair.value.keyCode,
                        carbonModifiers: pair.value.carbonModifiers
                    )
                }
            }
        } else {
            shortcuts = Self.defaults
        }
        migrateBareNumberToolShortcuts()
        migrateLegacyToggleShortcut()
        migrateOptionNumberToolShortcutsToControl()
        migrateRectangleToSecondToolSlot()
        migrateArrowToThirdToolSlot()
        migrateRegionCaptureRemoved()
        migrateTriangleToolSlot()
        migratePersonAndShapeOrder()
        migrateMarkerToBottom()
        migrateArrowPersonThirdFourth()
    }

    /// Upgrade the previous Option+D toggle default to Control+Shift+D.
    private func migrateLegacyToggleShortcut() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "DrawOver.migratedToggleToCtrlShiftD") else { return }
        defaults.set(true, forKey: "DrawOver.migratedToggleToCtrlShiftD")

        let current = shortcuts[.toggleDrawing] ?? Self.defaults[.toggleDrawing]!
        let isLegacyOptionD =
            current.keyCode == UInt32(kVK_ANSI_D) &&
            current.carbonModifiers == UInt32(optionKey)
        guard isLegacyOptionD else { return }

        shortcuts[.toggleDrawing] = Self.defaults[.toggleDrawing]!
        save()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    /// Upgrade old Option+1–7 (and bare 1–7) tool shortcuts to Control+1–7.
    private func migrateOptionNumberToolShortcutsToControl() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "DrawOver.migratedToolsToCtrlNumber") else { return }
        defaults.set(true, forKey: "DrawOver.migratedToolsToCtrlNumber")

        let toolActions: [ShortcutAction] = [
            .toolPen, .toolHighlighter, .toolArrow, .toolRectangle,
            .toolEllipse, .toolTriangle, .toolPerson, .toolText, .toolEraser
        ]
        var changed = false
        for action in toolActions {
            guard let shortcut = shortcuts[action] ?? Self.defaults[action] else { continue }
            let isNumberKey = (Int(shortcut.keyCode) >= kVK_ANSI_1 && Int(shortcut.keyCode) <= kVK_ANSI_9)
            let isOptionOrBare = shortcut.carbonModifiers == UInt32(optionKey) || shortcut.carbonModifiers == 0
            guard isNumberKey, isOptionOrBare else { continue }
            shortcuts[action] = KeyboardShortcut(
                action: action,
                keyCode: shortcut.keyCode,
                carbonModifiers: UInt32(controlKey)
            )
            changed = true
        }
        if changed {
            save()
            NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
        }
    }

    /// Rectangle moves to ⌃2; highlighter/arrow shift to ⌃3/⌃4.
    private func migrateRectangleToSecondToolSlot() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "DrawOver.migratedRectangleToCtrl2") else { return }
        defaults.set(true, forKey: "DrawOver.migratedRectangleToCtrl2")

        let remaps: [(ShortcutAction, UInt32)] = [
            (.toolPen, UInt32(kVK_ANSI_1)),
            (.toolRectangle, UInt32(kVK_ANSI_2)),
            (.toolHighlighter, UInt32(kVK_ANSI_3)),
            (.toolArrow, UInt32(kVK_ANSI_4)),
            (.toolEllipse, UInt32(kVK_ANSI_5)),
            (.toolText, UInt32(kVK_ANSI_6)),
            (.toolEraser, UInt32(kVK_ANSI_7)),
        ]
        for (action, keyCode) in remaps {
            shortcuts[action] = KeyboardShortcut(
                action: action,
                keyCode: keyCode,
                carbonModifiers: UInt32(controlKey)
            )
        }
        save()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    /// Arrow moves to ⌃3; remaining tools shift after it.
    private func migrateArrowToThirdToolSlot() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "DrawOver.migratedArrowToCtrl3") else { return }
        defaults.set(true, forKey: "DrawOver.migratedArrowToCtrl3")

        let remaps: [(ShortcutAction, UInt32)] = [
            (.toolPen, UInt32(kVK_ANSI_1)),
            (.toolRectangle, UInt32(kVK_ANSI_2)),
            (.toolArrow, UInt32(kVK_ANSI_3)),
            (.toolHighlighter, UInt32(kVK_ANSI_4)),
            (.toolEllipse, UInt32(kVK_ANSI_5)),
            (.toolText, UInt32(kVK_ANSI_6)),
            (.toolEraser, UInt32(kVK_ANSI_7)),
        ]
        for (action, keyCode) in remaps {
            shortcuts[action] = KeyboardShortcut(
                action: action,
                keyCode: keyCode,
                carbonModifiers: UInt32(controlKey)
            )
        }
        save()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    /// Restore ⌃4–⌃7 after Region shot was removed.
    private func migrateRegionCaptureRemoved() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "DrawOver.migratedRegionCaptureRemoved") else { return }
        defaults.set(true, forKey: "DrawOver.migratedRegionCaptureRemoved")

        let remaps: [(ShortcutAction, UInt32)] = [
            (.toolPen, UInt32(kVK_ANSI_1)),
            (.toolRectangle, UInt32(kVK_ANSI_2)),
            (.toolArrow, UInt32(kVK_ANSI_3)),
            (.toolHighlighter, UInt32(kVK_ANSI_4)),
            (.toolEllipse, UInt32(kVK_ANSI_5)),
            (.toolText, UInt32(kVK_ANSI_6)),
            (.toolEraser, UInt32(kVK_ANSI_7)),
        ]
        for (action, keyCode) in remaps {
            shortcuts[action] = KeyboardShortcut(
                action: action,
                keyCode: keyCode,
                carbonModifiers: UInt32(controlKey)
            )
        }
        save()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    /// Insert triangle at ⌃6; text/eraser shift to ⌃7/⌃8.
    private func migrateTriangleToolSlot() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "DrawOver.migratedTriangleTool") else { return }
        defaults.set(true, forKey: "DrawOver.migratedTriangleTool")

        let remaps: [(ShortcutAction, UInt32)] = [
            (.toolPen, UInt32(kVK_ANSI_1)),
            (.toolRectangle, UInt32(kVK_ANSI_2)),
            (.toolArrow, UInt32(kVK_ANSI_3)),
            (.toolHighlighter, UInt32(kVK_ANSI_4)),
            (.toolEllipse, UInt32(kVK_ANSI_5)),
            (.toolTriangle, UInt32(kVK_ANSI_6)),
            (.toolText, UInt32(kVK_ANSI_7)),
            (.toolEraser, UInt32(kVK_ANSI_8)),
        ]
        for (action, keyCode) in remaps {
            shortcuts[action] = KeyboardShortcut(
                action: action,
                keyCode: keyCode,
                carbonModifiers: UInt32(controlKey)
            )
        }
        save()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    /// Arrow → ⌃3, Person → ⌃4; remaining tools shift after.
    private func migrateArrowPersonThirdFourth() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "DrawOver.migratedArrowPersonThirdFourth") else { return }
        defaults.set(true, forKey: "DrawOver.migratedArrowPersonThirdFourth")

        let remaps: [(ShortcutAction, UInt32)] = [
            (.toolPen, UInt32(kVK_ANSI_1)),
            (.toolRectangle, UInt32(kVK_ANSI_2)),
            (.toolArrow, UInt32(kVK_ANSI_3)),
            (.toolPerson, UInt32(kVK_ANSI_4)),
            (.toolTriangle, UInt32(kVK_ANSI_5)),
            (.toolEllipse, UInt32(kVK_ANSI_6)),
            (.toolText, UInt32(kVK_ANSI_7)),
            (.toolEraser, UInt32(kVK_ANSI_8)),
            (.toolHighlighter, UInt32(kVK_ANSI_9)),
        ]
        for (action, keyCode) in remaps {
            shortcuts[action] = KeyboardShortcut(
                action: action,
                keyCode: keyCode,
                carbonModifiers: UInt32(controlKey)
            )
        }
        save()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    /// Marker/highlighter moves to the bottom of the toolbar (⌃9).
    private func migrateMarkerToBottom() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "DrawOver.migratedMarkerToBottom") else { return }
        defaults.set(true, forKey: "DrawOver.migratedMarkerToBottom")

        let remaps: [(ShortcutAction, UInt32)] = [
            (.toolPen, UInt32(kVK_ANSI_1)),
            (.toolRectangle, UInt32(kVK_ANSI_2)),
            (.toolTriangle, UInt32(kVK_ANSI_3)),
            (.toolEllipse, UInt32(kVK_ANSI_4)),
            (.toolArrow, UInt32(kVK_ANSI_5)),
            (.toolPerson, UInt32(kVK_ANSI_6)),
            (.toolText, UInt32(kVK_ANSI_7)),
            (.toolEraser, UInt32(kVK_ANSI_8)),
            (.toolHighlighter, UInt32(kVK_ANSI_9)),
        ]
        for (action, keyCode) in remaps {
            shortcuts[action] = KeyboardShortcut(
                action: action,
                keyCode: keyCode,
                carbonModifiers: UInt32(controlKey)
            )
        }
        save()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    /// Triangle→⌃3, circle→⌃4; person at ⌃7; text/eraser ⌃8/⌃9.
    private func migratePersonAndShapeOrder() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "DrawOver.migratedPersonAndShapeOrder") else { return }
        defaults.set(true, forKey: "DrawOver.migratedPersonAndShapeOrder")

        let remaps: [(ShortcutAction, UInt32)] = [
            (.toolPen, UInt32(kVK_ANSI_1)),
            (.toolRectangle, UInt32(kVK_ANSI_2)),
            (.toolTriangle, UInt32(kVK_ANSI_3)),
            (.toolEllipse, UInt32(kVK_ANSI_4)),
            (.toolArrow, UInt32(kVK_ANSI_5)),
            (.toolHighlighter, UInt32(kVK_ANSI_6)),
            (.toolPerson, UInt32(kVK_ANSI_7)),
            (.toolText, UInt32(kVK_ANSI_8)),
            (.toolEraser, UInt32(kVK_ANSI_9)),
        ]
        for (action, keyCode) in remaps {
            shortcuts[action] = KeyboardShortcut(
                action: action,
                keyCode: keyCode,
                carbonModifiers: UInt32(controlKey)
            )
        }
        save()
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    /// Upgrade old plain 1–7 shortcuts that hijacked the number row in every app.
    private func migrateBareNumberToolShortcuts() {
        let toolActions: [ShortcutAction] = [
            .toolPen, .toolHighlighter, .toolArrow, .toolRectangle,
            .toolEllipse, .toolTriangle, .toolPerson, .toolText, .toolEraser
        ]
        var changed = false
        for action in toolActions {
            guard let shortcut = shortcuts[action] ?? Self.defaults[action] else { continue }
            let isNumberKey = (Int(shortcut.keyCode) >= kVK_ANSI_1 && Int(shortcut.keyCode) <= kVK_ANSI_9)
            if shortcut.carbonModifiers == 0, isNumberKey {
                shortcuts[action] = KeyboardShortcut(
                    action: action,
                    keyCode: shortcut.keyCode,
                    carbonModifiers: UInt32(controlKey)
                )
                changed = true
            }
        }
        if changed { save() }
    }

    private func save() {
        let encoded = shortcuts.reduce(into: [String: KeyboardShortcut]()) { $0[$1.key.rawValue] = $1.value }
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

extension Notification.Name {
    static let shortcutsDidChange = Notification.Name("DrawOver.shortcutsDidChange")
    static let annotationsCleared = Notification.Name("DrawOver.annotationsCleared")
}
