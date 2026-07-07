import SwiftUI

enum DrawingTool: String, CaseIterable, Identifiable {
    case pen
    case highlighter
    case arrow
    case rectangle
    case ellipse
    case text
    case eraser

    var id: String { rawValue }

    /// Tools shown in the toolbar (spotlight & measure removed).
    static let toolbarTools: [DrawingTool] = [
        .pen, .highlighter, .arrow, .rectangle, .ellipse, .text, .eraser
    ]

    var label: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .eraser: return "Eraser"
        }
    }

    var icon: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .eraser: return "eraser"
        }
    }

    var shortcut: String {
        switch self {
        case .pen: return "1"
        case .highlighter: return "2"
        case .arrow: return "3"
        case .rectangle: return "4"
        case .ellipse: return "5"
        case .text: return "6"
        case .eraser: return "7"
        }
    }

    var defaultLineWidth: CGFloat {
        switch self {
        case .pen: return 3
        case .highlighter: return 24
        case .arrow: return 3
        case .rectangle, .ellipse: return 3
        case .text: return 0
        case .eraser: return 20
        }
    }

    var supportsLineWidth: Bool {
        self != .text
    }
}

enum ToolbarDock: String, CaseIterable {
    case floating
    case left
    case right
}
