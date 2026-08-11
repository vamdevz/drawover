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
///
/// Order matters: polygonal shapes are preferred over circles, because a square’s
/// isoperimetric quotient (~0.78) looks “fairly round” and was previously stolen by ellipse matching.
enum PenShapeRecognizer {
    static func recognize(_ rawPoints: [CGPoint], forcedStraight: Bool) -> PenShapeRecognition {
        let points = cleaned(rawPoints)
        guard let first = points.first, let last = points.last, points.count >= 2 else {
            return .freehand(points)
        }

        if forcedStraight {
            return .line(from: first, to: last)
        }

        if !isClosed(points), isNearlyStraight(points) {
            return .line(from: first, to: last)
        }

        guard isClosed(points), pathLength(points) >= 70 else {
            if isNearlyStraight(points) {
                return .line(from: first, to: last)
            }
            return .freehand(points)
        }

        let corners = simplifiedCorners(points)
        let circularity = shapeCircularity(points)

        // 1) Triangle — strong 3-corner structure
        if let triangle = recognizeTriangle(points, corners: corners, circularity: circularity) {
            return .triangle(a: triangle.0, b: triangle.1, c: triangle.2)
        }

        // 2) Rectangle / square — boxy perimeter fit (before circle)
        if let rect = recognizeRectangle(points, corners: corners, circularity: circularity) {
            return .rectangle(rect)
        }

        // 3) Circle / ellipse — only when clearly round and not polygonal
        if let ellipse = recognizeEllipse(points, corners: corners, circularity: circularity) {
            return .ellipse(ellipse)
        }

        if isNearlyStraight(points) {
            return .line(from: first, to: last)
        }
        return .freehand(points)
    }

    // MARK: - Cleaning / geometry helpers

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
        max(36, pathLength(points) * 0.18)
    }

    private static func isClosed(_ points: [CGPoint]) -> Bool {
        guard let first = points.first, let last = points.last, points.count >= 6 else { return false }
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

    private static func shapeCircularity(_ points: [CGPoint]) -> CGFloat {
        let area = abs(shoelaceArea(points))
        let peri = pathLength(points)
        guard peri > 0 else { return 0 }
        return (4 * CGFloat.pi * area) / (peri * peri)
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
        (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y)) / 2
    }

    private static func average(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / CGFloat(values.count)
    }

    // MARK: - Corner simplification (Douglas–Peucker)

    /// Closed-stroke corner vertices, ordered around the shape.
    private static func simplifiedCorners(_ points: [CGPoint]) -> [CGPoint] {
        let ring = stripClosingDuplicate(points)
        guard ring.count >= 4 else { return ring }

        let box = boundingBox(ring)
        let diagonal = hypot(box.width, box.height)
        let epsilon = max(10, diagonal * 0.055)

        // Close the loop for simplification, then drop the duplicate end.
        let loop = ring + [ring[0]]
        var simplified = douglasPeucker(loop, epsilon: epsilon)
        if simplified.count >= 2, distance(simplified.first!, simplified.last!) <= epsilon * 1.5 {
            simplified.removeLast()
        }

        // If DP kept too many wiggly points, keep the sharpest turns only.
        if simplified.count > 6 {
            return dominantCorners(points, minAngle: 35, maxAngle: 150, limit: 5)
        }
        return simplified
    }

    private static func douglasPeucker(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count >= 3 else { return points }

        var maxDistance: CGFloat = 0
        var index = 0
        let end = points.count - 1
        for i in 1..<end {
            let d = distanceToSegment(points[i], points[0], points[end])
            if d > maxDistance {
                maxDistance = d
                index = i
            }
        }

        if maxDistance > epsilon {
            let left = douglasPeucker(Array(points[0...index]), epsilon: epsilon)
            let right = douglasPeucker(Array(points[index...end]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        }
        return [points[0], points[end]]
    }

    private static func dominantCorners(
        _ points: [CGPoint],
        minAngle: CGFloat,
        maxAngle: CGFloat,
        limit: Int
    ) -> [CGPoint] {
        let ring = stripClosingDuplicate(points)
        guard ring.count >= 6 else { return [] }

        let mergeDistance = max(14, max(boundingBox(ring).width, boundingBox(ring).height) * 0.07)
        var candidates: [(point: CGPoint, sharpness: CGFloat)] = []

        for index in 0..<ring.count {
            let prev = ring[(index - 1 + ring.count) % ring.count]
            let cur = ring[index]
            let next = ring[(index + 1) % ring.count]
            if distance(prev, cur) < 5 || distance(cur, next) < 5 { continue }
            let angle = turningAngleDegrees(prev, cur, next)
            // Sharpness: how far from 180° (straight).
            let sharpness = 180 - angle
            if angle >= minAngle, angle <= maxAngle {
                candidates.append((cur, sharpness))
            }
        }

        candidates.sort { $0.sharpness > $1.sharpness }

        var corners: [CGPoint] = []
        for candidate in candidates {
            if corners.contains(where: { distance($0, candidate.point) < mergeDistance }) {
                continue
            }
            corners.append(candidate.point)
            if corners.count >= limit { break }
        }

        let center = CGPoint(
            x: corners.map(\.x).reduce(0, +) / CGFloat(max(corners.count, 1)),
            y: corners.map(\.y).reduce(0, +) / CGFloat(max(corners.count, 1))
        )
        corners.sort {
            atan2($0.y - center.y, $0.x - center.x) < atan2($1.y - center.y, $1.x - center.x)
        }
        return corners
    }

    private static func turningAngleDegrees(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        let v1 = CGPoint(x: a.x - b.x, y: a.y - b.y)
        let v2 = CGPoint(x: c.x - b.x, y: c.y - b.y)
        let len1 = hypot(v1.x, v1.y)
        let len2 = hypot(v2.x, v2.y)
        guard len1 > 0.001, len2 > 0.001 else { return 180 }
        var cosTheta = (v1.x * v2.x + v1.y * v2.y) / (len1 * len2)
        cosTheta = min(1, max(-1, cosTheta))
        return acos(cosTheta) * 180 / .pi
    }

    // MARK: - Triangle

    private static func recognizeTriangle(
        _ points: [CGPoint],
        corners: [CGPoint],
        circularity: CGFloat
    ) -> (CGPoint, CGPoint, CGPoint)? {
        // Circles shouldn't become triangles.
        if circularity >= 0.88 { return nil }

        var verts = corners
        if verts.count != 3 {
            // Fallback: sharpest 3 corners from angle scan.
            verts = dominantCorners(points, minAngle: 28, maxAngle: 165, limit: 3)
        }
        guard verts.count == 3 else { return nil }

        let area = abs(triangleArea(verts[0], verts[1], verts[2]))
        guard area >= 350 else { return nil }

        let sideThreshold = max(12, sqrt(area) * 0.16)
        let nearSides = points.filter { point in
            min(
                distanceToSegment(point, verts[0], verts[1]),
                distanceToSegment(point, verts[1], verts[2]),
                distanceToSegment(point, verts[2], verts[0])
            ) <= sideThreshold
        }.count
        let fit = CGFloat(nearSides) / CGFloat(points.count)
        guard fit >= 0.58 else { return nil }

        // Reject if it fits a box better than a triangle (boxy doodles).
        let box = boundingBox(points)
        let boxBorderFit = rectangleBorderFit(points, box: box)
        if boxBorderFit >= 0.78, circularity >= 0.7 {
            return nil
        }

        return (verts[0], verts[1], verts[2])
    }

    // MARK: - Rectangle / square

    private static func recognizeRectangle(
        _ points: [CGPoint],
        corners: [CGPoint],
        circularity: CGFloat
    ) -> CGRect? {
        let box = boundingBox(points)
        guard box.width >= 24, box.height >= 24 else { return nil }

        // A filled-looking round blob: circularity of square ≈ 0.785, circle ≈ 1.0
        // Accept rectangles when circularity is below a clear circle.
        if circularity >= 0.90 { return nil }

        let borderFit = rectangleBorderFit(points, box: box)
        let hasFourCorners = corners.count == 4 || corners.count == 5
        let hasBoxyCorners = (3...5).contains(corners.count)

        // Need either a strong border hug or clear box corners.
        guard borderFit >= 0.62 || (hasBoxyCorners && borderFit >= 0.52) else {
            return nil
        }

        // If it looks very round and has no corners, leave it for ellipse.
        if circularity >= 0.86, !hasFourCorners, borderFit < 0.72 {
            return nil
        }

        if hasFourCorners {
            let ordered = Array(corners.prefix(4))
            // Soft angle check — freehand boxes are rarely perfect.
            if !cornerAnglesNearRight(ordered, tolerance: 38), borderFit < 0.7 {
                return nil
            }
        }

        let aspect = box.width / max(box.height, 1)
        if aspect > 0.75, aspect < 1.33 {
            let side = (box.width + box.height) / 2
            let center = CGPoint(x: box.midX, y: box.midY)
            return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        }
        return box
    }

    private static func rectangleBorderFit(_ points: [CGPoint], box: CGRect) -> CGFloat {
        let threshold = max(10, min(box.width, box.height) * 0.16)
        let nearBorder = points.filter { distanceToRectBorder($0, box) <= threshold }.count
        return CGFloat(nearBorder) / CGFloat(max(points.count, 1))
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

    private static func cornerAnglesNearRight(_ corners: [CGPoint], tolerance: CGFloat) -> Bool {
        guard corners.count == 4 else { return false }
        var good = 0
        for index in 0..<4 {
            let prev = corners[(index + 3) % 4]
            let cur = corners[index]
            let next = corners[(index + 1) % 4]
            let angle = turningAngleDegrees(prev, cur, next)
            if abs(angle - 90) <= tolerance {
                good += 1
            }
        }
        return good >= 3
    }

    // MARK: - Ellipse / circle

    private static func recognizeEllipse(
        _ points: [CGPoint],
        corners: [CGPoint],
        circularity: CGFloat
    ) -> CGRect? {
        let box = boundingBox(points)
        guard box.width >= 32, box.height >= 32 else { return nil }

        // Must be clearly round. Squares (~0.78) must not pass.
        guard circularity >= 0.88 else { return nil }

        // Polygonal strokes with obvious corners are not circles.
        if corners.count == 3 || corners.count == 4 {
            return nil
        }

        let center = CGPoint(x: box.midX, y: box.midY)
        let radii = points.map { distance($0, center) }
        guard let mean = average(radii), mean > 14 else { return nil }
        let variance = radii.reduce(CGFloat(0)) { $0 + ($1 - mean) * ($1 - mean) } / CGFloat(radii.count)
        let std = sqrt(variance)
        guard std / mean <= 0.18 else { return nil }

        // Also reject if most points hug an AABB border (box doodle).
        if rectangleBorderFit(points, box: box) >= 0.75, circularity < 0.93 {
            return nil
        }

        let aspect = box.width / max(box.height, 1)
        if aspect > 0.82, aspect < 1.22 {
            let side = (box.width + box.height) / 2
            return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        }
        return box.insetBy(dx: -1, dy: -1)
    }
}
