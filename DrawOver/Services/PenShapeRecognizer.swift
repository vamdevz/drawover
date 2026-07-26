import AppKit
import CoreGraphics

/// Result of classifying a freehand pen stroke.
enum PenShapeRecognition: Equatable {
    case line(from: CGPoint, to: CGPoint)
    case rectangle(CGRect)
    case ellipse(CGRect)
    case triangle(a: CGPoint, b: CGPoint, c: CGPoint)
    case freehand([CGPoint])

    func annotationKind(lineWidth: CGFloat, color: NSColor) -> AnnotationKind {
        switch self {
        case let .line(from, to):
            return .stroke(points: [from, to], lineWidth: lineWidth, color: color, opacity: 1, isHighlighter: false)
        case let .rectangle(rect):
            return .rectangle(rect: rect, lineWidth: lineWidth, color: color, filled: false)
        case let .ellipse(rect):
            return .ellipse(rect: rect, lineWidth: lineWidth, color: color, filled: false)
        case let .triangle(a, b, c):
            return .triangle(a: a, b: b, c: c, lineWidth: lineWidth, color: color)
        case let .freehand(points):
            return .stroke(points: points, lineWidth: lineWidth, color: color, opacity: 1, isHighlighter: false)
        }
    }
}

/// Recognizes imperfect freehand strokes as lines, rectangles/squares, ellipses/circles, or triangles.
enum PenShapeRecognizer {
    static func recognize(_ rawPoints: [CGPoint], forcedStraight: Bool) -> PenShapeRecognition {
        let points = cleaned(rawPoints)
        guard let first = points.first, let last = points.last, points.count >= 2 else {
            return .freehand(points)
        }

        if forcedStraight {
            return .line(from: first, to: last)
        }

        let closed = isClosed(points)

        if !closed, isNearlyStraight(points) {
            return .line(from: first, to: last)
        }

        guard closed, pathLength(points) >= 80 else {
            if isNearlyStraight(points) {
                return .line(from: first, to: last)
            }
            return .freehand(points)
        }

        // Prefer smoother closed shapes first, then polygonal ones.
        if let ellipse = recognizeEllipse(points) {
            return .ellipse(ellipse)
        }
        if let triangle = recognizeTriangle(points) {
            return .triangle(a: triangle.0, b: triangle.1, c: triangle.2)
        }
        if let rect = recognizeRectangle(points) {
            return .rectangle(rect)
        }
        if isNearlyStraight(points) {
            return .line(from: first, to: last)
        }
        return .freehand(points)
    }

    // MARK: - Cleaning

    private static func cleaned(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            if let last = result.last, hypot(point.x - last.x, point.y - last.y) < 1.5 {
                continue
            }
            result.append(point)
        }
        return result
    }

    private static func stripClosingDuplicate(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 2,
              let first = points.first,
              let last = points.last,
              hypot(first.x - last.x, first.y - last.y) <= closingThreshold(for: points) else {
            return points
        }
        return Array(points.dropLast())
    }

    private static func closingThreshold(for points: [CGPoint]) -> CGFloat {
        max(28, pathLength(points) * 0.14)
    }

    private static func isClosed(_ points: [CGPoint]) -> Bool {
        guard let first = points.first, let last = points.last, points.count >= 8 else { return false }
        return hypot(first.x - last.x, first.y - last.y) <= closingThreshold(for: points)
    }

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var length: CGFloat = 0
        for index in 1..<points.count {
            length += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
        }
        return length
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    private static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        if dx == 0, dy == 0 { return distance(p, a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)))
        return distance(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    private static func isNearlyStraight(_ points: [CGPoint]) -> Bool {
        guard points.count >= 3, let first = points.first, let last = points.last else {
            return points.count == 2
        }
        let chord = distance(first, last)
        guard chord >= 28 else { return false }
        let maxDeviation = max(6, chord * 0.08)
        for point in points where distanceToSegment(point, first, last) > maxDeviation {
            return false
        }
        return pathLength(points) <= chord * 1.22
    }

    // MARK: - Ellipse / circle

    private static func recognizeEllipse(_ points: [CGPoint]) -> CGRect? {
        let box = boundingBox(points)
        guard box.width >= 36, box.height >= 36 else { return nil }

        let center = CGPoint(x: box.midX, y: box.midY)
        let radii = points.map { distance($0, center) }
        guard let mean = average(radii), mean > 16 else { return nil }
        let variance = radii.reduce(CGFloat(0)) { $0 + ($1 - mean) * ($1 - mean) } / CGFloat(radii.count)
        let std = sqrt(variance)
        // Circles/ellipses stay near a constant radius from the center.
        guard std / mean <= 0.22 else { return nil }

        let area = abs(shoelaceArea(points))
        let peri = pathLength(points)
        guard peri > 0 else { return nil }
        let circularity = (4 * CGFloat.pi * area) / (peri * peri)
        guard circularity >= 0.68 else { return nil }

        // Prefer ellipse recognition over boxy shapes when circularity is strong.
        let aspect = box.width / max(box.height, 1)
        if aspect > 0.82, aspect < 1.22 {
            let side = (box.width + box.height) / 2
            return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        }
        return box.insetBy(dx: -2, dy: -2)
    }

    // MARK: - Rectangle / square

    private static func recognizeRectangle(_ points: [CGPoint]) -> CGRect? {
        let box = boundingBox(points)
        guard box.width >= 28, box.height >= 28 else { return nil }

        let threshold = max(8, min(box.width, box.height) * 0.14)
        let nearBorder = points.filter { distanceToRectBorder($0, box) <= threshold }.count
        let ratio = CGFloat(nearBorder) / CGFloat(points.count)
        guard ratio >= 0.7 else { return nil }

        // Reject blobs that are more circular than rectangular.
        let area = abs(shoelaceArea(points))
        let peri = pathLength(points)
        if peri > 0 {
            let circularity = (4 * CGFloat.pi * area) / (peri * peri)
            if circularity >= 0.82 { return nil }
        }

        let corners = dominantCorners(points, minAngle: 28, maxAngle: 155)
        if corners.count == 4 {
            let anglesOK = cornerAnglesNearRight(corners)
            if !anglesOK { return nil }
        } else if corners.count > 5 {
            return nil
        }

        let aspect = box.width / max(box.height, 1)
        if aspect > 0.78, aspect < 1.28 {
            let side = (box.width + box.height) / 2
            let center = CGPoint(x: box.midX, y: box.midY)
            return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        }
        return box
    }

    private static func distanceToRectBorder(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        if rect.contains(point) {
            return min(
                point.x - rect.minX,
                rect.maxX - point.x,
                point.y - rect.minY,
                rect.maxY - point.y
            )
        }
        let clamped = CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
        return distance(point, clamped)
    }

    private static func cornerAnglesNearRight(_ corners: [CGPoint]) -> Bool {
        guard corners.count == 4 else { return false }
        for index in 0..<4 {
            let prev = corners[(index + 3) % 4]
            let cur = corners[index]
            let next = corners[(index + 1) % 4]
            let angle = turningAngleDegrees(prev, cur, next)
            if abs(angle - 90) > 28 {
                return false
            }
        }
        return true
    }

    // MARK: - Triangle

    private static func recognizeTriangle(_ points: [CGPoint]) -> (CGPoint, CGPoint, CGPoint)? {
        let corners = dominantCorners(points, minAngle: 30, maxAngle: 160)
        guard corners.count == 3 else { return nil }

        let area = abs(triangleArea(corners[0], corners[1], corners[2]))
        guard area >= 400 else { return nil }

        // Most of the stroke should hug the three sides.
        let threshold = max(10, sqrt(area) * 0.12)
        let nearSides = points.filter { point in
            min(
                distanceToSegment(point, corners[0], corners[1]),
                distanceToSegment(point, corners[1], corners[2]),
                distanceToSegment(point, corners[2], corners[0])
            ) <= threshold
        }.count
        guard CGFloat(nearSides) / CGFloat(points.count) >= 0.68 else { return nil }

        return (corners[0], corners[1], corners[2])
    }

    // MARK: - Corners

    private static func dominantCorners(
        _ points: [CGPoint],
        minAngle: CGFloat,
        maxAngle: CGFloat
    ) -> [CGPoint] {
        let ring = stripClosingDuplicate(points)
        guard ring.count >= 6 else { return [] }

        let mergeDistance = max(16, max(boundingBox(ring).width, boundingBox(ring).height) * 0.08)
        var candidates: [(point: CGPoint, angle: CGFloat)] = []

        for index in 0..<ring.count {
            let prev = ring[(index - 1 + ring.count) % ring.count]
            let cur = ring[index]
            let next = ring[(index + 1) % ring.count]
            // Skip nearly collinear micro-steps.
            if distance(prev, cur) < 4 || distance(cur, next) < 4 { continue }
            let angle = turningAngleDegrees(prev, cur, next)
            if angle >= minAngle, angle <= maxAngle {
                candidates.append((cur, angle))
            }
        }

        candidates.sort { $0.angle > $1.angle }

        var corners: [CGPoint] = []
        for candidate in candidates {
            if corners.contains(where: { distance($0, candidate.point) < mergeDistance }) {
                continue
            }
            corners.append(candidate.point)
            if corners.count >= 6 { break }
        }

        // Order around centroid for stable polygon winding.
        let center = CGPoint(
            x: corners.map(\.x).reduce(0, +) / CGFloat(max(corners.count, 1)),
            y: corners.map(\.y).reduce(0, +) / CGFloat(max(corners.count, 1))
        )
        corners.sort {
            atan2($0.y - center.y, $0.x - center.x) < atan2($1.y - center.y, $1.x - center.x)
        }
        return corners
    }

    /// Interior turning angle in degrees (0...180). Sharp corners are near 90 for boxes.
    private static func turningAngleDegrees(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        let v1 = CGPoint(x: a.x - b.x, y: a.y - b.y)
        let v2 = CGPoint(x: c.x - b.x, y: c.y - b.y)
        let len1 = hypot(v1.x, v1.y)
        let len2 = hypot(v2.x, v2.y)
        guard len1 > 0.001, len2 > 0.001 else { return 180 }
        var cosTheta = (v1.x * v2.x + v1.y * v2.y) / (len1 * len2)
        cosTheta = min(1, max(-1, cosTheta))
        let radians = acos(cosTheta)
        return radians * 180 / .pi
    }

    private static func shoelaceArea(_ points: [CGPoint]) -> CGFloat {
        let ring = stripClosingDuplicate(points)
        guard ring.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for index in 0..<ring.count {
            let next = ring[(index + 1) % ring.count]
            sum += ring[index].x * next.y - next.x * ring[index].y
        }
        return sum / 2
    }

    private static func triangleArea(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        ((a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y)) / 2)
    }

    private static func average(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / CGFloat(values.count)
    }
}
