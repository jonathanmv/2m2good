import Foundation

struct ActiveUseTick: Equatable {
    let activeSeconds: TimeInterval
    /// Retained as a transition signal for existing callers. Inactivity no longer
    /// clears the accumulated credit when activity resumes.
    let didResetAfterIdle: Bool
    let shouldOfferCheckIn: Bool
}

/// Tracks cadence credit: active time earns at 1x and inactive time spends it at
/// 0.5x. Delayed timer callbacks are bounded so an observation gap cannot earn work.
struct ActiveUseTracker {
    struct PersistenceState: Codable, Equatable {
        let accumulatedActiveTime: TimeInterval
        let lastActiveSampleAt: Date?
        let lastSampleWasIdle: Bool
        /// Optional so checkpoints written before system-boundary decay remain readable.
        var lastTickAt: Date? = nil
        var systemInactiveBoundary: Bool? = nil
    }

    static let maximumTimerDelta: TimeInterval = 2
    static let inactiveDecayRate: Double = 0.5

    private(set) var activeInterval: TimeInterval
    let idleThreshold: TimeInterval
    private(set) var accumulatedActiveTime: TimeInterval = 0

    private var lastTickAt: Date
    private var lastActiveSampleAt: Date?
    private var lastSampleWasIdle = false
    private var observationSuspended = false
    private var systemInactiveBoundary = false

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
        systemInactiveBoundary = persistenceState.systemInactiveBoundary ?? false
        if systemInactiveBoundary,
           let persistedLastTickAt = persistenceState.lastTickAt,
           persistedLastTickAt <= startedAt {
            lastTickAt = persistedLastTickAt
        }
    }

    var persistenceState: PersistenceState {
        PersistenceState(
            accumulatedActiveTime: accumulatedActiveTime,
            lastActiveSampleAt: lastActiveSampleAt,
            lastSampleWasIdle: lastSampleWasIdle,
            lastTickAt: systemInactiveBoundary ? lastTickAt : nil,
            systemInactiveBoundary: systemInactiveBoundary
        )
    }

    mutating func tick(at date: Date, userIsActive: Bool) -> ActiveUseTick {
        let elapsedSinceLastTick = max(0, date.timeIntervalSince(lastTickAt))
        let activeDelta = min(Self.maximumTimerDelta, elapsedSinceLastTick)
        lastTickAt = date

        guard userIsActive else {
            // Inactive time is a debit, not a reset. Use the full elapsed span so
            // a delayed inactive sample still applies the intended half-rate decay.
            decayCredit(for: elapsedSinceLastTick)
            lastSampleWasIdle = true
            return result(didResetAfterIdle: false, shouldOfferCheckIn: false)
        }

        // A previously inactive sample makes the span since that sample inactive.
        // A long gap between active samples is treated the same way so delayed
        // callbacks and sleep gaps cannot turn into active credit. Settings calls
        // suspend() first and deliberately opt out of this gap discount.
        let delayedActiveGap = !observationSuspended
            && !lastSampleWasIdle
            && elapsedSinceLastTick >= idleThreshold
        let inactiveBoundaryGap = !observationSuspended && systemInactiveBoundary
        if delayedActiveGap || inactiveBoundaryGap {
            decayCredit(for: elapsedSinceLastTick)
        }
        let resumedAfterIdle = !observationSuspended && (
            lastSampleWasIdle || delayedActiveGap || inactiveBoundaryGap
        )
        observationSuspended = false
        systemInactiveBoundary = false
        lastSampleWasIdle = false
        lastActiveSampleAt = date
        accumulatedActiveTime = min(activeInterval, accumulatedActiveTime + activeDelta)

        return result(
            didResetAfterIdle: resumedAfterIdle,
            // Let the first active sample re-anchor after inactivity. If that
            // sample reaches the threshold, the next active sample presents it;
            // this avoids surprising someone immediately on returning to work.
            shouldOfferCheckIn: !resumedAfterIdle && accumulatedActiveTime >= activeInterval
        )
    }

    /// Advances the timer's observation point without granting or spending cadence
    /// credit. This keeps time spent in a non-timing surface, such as Settings, out of
    /// both the delta and the delayed-callback calculation.
    mutating func suspend(at date: Date) {
        lastTickAt = date
        lastActiveSampleAt = date
        lastSampleWasIdle = false
        observationSuspended = true
        systemInactiveBoundary = false
    }

    /// Changes the cadence without turning time spent in Settings into active use.
    /// Existing active credit is intentionally retained; the new cadence applies to
    /// the active interval already in progress and future intervals.
    mutating func reconfigure(activeInterval: TimeInterval, at date: Date) {
        guard activeInterval.isFinite, activeInterval > 0 else { return }
        self.activeInterval = activeInterval
        accumulatedActiveTime = min(activeInterval, accumulatedActiveTime)
        lastTickAt = date
        lastActiveSampleAt = date
        lastSampleWasIdle = false
        observationSuspended = true
        systemInactiveBoundary = false
    }

    mutating func reset(at date: Date) {
        accumulatedActiveTime = 0
        lastTickAt = date
        lastActiveSampleAt = nil
        lastSampleWasIdle = false
        observationSuspended = false
        systemInactiveBoundary = false
    }

    /// Applies a system-inactive boundary without discarding work credit. The span
    /// after this boundary is discounted when activity returns, covering sleep gaps
    /// for which no ordinary inactive timer samples can arrive.
    @discardableResult
    mutating func markInactive(at date: Date) -> ActiveUseTick {
        observationSuspended = false
        let result = tick(at: date, userIsActive: false)
        systemInactiveBoundary = true
        return result
    }

    private mutating func decayCredit(for elapsed: TimeInterval) {
        accumulatedActiveTime = max(
            0,
            accumulatedActiveTime - elapsed * Self.inactiveDecayRate
        )
    }

    private func result(
        didResetAfterIdle: Bool,
        shouldOfferCheckIn: Bool
    ) -> ActiveUseTick {
        ActiveUseTick(
            activeSeconds: accumulatedActiveTime,
            didResetAfterIdle: didResetAfterIdle,
            shouldOfferCheckIn: shouldOfferCheckIn
        )
    }
}
