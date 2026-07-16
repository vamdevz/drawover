import AppKit
import CoreGraphics

enum AnnotationKind: Equatable {
    case stroke(points: [CGPoint], lineWidth: CGFloat, color: NSColor, opacity: CGFloat, isHighlighter: Bool)
    case arrow(from: CGPoint, to: CGPoint, lineWidth: CGFloat, color: NSColor)
    case rectangle(rect: CGRect, lineWidth: CGFloat, color: NSColor, filled: Bool)
    case ellipse(rect: CGRect, lineWidth: CGFloat, color: NSColor, filled: Bool)
    case text(content: String, origin: CGPoint, fontSize: CGFloat, color: NSColor)
    case spotlight(rect: CGRect, cornerRadius: CGFloat, dimOpacity: CGFloat)
    case measure(from: CGPoint, to: CGPoint, label: String)
}

struct Annotation: Identifiable, Equatable {
    let id: UUID
    var kind: AnnotationKind
    /// CGDirectDisplayID for the screen this annotation was drawn on.
    var displayID: UInt32

    init(id: UUID = UUID(), kind: AnnotationKind, displayID: UInt32 = 0) {
        self.id = id
        self.kind = kind
        self.displayID = displayID
    }
}

extension AnnotationKind {
    func draw(in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        switch self {
        case let .stroke(points, lineWidth, color, opacity, isHighlighter):
            guard points.count > 1 else { break }
            context.setStrokeColor(color.withAlphaComponent(opacity).cgColor)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            if isHighlighter {
                context.setBlendMode(.multiply)
            }
            context.beginPath()
            context.move(to: points[0])
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()

        case let .arrow(from, to, lineWidth, color):
            drawArrow(context: context, from: from, to: to, lineWidth: lineWidth, color: color)

        case let .rectangle(rect, lineWidth, color, filled):
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
            if filled {
                context.setFillColor(color.withAlphaComponent(0.15).cgColor)
                context.fill(rect)
            }
            context.stroke(rect)

        case let .ellipse(rect, lineWidth, color, filled):
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
            if filled {
                context.setFillColor(color.withAlphaComponent(0.15).cgColor)
                context.fillEllipse(in: rect)
            }
            context.strokeEllipse(in: rect)

        case let .text(content, origin, fontSize, color):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: color
            ]
            let size = (content as NSString).size(withAttributes: attributes)
            (content as NSString).draw(in: CGRect(origin: origin, size: size), withAttributes: attributes)

        case let .spotlight(rect, cornerRadius, dimOpacity):
            break // Rendered separately as overlay mask

        case let .measure(from, to, label):
            drawMeasure(context: context, from: from, to: to, label: label)
        }
    }

    func translated(by delta: CGPoint) -> AnnotationKind {
        switch self {
        case let .stroke(points, lineWidth, color, opacity, isHighlighter):
            return .stroke(
                points: points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) },
                lineWidth: lineWidth,
                color: color,
                opacity: opacity,
                isHighlighter: isHighlighter
            )
        case let .arrow(from, to, lineWidth, color):
            return .arrow(
                from: CGPoint(x: from.x + delta.x, y: from.y + delta.y),
                to: CGPoint(x: to.x + delta.x, y: to.y + delta.y),
                lineWidth: lineWidth,
                color: color
            )
        case let .rectangle(rect, lineWidth, color, filled):
            return .rectangle(
                rect: rect.offsetBy(dx: delta.x, dy: delta.y),
                lineWidth: lineWidth,
                color: color,
                filled: filled
            )
        case let .ellipse(rect, lineWidth, color, filled):
            return .ellipse(
                rect: rect.offsetBy(dx: delta.x, dy: delta.y),
                lineWidth: lineWidth,
                color: color,
                filled: filled
            )
        case let .text(content, origin, fontSize, color):
            return .text(
                content: content,
                origin: CGPoint(x: origin.x + delta.x, y: origin.y + delta.y),
                fontSize: fontSize,
                color: color
            )
        case let .spotlight(rect, cornerRadius, dimOpacity):
            return .spotlight(
                rect: rect.offsetBy(dx: delta.x, dy: delta.y),
                cornerRadius: cornerRadius,
                dimOpacity: dimOpacity
            )
        case let .measure(from, to, label):
            return .measure(
                from: CGPoint(x: from.x + delta.x, y: from.y + delta.y),
                to: CGPoint(x: to.x + delta.x, y: to.y + delta.y),
                label: label
            )
        }
    }

    func boundingRect(padding: CGFloat = 0) -> CGRect? {
        switch self {
        case let .stroke(points, lineWidth, _, _, _):
            guard let first = points.first else { return nil }
            var rect = CGRect(origin: first, size: .zero)
            for point in points.dropFirst() {
                rect = rect.union(CGRect(origin: point, size: .zero))
            }
            let inset = -max(lineWidth, padding)
            return rect.insetBy(dx: inset, dy: inset)
        case let .arrow(from, to, lineWidth, _):
            let rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
            let inset = -max(lineWidth, padding)
            return rect.insetBy(dx: inset, dy: inset)
        case let .rectangle(rect, _, _, _), let .ellipse(rect, _, _, _), let .spotlight(rect, _, _):
            return rect.insetBy(dx: -padding, dy: -padding)
        case let .text(content, origin, fontSize, _):
            return Self.textBounds(content: content, origin: origin, fontSize: fontSize, padding: padding)
        case let .measure(from, to, _):
            let rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
            return rect.insetBy(dx: -padding, dy: -padding)
        }
    }

    static func textBounds(content: String, origin: CGPoint, fontSize: CGFloat, padding: CGFloat = 10) -> CGRect {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        ]
        let size = (content as NSString).size(withAttributes: attrs)
        return CGRect(origin: origin, size: size).insetBy(dx: -padding, dy: -padding)
    }

    private func drawArrow(context: CGContext, from: CGPoint, to: CGPoint, lineWidth: CGFloat, color: NSColor) {
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        context.beginPath()
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()

        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength: CGFloat = max(12, lineWidth * 4)
        let headAngle: CGFloat = .pi / 7

        let p1 = CGPoint(
            x: to.x - headLength * cos(angle - headAngle),
            y: to.y - headLength * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: to.x - headLength * cos(angle + headAngle),
            y: to.y - headLength * sin(angle + headAngle)
        )

        context.beginPath()
        context.move(to: to)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
    }

    private func drawMeasure(context: CGContext, from: CGPoint, to: CGPoint, label: String) {
        context.setStrokeColor(NSColor.systemYellow.cgColor)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [6, 4])

        context.beginPath()
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 - 14)
        let padding: CGFloat = 6
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        let bg = CGRect(
            x: mid.x - size.width / 2 - padding,
            y: mid.y - size.height / 2 - padding / 2,
            width: size.width + padding * 2,
            height: size.height + padding
        )
        context.setFillColor(NSColor.systemYellow.withAlphaComponent(0.9).cgColor)
        context.fill(bg)
        (label as NSString).draw(
            at: CGPoint(x: bg.minX + padding, y: bg.minY + padding / 2),
            withAttributes: attrs
        )

        for point in [from, to] {
            context.setFillColor(NSColor.systemYellow.cgColor)
            context.fillEllipse(in: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
        }
    }
}
