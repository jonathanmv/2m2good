import Foundation

struct ActiveUseTick: Equatable {
    let activeSeconds: TimeInterval
    let didResetAfterIdle: Bool
    let shouldOfferCheckIn: Bool
}

/// Tracks active-use time without turning a delayed timer callback into work.
/// A new active sample after the idle threshold starts a fresh active interval.
struct ActiveUseTracker {
    static let maximumTimerDelta: TimeInterval = 2

    let activeInterval: TimeInterval
    let idleThreshold: TimeInterval
    private(set) var accumulatedActiveTime: TimeInterval = 0

    private var lastTickAt: Date
    private var lastActiveSampleAt: Date?
    private var lastSampleWasIdle = false

    init(
        activeInterval: TimeInterval,
        idleThreshold: TimeInterval,
        startedAt: Date
    ) {
        self.activeInterval = activeInterval
        self.idleThreshold = idleThreshold
        lastTickAt = startedAt
    }

    mutating func tick(at date: Date, userIsActive: Bool) -> ActiveUseTick {
        let elapsedSinceLastTick = max(0, date.timeIntervalSince(lastTickAt))
        let delta = min(Self.maximumTimerDelta, elapsedSinceLastTick)
        lastTickAt = date

        guard userIsActive else {
            lastSampleWasIdle = true
            return result(didResetAfterIdle: false)
        }

        let didResetAfterIdle = lastSampleWasIdle || (lastActiveSampleAt.map {
            date.timeIntervalSince($0) >= idleThreshold
        } ?? false)
        if didResetAfterIdle {
            accumulatedActiveTime = 0
        }
        lastSampleWasIdle = false
        lastActiveSampleAt = date
        accumulatedActiveTime += delta

        return result(didResetAfterIdle: didResetAfterIdle)
    }

    mutating func reset(at date: Date) {
        accumulatedActiveTime = 0
        lastTickAt = date
        lastActiveSampleAt = nil
        lastSampleWasIdle = false
    }

    private func result(didResetAfterIdle: Bool) -> ActiveUseTick {
        ActiveUseTick(
            activeSeconds: accumulatedActiveTime,
            didResetAfterIdle: didResetAfterIdle,
            shouldOfferCheckIn: accumulatedActiveTime >= activeInterval
        )
    }
}
