import CoreGraphics
import Foundation

/// The only activity data used by routine integrity detection: aggregate ages exposed by
/// macOS. No event values, locations, applications, or event streams are retained.
struct LocalActivitySignal: Equatable {
    let keyboardIdle: TimeInterval
    let pointerIdle: TimeInterval

    static func current() -> LocalActivitySignal {
        LocalActivitySignal(
            keyboardIdle: CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: .keyDown
            ),
            pointerIdle: CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: .mouseMoved
            )
        )
    }

    func hasActivityReset(from previous: LocalActivitySignal, tolerance: TimeInterval) -> Bool {
        keyboardIdle + tolerance < previous.keyboardIdle
            || pointerIdle + tolerance < previous.pointerIdle
    }

    /// True when either aggregate age shows input inside the most recent polling window, so
    /// input that keeps going is still visible after a sample was ignored as protected.
    func hasSustainedActivity(within window: TimeInterval) -> Bool {
        min(keyboardIdle, pointerIdle) <= window
    }
}

enum RoutineActivityDecision: Equatable {
    case noNewActivity
    case initialGracePeriod
    case companionInteraction
    case paused
    case resumedWork
}

/// Conservative, deterministic rules for interpreting aggregate activity ages.
struct RoutineActivityPolicy {
    static let initialGracePeriod: TimeInterval = 5
    static let companionInteractionTolerance: TimeInterval = 3
    static let activityResetTolerance: TimeInterval = 0.5
    static let sustainedActivityWindow: TimeInterval = 1

    func decision(
        elapsedSinceStart: TimeInterval,
        isPaused: Bool,
        companionInteractionRemaining: TimeInterval,
        previousSignal: LocalActivitySignal?,
        currentSignal: LocalActivitySignal
    ) -> RoutineActivityDecision {
        let hasResetEdge = previousSignal.map {
            currentSignal.hasActivityReset(from: $0, tolerance: Self.activityResetTolerance)
        } ?? false
        let isStillActive = currentSignal.hasSustainedActivity(within: Self.sustainedActivityWindow)
        guard hasResetEdge || isStillActive else {
            return .noNewActivity
        }
        if elapsedSinceStart < Self.initialGracePeriod {
            return .initialGracePeriod
        }
        if isPaused {
            return .paused
        }
        if companionInteractionRemaining > 0 {
            return .companionInteraction
        }
        return .resumedWork
    }
}

struct RoutineActivityDetector {
    private(set) var startedAt: Date?
    private(set) var previousSignal: LocalActivitySignal?
    private(set) var companionProtectedUntil: Date?
    private let policy = RoutineActivityPolicy()

    mutating func start(at date: Date, signal: LocalActivitySignal) {
        startedAt = date
        previousSignal = signal
        companionProtectedUntil = nil
    }

    mutating func noteCompanionInteraction(at date: Date) {
        let protectedUntil = date.addingTimeInterval(RoutineActivityPolicy.companionInteractionTolerance)
        companionProtectedUntil = max(companionProtectedUntil ?? date, protectedUntil)
    }

    mutating func decision(
        at date: Date,
        isPaused: Bool,
        signal: LocalActivitySignal
    ) -> RoutineActivityDecision {
        let previous = previousSignal
        previousSignal = signal
        guard let startedAt else { return .noNewActivity }
        let remainingProtection = max(0, (companionProtectedUntil ?? date).timeIntervalSince(date))
        return policy.decision(
            elapsedSinceStart: date.timeIntervalSince(startedAt),
            isPaused: isPaused,
            companionInteractionRemaining: remainingProtection,
            previousSignal: previous,
            currentSignal: signal
        )
    }

    mutating func reset() {
        startedAt = nil
        previousSignal = nil
        companionProtectedUntil = nil
    }
}
