import CoreGraphics

struct SafeCorridor: Equatable, Sendable {
    let anchor: CGPoint
    let target: CGRect
    let padding: CGFloat

    func contains(_ point: CGPoint) -> Bool {
        if target.insetBy(dx: -padding, dy: -padding).contains(point) { return true }

        let expanded = target.insetBy(dx: -padding, dy: -padding)
        let corners = [
            CGPoint(x: expanded.minX, y: expanded.minY),
            CGPoint(x: expanded.maxX, y: expanded.minY),
            CGPoint(x: expanded.maxX, y: expanded.maxY),
            CGPoint(x: expanded.minX, y: expanded.maxY)
        ]
        let hull = convexHull([anchor] + corners)
        return pointInsideConvexPolygon(point, polygon: hull)
    }

    private func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard sorted.count > 2 else { return sorted }
        var lower: [CGPoint] = []
        for point in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower.last!, point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }
        var upper: [CGPoint] = []
        for point in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper.last!, point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    private func pointInsideConvexPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var sign: CGFloat?
        for index in polygon.indices {
            let edge = cross(polygon[index], polygon[(index + 1) % polygon.count], point)
            if abs(edge) < 0.001 { continue }
            let current = edge > 0 ? CGFloat(1) : CGFloat(-1)
            if let sign, sign != current { return false }
            sign = current
        }
        return true
    }

    private func cross(_ origin: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)
    }
}
