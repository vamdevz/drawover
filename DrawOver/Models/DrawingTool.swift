import SwiftUI

enum DrawingTool: String, CaseIterable, Identifiable {
    case pen
    case rectangle
    case arrow
    case person
    case triangle
    case ellipse
    case text
    case eraser
    case highlighter

    var id: String { rawValue }

    /// Tools shown in the toolbar (arrow = 3rd, person = 4th; marker last).
    static let toolbarTools: [DrawingTool] = [
        .pen, .rectangle, .arrow, .person, .triangle, .ellipse, .text, .eraser, .highlighter
    ]

    var label: String {
        switch self {
        case .pen: return "Pen"
        case .rectangle: return "Rectangle"
        case .arrow: return "Arrow"
        case .person: return "Person"
        case .triangle: return "Triangle"
        case .ellipse: return "Circle"
        case .text: return "Text"
        case .eraser: return "Eraser"
        case .highlighter: return "Marker"
        }
    }

    var icon: String {
        switch self {
        case .pen: return "pencil.tip"
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .person: return "person"
        case .triangle: return "triangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .eraser: return "eraser"
        case .highlighter: return "highlighter"
        }
    }

    var shortcut: String {
        switch self {
        case .pen: return "1"
        case .rectangle: return "2"
        case .arrow: return "3"
        case .person: return "4"
        case .triangle: return "5"
        case .ellipse: return "6"
        case .text: return "7"
        case .eraser: return "8"
        case .highlighter: return "9"
        }
    }

    var defaultLineWidth: CGFloat {
        switch self {
        case .pen: return 2
        case .highlighter: return 24
        case .arrow: return 3
        case .rectangle, .ellipse, .triangle, .person: return 3
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

/// What a bare Control tap cycles while drawing.
enum ControlTapToolCycle: String, CaseIterable, Identifiable {
    case allTools
    case penRectangle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allTools: return "All tools"
        case .penRectangle: return "Pen ↔ Rectangle"
        }
    }

    var tools: [DrawingTool] {
        switch self {
        case .allTools: return DrawingTool.toolbarTools
        case .penRectangle: return [.pen, .rectangle]
        }
    }
}
