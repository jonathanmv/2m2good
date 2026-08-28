import CoreGraphics
import Foundation

@MainActor
protocol DelayedActionScheduling {
    func schedule(after delay: TimeInterval, action: @escaping () -> Void)
}

@MainActor
struct DelayedActionScheduler: DelayedActionScheduling {
    nonisolated init() {}

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        guard delay > 0 else {
            action()
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            action()
        }
    }
}

@MainActor
final class CompanionStore: ObservableObject {
    enum Mode: Equatable {
        case idle
        case setup
        case configuration
        case checkIn
        case routine
        case complete
    }

    static let checkInPrompt = "Time for a small pause."

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var routine: BreakRoutine
    @Published private(set) var stepIndex = 0
    @Published private(set) var elapsedInStep = 0
    @Published private(set) var isPaused = false
    @Published private(set) var statusText: String?
    @Published private(set) var activityRecoveryExplanation: String?
    @Published private(set) var checkInProgress: Double = 0
    @Published private(set) var nextCheckInRemainingSeconds: TimeInterval = 0
    @Published private(set) var selectedAreas: Set<BodyArea>
    @Published private(set) var selectedCadence: Cadence
    @Published private(set) var isCheckInCollapsed = false
    @Published private(set) var lastCompletedPauseContext: String?

    var onSizeChange: ((Mode) -> Void)?
    /// Set by the app so keystrokes aimed at the companion's own panel are read as
    /// intentional interaction instead of resumed work.
    var companionHasKeyboardFocus: () -> Bool = { false }

    private let speaker: RoutineSpeaking
    private var workInterval: TimeInterval
    private let idleThreshold: TimeInterval
    private let sessionSelection: SessionSelectionStore
    private let bodyAreaPreferences: BodyAreaPreferences
    private let cadencePreferences: CadencePreferences
    private let pauseHistory: PauseHistoryStore
    private let stateStore: CompanionStateStore?
    private let testingIntervalOverride: TimeInterval?
    private var activeUseTracker: ActiveUseTracker
    private var scheduledCheckIn: ScheduledCheckInWindow?
    private let nowProvider: () -> Date
    private let postponementScheduler: any DelayedActionScheduling
    private var timer: Timer?
    private var completionDismissTask: Task<Void, Never>?
    private var completionDismissalState = CompletionDismissalState()
    private var routineActivityDetector = RoutineActivityDetector()
    private let activitySignalProvider: () -> LocalActivitySignal

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        activitySignalProvider: @escaping () -> LocalActivitySignal = LocalActivitySignal.current,
        speaker: RoutineSpeaking? = nil,
        nowProvider: @escaping () -> Date = Date.init,
        postponementScheduler: any DelayedActionScheduling = DelayedActionScheduler(),
        stateStore: CompanionStateStore? = nil
    ) {
        let configuredInterval = Double(environment["BREAK_INTERVAL_SECONDS"] ?? "")
        let cadencePreferences = CadencePreferences(defaults: defaults)
        let initialCadence = cadencePreferences.selectedCadence
        let testingIntervalOverride = configuredInterval.map { max(5, $0) }
        let configuredIdle = Double(environment["BREAK_IDLE_THRESHOLD_SECONDS"] ?? "")
        workInterval = testingIntervalOverride ?? initialCadence.interval
        idleThreshold = max(10, configuredIdle ?? 60)
        sessionSelection = SessionSelectionStore(defaults: defaults)
        bodyAreaPreferences = BodyAreaPreferences(defaults: defaults)
        self.cadencePreferences = cadencePreferences
        pauseHistory = PauseHistoryStore(defaults: defaults)
        self.stateStore = stateStore
        self.testingIntervalOverride = testingIntervalOverride
        self.activitySignalProvider = activitySignalProvider
        self.speaker = speaker ?? GuideSpeaker()
        self.nowProvider = nowProvider
        self.postponementScheduler = postponementScheduler
        let initialNow = nowProvider()
        activeUseTracker = ActiveUseTracker(
            activeInterval: workInterval,
            idleThreshold: idleThreshold,
            startedAt: initialNow
        )
        selectedAreas = bodyAreaPreferences.selectedAreas
        selectedCadence = initialCadence
        routine = BreakRoutine.fallback
        nextCheckInRemainingSeconds = workInterval
        mode = bodyAreaPreferences.shouldPresentFirstRunSetup ? .setup : .idle
        restorePersistedState(at: initialNow)

        startClock()
    }

    deinit {
        timer?.invalidate()
        completionDismissTask?.cancel()
    }

    var currentStep: RoutineStep { routine.steps[stepIndex] }

    var remainingSeconds: Int {
        let completed = routine.steps.prefix(stepIndex).reduce(0) { $0 + $1.duration }
        return max(0, routine.duration - completed - elapsedInStep)
    }

    var progress: Double {
        Double(routine.duration - remainingSeconds) / Double(routine.duration)
    }

    var checkInAccessibilityValue: String {
        BreakProgress.accessibilityValue(
            progress: checkInProgress,
            remainingSeconds: nextCheckInRemainingSeconds
        )
    }

    func offerBreakNow() {
        if mode == .checkIn, isCheckInCollapsed {
            restoreCheckIn()
            return
        }
        showCheckIn(at: nowProvider())
    }

    /// Checkpoints live timer/session state outside the replaceable app bundle so a
    /// graceful quit for an update can resume the same user session.
    func persistState() {
        guard let stateStore else { return }
        let persistedMode: PersistedCompanionMode
        switch mode {
        case .idle, .setup, .configuration: persistedMode = .idle
        case .checkIn: persistedMode = .checkIn
        case .routine: persistedMode = .routine
        case .complete: persistedMode = .complete
        }
        stateStore.save(PersistedCompanionState(
            mode: persistedMode,
            activeUse: activeUseTracker.persistenceState,
            scheduledCheckInStartedAt: scheduledCheckIn?.startedAt,
            scheduledCheckInDueAt: scheduledCheckIn?.dueAt,
            routineMoveIDs: routine.moveIDs,
            stepIndex: stepIndex,
            elapsedInStep: elapsedInStep,
            isPaused: isPaused,
            isCheckInCollapsed: isCheckInCollapsed
        ))
    }

    var canOpenAreaConfiguration: Bool { mode == .idle }

    func collapseCheckIn() {
        guard mode == .checkIn, statusText == nil else { return }
        isCheckInCollapsed = true
        notifySizeChange()
    }

    func restoreCheckIn() {
        guard mode == .checkIn, isCheckInCollapsed else { return }
        isCheckInCollapsed = false
        notifySizeChange()
    }

    var offersBalancedChoice: Bool { mode == .setup || mode == .configuration }

    func openAreaConfiguration() {
        guard canOpenAreaConfiguration else { return }
        mode = .configuration
        notifySizeChange()
    }

    func saveSettings(cadence: Cadence, areas: Set<BodyArea>) {
        guard !areas.isEmpty else { return }
        let cadenceChanged = selectedCadence != cadence
        cadencePreferences.save(cadence: cadence)
        bodyAreaPreferences.save(selectedAreas: areas)
        selectedCadence = cadence
        selectedAreas = bodyAreaPreferences.selectedAreas
        sessionSelection.clearPendingSession()

        if cadenceChanged {
            workInterval = testingIntervalOverride ?? cadence.interval
            activeUseTracker = ActiveUseTracker(
                activeInterval: workInterval,
                idleThreshold: idleThreshold,
                startedAt: nowProvider()
            )
            updateCheckInProgress(at: nowProvider())
        }

        guard offersBalancedChoice else { return }
        mode = .idle
        notifySizeChange()
    }

    // Kept as a small compatibility shim for the existing menu/setup path.
    func saveSelectedAreas(_ areas: Set<BodyArea>) {
        saveSettings(cadence: selectedCadence, areas: areas)
    }

    func continueWithBalancedDefaults() {
        cadencePreferences.save(cadence: selectedCadence)
        bodyAreaPreferences.continueWithBalancedDefaults()
        selectedAreas = []
        sessionSelection.clearPendingSession()
        guard offersBalancedChoice else { return }
        mode = .idle
        notifySizeChange()
    }

    func diagnosticSnapshot(activityIsActive: Bool? = nil) -> CompanionDiagnosticSnapshot {
        let path: ActiveUsePath
        switch mode {
        case .idle where scheduledCheckIn != nil:
            path = .scheduled
        case .idle where activityIsActive ?? userIsActive:
            path = .accumulating
        case .idle:
            path = .waitingForActivity
        default:
            path = .otherwisePaused
        }
        return CompanionDiagnosticSnapshot(
            cadence: selectedCadence,
            selectedAreas: BodyArea.allCases.filter { selectedAreas.contains($0) },
            mode: mode.diagnosticLabel,
            activeUsePath: path
        )
    }

    func diagnosticReport(activityIsActive: Bool? = nil) -> String {
        diagnosticSnapshot(activityIsActive: activityIsActive).report
    }

    func cancelAreaConfiguration() {
        guard mode == .configuration else { return }
        mode = .idle
        notifySizeChange()
    }

    func startRoutine() {
        startRoutine(at: Date(), activitySignal: activitySignalProvider())
    }

    func startRoutine(at date: Date, activitySignal: LocalActivitySignal) {
        cancelCompletionAutoDismiss()
        isCheckInCollapsed = false
        mode = .routine
        stepIndex = 0
        elapsedInStep = 0
        isPaused = false
        statusText = nil
        activityRecoveryExplanation = nil
        routineActivityDetector.start(at: date, signal: activitySignal)
        notifySizeChange()
        speaker.speak(currentStep.spokenInstruction)
    }

    func postpone(minutes: Int) {
        let now = nowProvider()
        isCheckInCollapsed = false
        scheduledCheckIn = ScheduledCheckInWindow(
            startedAt: now,
            dueAt: now.addingTimeInterval(TimeInterval(minutes * 60))
        )
        activeUseTracker.reset(at: now)
        updateCheckInProgress(at: now)
        statusText = minutes == 60 ? "I’ll check back in an hour." : "I’ll check back in \(minutes) minutes."
        activityRecoveryExplanation = nil
        persistState()
        returnToIdle(after: 1.5)
    }

    func postponeUntilTomorrow() {
        let now = nowProvider()
        isCheckInCollapsed = false
        let dueAt = Calendar.current.date(byAdding: .day, value: 1, to: now)
            ?? now.addingTimeInterval(24 * 60 * 60)
        scheduledCheckIn = ScheduledCheckInWindow(startedAt: now, dueAt: dueAt)
        activeUseTracker.reset(at: now)
        updateCheckInProgress(at: now)
        statusText = "See you tomorrow."
        activityRecoveryExplanation = nil
        persistState()
        returnToIdle(after: 1.5)
    }

    /// Called from every interactive surface of the companion itself - its window and its
    /// menu-bar menu - so intentional use of the app is never read as resumed work.
    func noteCompanionInteraction() {
        noteCompanionInteraction(at: Date())
    }

    func noteCompanionInteraction(at date: Date) {
        guard mode == .routine else { return }
        routineActivityDetector.noteCompanionInteraction(at: date)
    }

    func togglePause() {
        guard mode == .routine else { return }
        noteCompanionInteraction()
        isPaused.toggle()
        persistState()
        if isPaused { speaker.stop() } else { speaker.speak(currentStep.spokenInstruction) }
    }

    func nextRoutine() {
        nextRoutine(at: Date(), activitySignal: activitySignalProvider())
    }

    /// Next starts a brand-new routine, so activity detection restarts with it: its own
    /// grace period, its own pointer-persistence state, and its own protection budget.
    func nextRoutine(at date: Date, activitySignal: LocalActivitySignal) {
        guard mode == .routine,
              let next = sessionSelection.nextSession(
                after: routine,
                from: MoveLibrary.all,
                selectedAreas: selectedAreas
              ) else { return }

        speaker.stop()
        routine = next
        stepIndex = 0
        elapsedInStep = 0
        isPaused = false
        statusText = nil
        routineActivityDetector.start(at: date, signal: activitySignal)
        notifySizeChange()
        speaker.speak(currentStep.spokenInstruction)
    }

    func endRoutine() {
        guard mode == .routine else { return }
        noteCompanionInteraction()
        speaker.stop()
        finishRoutine(countAsCompleted: false)
    }

    func dismissCompletion() {
        guard mode == .complete else { return }
        cancelCompletionAutoDismiss()
        mode = .idle
        notifySizeChange()
    }

    @discardableResult
    func handleCompletionKey(characters: String?, keyCode: UInt16) -> Bool {
        guard CompletionDismissalPolicy.shouldDismiss(
            isCompletionVisible: mode == .complete,
            characters: characters,
            keyCode: keyCode
        ) else {
            return false
        }
        dismissCompletion()
        return true
    }

    private func startClock() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        tick(at: nowProvider(), userIsActive: userIsActive)
    }

    /// Runs the automatic timer path with the injected aggregate activity signal.
    @MainActor
    func tickForTesting(at date: Date) {
        tick(at: date, userIsActive: userIsActive)
    }

    @MainActor
    func tickForTesting(at date: Date, userIsActive: Bool) {
        tick(at: date, userIsActive: userIsActive)
    }

    private func tick(at now: Date, userIsActive: Bool) {
        defer { persistState() }

        if mode == .checkIn {
            updateLastCompletedPauseContext(at: now)
            return
        }

        if mode == .routine {
            if evaluateRoutineActivity(signal: activitySignalProvider(), at: now) == .resumedWork {
                return
            }
            guard !isPaused else { return }
            elapsedInStep += 1
            if elapsedInStep >= currentStep.duration { advanceStep() }
            return
        }

        guard mode == .idle else { return }
        let activity = activeUseTracker.tick(at: now, userIsActive: userIsActive)

        if let scheduledCheckIn {
            updateCheckInProgress(at: now)
            guard userIsActive else { return }
            if now >= scheduledCheckIn.dueAt {
                self.scheduledCheckIn = nil
                showCheckIn(at: now)
            }
            return
        }

        guard userIsActive else {
            updateCheckInProgress(at: now)
            return
        }
        updateCheckInProgress(at: now)
        if activity.shouldOfferCheckIn {
            showCheckIn(at: now)
        }
    }

    private var userIsActive: Bool {
        activitySignalProvider().workActivityIdle < idleThreshold
    }

    @discardableResult
    func evaluateRoutineActivity(
        signal: LocalActivitySignal,
        at date: Date
    ) -> RoutineActivityDecision {
        guard mode == .routine else { return .noNewActivity }
        let decision = routineActivityDetector.decision(
            at: date,
            isPaused: isPaused,
            companionHasKeyboardFocus: companionHasKeyboardFocus(),
            signal: signal
        )
        if decision == .resumedWork {
            recoverFromResumedActivity(at: date)
        }
        return decision
    }

    private func showCheckIn(at date: Date, activityRecoveryExplanation: String? = nil) {
        guard mode == .idle else { return }
        cancelCompletionAutoDismiss()
        activeUseTracker.reset(at: date)
        guard let suggestion = sessionSelection.suggestion(
            from: MoveLibrary.all,
            selectedAreas: selectedAreas
        ) else { return }
        routine = suggestion
        statusText = nil
        self.activityRecoveryExplanation = activityRecoveryExplanation
        isCheckInCollapsed = false
        updateLastCompletedPauseContext(at: date)
        mode = .checkIn
        notifySizeChange()
        // Someone who just went back to work should not be spoken to or have the
        // app focus taken from them; the written explanation carries it.
        guard activityRecoveryExplanation == nil else { return }
        speaker.speak(Self.checkInPrompt)
    }

    private func advanceStep() {
        if stepIndex + 1 < routine.steps.count {
            stepIndex += 1
            elapsedInStep = 0
            speaker.speak(currentStep.spokenInstruction)
        } else {
            finishRoutine(countAsCompleted: true)
        }
    }

    private func recoverFromResumedActivity(at date: Date) {
        guard mode == .routine else { return }
        speaker.stop()
        routineActivityDetector.reset()
        sessionSelection.clearPendingSession()
        activeUseTracker.reset(at: date)
        scheduledCheckIn = nil
        isPaused = false
        isCheckInCollapsed = false
        stepIndex = 0
        elapsedInStep = 0
        statusText = nil
        mode = .idle
        notifySizeChange()
        showCheckIn(
            at: date,
            activityRecoveryExplanation: "No problem — it looks like you’re back at work. Start a fresh reset whenever you’re ready."
        )
    }

    private func finishRoutine(countAsCompleted: Bool) {
        routineActivityDetector.reset()
        if countAsCompleted {
            sessionSelection.markCompleted(routine)
        } else {
            sessionSelection.clearPendingSession()
        }
        let now = nowProvider()
        if countAsCompleted {
            pauseHistory.recordCompletedPause(at: now)
        }
        mode = .complete
        activeUseTracker.reset(at: now)
        scheduledCheckIn = nil
        updateCheckInProgress(at: now)
        statusText = nil
        activityRecoveryExplanation = nil
        speaker.speak("That’s it. Welcome back.")
        scheduleCompletionAutoDismiss()
        notifySizeChange()
    }

    private func scheduleCompletionAutoDismiss() {
        completionDismissTask?.cancel()
        let token = completionDismissalState.begin()
        completionDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(CompletionDismissalState.delaySeconds))
            guard !Task.isCancelled,
                  let self,
                  self.mode == .complete,
                  self.completionDismissalState.isCurrent(token) else {
                return
            }
            self.dismissCompletion()
        }
    }

    private func cancelCompletionAutoDismiss() {
        completionDismissTask?.cancel()
        completionDismissTask = nil
        completionDismissalState.cancel()
    }

    private func returnToIdle(after seconds: TimeInterval) {
        postponementScheduler.schedule(after: seconds) { [weak self] in
            self?.transitionToIdle()
        }
    }

    private func transitionToIdle() {
        guard mode == .checkIn else { return }
        isCheckInCollapsed = false
        mode = .idle
        statusText = nil
        activityRecoveryExplanation = nil
        notifySizeChange()
    }

    private func notifySizeChange() {
        persistState()
        onSizeChange?(mode)
    }

    private func restorePersistedState(at now: Date) {
        guard let state = stateStore?.load(),
              !bodyAreaPreferences.shouldPresentFirstRunSetup else { return }

        activeUseTracker = ActiveUseTracker(
            activeInterval: workInterval,
            idleThreshold: idleThreshold,
            startedAt: now,
            persistenceState: state.activeUse
        )
        if let startedAt = state.scheduledCheckInStartedAt,
           let dueAt = state.scheduledCheckInDueAt,
           startedAt <= dueAt,
           startedAt.timeIntervalSinceReferenceDate.isFinite,
           dueAt.timeIntervalSinceReferenceDate.isFinite {
            scheduledCheckIn = ScheduledCheckInWindow(startedAt: startedAt, dueAt: dueAt)
        }

        guard let persistedRoutine = routineFromPersistedMoveIDs(state.routineMoveIDs) else {
            updateCheckInProgress(at: now)
            return
        }
        routine = persistedRoutine

        switch state.mode {
        case .idle:
            mode = .idle
        case .checkIn where scheduledCheckIn != nil:
            mode = .idle
            isCheckInCollapsed = false
        case .checkIn:
            mode = .checkIn
            isCheckInCollapsed = state.isCheckInCollapsed
            updateLastCompletedPauseContext(at: now)
        case .routine:
            guard state.stepIndex >= 0,
                  state.stepIndex < routine.steps.count,
                  state.elapsedInStep >= 0,
                  state.elapsedInStep < routine.steps[state.stepIndex].duration else {
                mode = .idle
                updateCheckInProgress(at: now)
                return
            }
            mode = .routine
            stepIndex = state.stepIndex
            elapsedInStep = state.elapsedInStep
            isPaused = state.isPaused
            routineActivityDetector.start(at: now, signal: activitySignalProvider())
        case .complete:
            mode = .complete
            scheduleCompletionAutoDismiss()
        }
        updateCheckInProgress(at: now)
    }

    private func routineFromPersistedMoveIDs(_ moveIDs: [String]) -> BreakRoutine? {
        guard moveIDs.count == SessionComposer.sessionMoveCount,
              Set(moveIDs).count == moveIDs.count else { return nil }
        let movesByID = Dictionary(uniqueKeysWithValues: MoveLibrary.all.map { ($0.id, $0) })
        let moves = moveIDs.compactMap { movesByID[$0] }
        guard moves.count == moveIDs.count else { return nil }
        return BreakRoutine.composed(from: moves, selectedAreas: selectedAreas)
    }

    private func updateLastCompletedPauseContext(at now: Date) {
        let context = pauseHistory.lastCompletedPause(beforeOrAt: now).flatMap {
            PauseRelativeTimeFormatter.string(for: $0, relativeTo: now)
        }
        if lastCompletedPauseContext != context {
            lastCompletedPauseContext = context
        }
    }

    private func updateCheckInProgress(at now: Date) {
        checkInProgress = BreakProgress.value(
            activeSeconds: activeUseTracker.accumulatedActiveTime,
            activeInterval: workInterval,
            scheduledWindow: scheduledCheckIn,
            now: now
        )
        nextCheckInRemainingSeconds = BreakProgress.remainingSeconds(
            activeSeconds: activeUseTracker.accumulatedActiveTime,
            activeInterval: workInterval,
            scheduledWindow: scheduledCheckIn,
            now: now
        )
    }
}
