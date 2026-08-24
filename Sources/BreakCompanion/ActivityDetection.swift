import CoreGraphics
import Foundation

/// The only activity data used by routine integrity detection: aggregate ages exposed by
/// macOS. No event values, locations, applications, or event streams are retained.
struct LocalActivitySignal: Equatable {
    let keyboardIdle: TimeInterval
    let mouseMovementIdle: TimeInterval
    let mouseClickIdle: TimeInterval
    let scrollWheelIdle: TimeInterval
    let mouseDragIdle: TimeInterval

    var pointerIdle: TimeInterval {
        min(mouseMovementIdle, min(mouseDragIdle, min(mouseClickIdle, scrollWheelIdle)))
    }

    var workActivityIdle: TimeInterval {
        min(mouseMovementIdle, keyboardIdle)
    }

    init(keyboardIdle: TimeInterval, pointerIdle: TimeInterval) {
        self.init(
            keyboardIdle: keyboardIdle,
            mouseMovementIdle: pointerIdle,
            mouseClickIdle: .infinity,
            scrollWheelIdle: .infinity
        )
    }

    init(
        keyboardIdle: TimeInterval,
        mouseMovementIdle: TimeInterval,
        mouseClickIdle: TimeInterval,
        scrollWheelIdle: TimeInterval,
        mouseDragIdle: TimeInterval = .infinity
    ) {
        self.keyboardIdle = keyboardIdle
        self.mouseMovementIdle = mouseMovementIdle
        self.mouseClickIdle = mouseClickIdle
        self.scrollWheelIdle = scrollWheelIdle
        self.mouseDragIdle = mouseDragIdle
    }

    static func current() -> LocalActivitySignal {
        LocalActivitySignal(
            keyboardIdle: secondsSinceLastEvent(.keyDown),
            mouseMovementIdle: secondsSinceLastEvent(.mouseMoved),
            mouseClickIdle: min(
                secondsSinceLastEvent(.leftMouseDown),
                min(
                    secondsSinceLastEvent(.rightMouseDown),
                    secondsSinceLastEvent(.otherMouseDown)
                )
            ),
            scrollWheelIdle: secondsSinceLastEvent(.scrollWheel),
            mouseDragIdle: min(
                secondsSinceLastEvent(.leftMouseDragged),
                min(
                    secondsSinceLastEvent(.rightMouseDragged),
                    secondsSinceLastEvent(.otherMouseDragged)
                )
            )
        )
    }

    static func currentWorkActivity() -> LocalActivitySignal {
        LocalActivitySignal(
            keyboardIdle: secondsSinceLastEvent(.keyDown),
            mouseMovementIdle: secondsSinceLastEvent(.mouseMoved),
            mouseClickIdle: .infinity,
            scrollWheelIdle: .infinity
        )
    }

    private static func secondsSinceLastEvent(_ eventType: CGEventType) -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: eventType
        )
    }

    func hasKeyboardActivity(comparedTo previous: LocalActivitySignal?, window: TimeInterval, tolerance: TimeInterval) -> Bool {
        keyboardIdle <= window
            || previous.map { keyboardIdle + tolerance < $0.keyboardIdle } ?? false
    }

    func hasPointerActivity(comparedTo previous: LocalActivitySignal?, window: TimeInterval, tolerance: TimeInterval) -> Bool {
        pointerIdle <= window
            || previous.map { pointerIdle + tolerance < $0.pointerIdle } ?? false
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
    static let companionProtectionBudget: TimeInterval = 30
    static let activityResetTolerance: TimeInterval = 0.5
    static let sustainedActivityWindow: TimeInterval = 1
    /// Reaching for a companion control also moves the pointer age, so pointer evidence
    /// has to survive consecutive polls.
    static let pointerPersistencePolls = 2

    func hasKeyboardActivity(previousSignal: LocalActivitySignal?, currentSignal: LocalActivitySignal) -> Bool {
        currentSignal.hasKeyboardActivity(
            comparedTo: previousSignal,
            window: Self.sustainedActivityWindow,
            tolerance: Self.activityResetTolerance
        )
    }

    func hasPointerActivity(previousSignal: LocalActivitySignal?, currentSignal: LocalActivitySignal) -> Bool {
        currentSignal.hasPointerActivity(
            comparedTo: previousSignal,
            window: Self.sustainedActivityWindow,
            tolerance: Self.activityResetTolerance
        )
    }

    /// True while a poll cannot qualify as resumed work, whatever the activity ages say.
    func suppressesActivity(
        elapsedSinceStart: TimeInterval,
        isPaused: Bool,
        companionInteractionRemaining: TimeInterval
    ) -> Bool {
        elapsedSinceStart < Self.initialGracePeriod || isPaused || companionInteractionRemaining > 0
    }

    func decision(
        elapsedSinceStart: TimeInterval,
        isPaused: Bool,
        companionInteractionRemaining: TimeInterval,
        hasKeyboardActivity: Bool,
        consecutivePointerActivityPolls: Int
    ) -> RoutineActivityDecision {
        let pointerQualifies = consecutivePointerActivityPolls >= Self.pointerPersistencePolls
        guard hasKeyboardActivity || pointerQualifies else {
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
    private(set) var consecutivePointerActivityPolls = 0
    private(set) var companionProtectionUsed: TimeInterval = 0
    private let policy = RoutineActivityPolicy()

    mutating func start(at date: Date, signal: LocalActivitySignal) {
        startedAt = date
        previousSignal = signal
        companionProtectedUntil = nil
        consecutivePointerActivityPolls = 0
        companionProtectionUsed = 0
    }

    /// Budget-capped so repeated grants can never suppress detection for a whole routine.
    mutating func noteCompanionInteraction(at date: Date) {
        let currentEnd = max(companionProtectedUntil ?? date, date)
        let requestedEnd = date.addingTimeInterval(RoutineActivityPolicy.companionInteractionTolerance)
        let remainingBudget = max(0, RoutineActivityPolicy.companionProtectionBudget - companionProtectionUsed)
        let granted = min(max(0, requestedEnd.timeIntervalSince(currentEnd)), remainingBudget)
        guard granted > 0 else { return }
        companionProtectionUsed += granted
        companionProtectedUntil = currentEnd.addingTimeInterval(granted)
    }

    mutating func decision(
        at date: Date,
        isPaused: Bool,
        companionHasKeyboardFocus: Bool = false,
        signal: LocalActivitySignal
    ) -> RoutineActivityDecision {
        let previous = previousSignal
        previousSignal = signal
        let keyboardActive = policy.hasKeyboardActivity(previousSignal: previous, currentSignal: signal)
        let pointerActive = policy.hasPointerActivity(previousSignal: previous, currentSignal: signal)
        consecutivePointerActivityPolls = pointerActive ? consecutivePointerActivityPolls + 1 : 0
        guard let startedAt else { return .noNewActivity }
        // Typing goes to whichever window has key focus, so keystrokes while the companion
        // holds it are companion interaction - budgeted like every other control grant.
        if companionHasKeyboardFocus && keyboardActive {
            noteCompanionInteraction(at: date)
        }
        let elapsedSinceStart = date.timeIntervalSince(startedAt)
        let remainingProtection = max(0, (companionProtectedUntil ?? date).timeIntervalSince(date))
        let decision = policy.decision(
            elapsedSinceStart: elapsedSinceStart,
            isPaused: isPaused,
            companionInteractionRemaining: remainingProtection,
            hasKeyboardActivity: keyboardActive,
            consecutivePointerActivityPolls: consecutivePointerActivityPolls
        )
        // Pointer persistence has to be established by unprotected polls, so a reach whose
        // polls fall inside grace, pause, or control protection cannot carry over.
        if policy.suppressesActivity(
            elapsedSinceStart: elapsedSinceStart,
            isPaused: isPaused,
            companionInteractionRemaining: remainingProtection
        ) {
            consecutivePointerActivityPolls = 0
        }
        return decision
    }

    mutating func reset() {
        startedAt = nil
        previousSignal = nil
        companionProtectedUntil = nil
        consecutivePointerActivityPolls = 0
        companionProtectionUsed = 0
    }
}
