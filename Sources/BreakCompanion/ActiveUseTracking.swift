import Foundation

struct ActiveUseTick: Equatable {
    let activeSeconds: TimeInterval
    let didResetAfterIdle: Bool
    let shouldOfferCheckIn: Bool
}

/// Tracks active-use time without turning a delayed timer callback into work.
/// A new active sample after the idle threshold starts a fresh active interval.
struct ActiveUseTracker {
    struct PersistenceState: Codable, Equatable {
        let accumulatedActiveTime: TimeInterval
        let lastActiveSampleAt: Date?
        let lastSampleWasIdle: Bool
    }

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
        startedAt: Date,
        persistenceState: PersistenceState? = nil
    ) {
        self.activeInterval = activeInterval
        self.idleThreshold = idleThreshold
        lastTickAt = startedAt
        guard let persistenceState,
              persistenceState.accumulatedActiveTime.isFinite,
              persistenceState.accumulatedActiveTime >= 0 else { return }
        accumulatedActiveTime = min(activeInterval, persistenceState.accumulatedActiveTime)
        lastActiveSampleAt = persistenceState.lastActiveSampleAt.flatMap { $0 <= startedAt ? $0 : nil }
        lastSampleWasIdle = persistenceState.lastSampleWasIdle
    }

    var persistenceState: PersistenceState {
        PersistenceState(
            accumulatedActiveTime: accumulatedActiveTime,
            lastActiveSampleAt: lastActiveSampleAt,
            lastSampleWasIdle: lastSampleWasIdle
        )
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
