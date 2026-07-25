import SwiftUI

enum DrawingTool: String, CaseIterable, Identifiable {
    case pen
    case rectangle
    case arrow
    case highlighter
    case ellipse
    case text
    case eraser

    var id: String { rawValue }

    /// Tools shown in the toolbar.
    static let toolbarTools: [DrawingTool] = [
        .pen, .rectangle, .arrow, .highlighter, .ellipse, .text, .eraser
    ]

    var label: String {
        switch self {
        case .pen: return "Pen"
        case .rectangle: return "Rectangle"
        case .arrow: return "Arrow"
        case .highlighter: return "Highlighter"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .eraser: return "Eraser"
        }
    }

    var icon: String {
        switch self {
        case .pen: return "pencil.tip"
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .highlighter: return "highlighter"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .eraser: return "eraser"
        }
    }

    var shortcut: String {
        switch self {
        case .pen: return "1"
        case .rectangle: return "2"
        case .arrow: return "3"
        case .highlighter: return "4"
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
