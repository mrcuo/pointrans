import CoreGraphics
import Foundation

struct HoverIntentConfiguration: Equatable, Sendable {
    var anchorRadius: CGFloat = 5
    var rearmRadius: CGFloat = 18
    var maximumVelocity: CGFloat = 90
    var dwellDuration: TimeInterval = 0.25
    var maximumStationaryRetries = 1
}

enum HoverIntentState: Equatable, Sendable {
    case idle
    case armed(anchor: CGPoint, generation: UInt64)
    case dwelling(anchor: CGPoint, generation: UInt64)
    case extracting(anchor: CGPoint, generation: UInt64)
    case preview(anchor: CGPoint, sessionID: UUID)
    case pinned(anchor: CGPoint, sessionID: UUID)
}

enum HoverIntentAction: Equatable, Sendable {
    case scheduleDwell(generation: UInt64, delay: TimeInterval)
    case cancelDwell
    case extract(anchor: CGPoint, generation: UInt64)
    case cancelExtraction
    case dismissPreview
}

struct HoverIntentMachine: Sendable {
    private(set) var state: HoverIntentState = .idle
    private(set) var generation: UInt64 = 0
    private var lastPoint: CGPoint?
    private var lastTimestamp: TimeInterval?
    private var stationaryRetryCount = 0
    var configuration: HoverIntentConfiguration

    init(configuration: HoverIntentConfiguration = .init()) {
        self.configuration = configuration
    }

    mutating func modifierPressed(at point: CGPoint, timestamp: TimeInterval) -> [HoverIntentAction] {
        generation &+= 1
        lastPoint = point
        lastTimestamp = timestamp
        stationaryRetryCount = 0
        state = .armed(anchor: point, generation: generation)
        return beginDwelling(at: point)
    }

    mutating func pointerMoved(to point: CGPoint, timestamp: TimeInterval) -> [HoverIntentAction] {
        let velocity = pointerVelocity(to: point, timestamp: timestamp)
        defer {
            lastPoint = point
            lastTimestamp = timestamp
        }

        switch state {
        case .idle, .pinned:
            return []

        case .preview(let anchor, _):
            if distance(anchor, point) > configuration.rearmRadius {
                generation &+= 1
                stationaryRetryCount = 0
                state = .armed(anchor: point, generation: generation)
                return [.dismissPreview] + beginDwelling(at: point)
            }
            return []

        case .extracting(let anchor, _):
            if distance(anchor, point) > configuration.rearmRadius {
                generation &+= 1
                stationaryRetryCount = 0
                state = .armed(anchor: point, generation: generation)
                return [.cancelExtraction] + beginDwelling(at: point)
            }
            return []

        case .armed(let anchor, _), .dwelling(let anchor, _):
            if distance(anchor, point) > configuration.anchorRadius || velocity > configuration.maximumVelocity {
                generation &+= 1
                stationaryRetryCount = 0
                state = .armed(anchor: point, generation: generation)
                return [.cancelDwell] + beginDwelling(at: point)
            }
            return []
        }
    }

    mutating func dwellElapsed(generation expected: UInt64) -> [HoverIntentAction] {
        guard case .dwelling(let anchor, let current) = state, current == expected else { return [] }
        state = .extracting(anchor: anchor, generation: current)
        return [.extract(anchor: anchor, generation: current)]
    }

    mutating func extractionSucceeded(sessionID: UUID, generation expected: UInt64) {
        guard case .extracting(let anchor, let current) = state, current == expected else { return }
        state = .preview(anchor: anchor, sessionID: sessionID)
    }

    mutating func extractionFailed(generation expected: UInt64) -> [HoverIntentAction] {
        guard case .extracting(let anchor, let current) = state, current == expected else { return [] }
        guard stationaryRetryCount < configuration.maximumStationaryRetries else {
            state = .armed(anchor: anchor, generation: current)
            return []
        }
        stationaryRetryCount += 1
        generation &+= 1
        state = .armed(anchor: anchor, generation: generation)
        return beginDwelling(at: anchor)
    }

    mutating func pinPreview() {
        guard case .preview(let anchor, let sessionID) = state else { return }
        state = .pinned(anchor: anchor, sessionID: sessionID)
    }

    mutating func closePinned() {
        reset()
    }

    mutating func reset() {
        generation &+= 1
        state = .idle
        lastPoint = nil
        lastTimestamp = nil
        stationaryRetryCount = 0
    }

    mutating func modifierReleased() -> [HoverIntentAction] {
        let actions: [HoverIntentAction]
        switch state {
        case .dwelling, .armed: actions = [.cancelDwell]
        case .extracting: actions = [.cancelExtraction]
        case .preview: actions = [.dismissPreview]
        case .pinned, .idle: actions = []
        }
        if case .pinned = state {
            return actions
        }
        state = .idle
        stationaryRetryCount = 0
        return actions
    }

    private mutating func beginDwelling(at point: CGPoint) -> [HoverIntentAction] {
        state = .dwelling(anchor: point, generation: generation)
        return [.scheduleDwell(generation: generation, delay: configuration.dwellDuration)]
    }

    private func pointerVelocity(to point: CGPoint, timestamp: TimeInterval) -> CGFloat {
        guard let lastPoint, let lastTimestamp else { return 0 }
        let elapsed = max(timestamp - lastTimestamp, 0.001)
        return distance(lastPoint, point) / elapsed
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
