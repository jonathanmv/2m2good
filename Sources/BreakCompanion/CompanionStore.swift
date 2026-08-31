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
    static let pendingOfferReminderInterval: TimeInterval = 5 * 60

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
    @Published private(set) var lastCompletedPauseContext = "none yet"

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
    private var lastPersistedState: PersistedCompanionState?
    private let testingIntervalOverride: TimeInterval?
    private var activeUseTracker: ActiveUseTracker
    private var scheduledCheckIn: ScheduledCheckInWindow?
    /// An undecided offer owns one wall-clock reminder at a time. Keeping the
    /// deadline in the store (rather than creating a task per collapse) lets the
    /// one-second clock, relaunch checkpoint, and tests share the same path.
    private var pendingOfferReminderDueAt: Date?
    private let nowProvider: () -> Date
    private let postponementScheduler: any DelayedActionScheduling
    private var timer: Timer?
    private var configurationReturnMode: Mode?
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
        case .idle, .setup: persistedMode = .idle
        case .configuration:
            switch configurationReturnMode {
            case .checkIn: persistedMode = .checkIn
            case .routine: persistedMode = .routine
            case .complete: persistedMode = .complete
            default: persistedMode = .idle
            }
        case .checkIn: persistedMode = .checkIn
        case .routine: persistedMode = .routine
        case .complete: persistedMode = .complete
        }
        let state = PersistedCompanionState(
            mode: persistedMode,
            activeUse: activeUseTracker.persistenceState,
            scheduledCheckInStartedAt: scheduledCheckIn?.startedAt,
            scheduledCheckInDueAt: scheduledCheckIn?.dueAt,
            pendingOfferReminderDueAt: pendingOfferReminderDueAt,
            routineMoveIDs: routine.moveIDs,
            stepIndex: stepIndex,
            elapsedInStep: elapsedInStep,
            isPaused: isPaused,
            isCheckInCollapsed: isCheckInCollapsed
        )
        guard state != lastPersistedState else { return }
        lastPersistedState = state
        stateStore.save(state)
    }

    /// Settings never becomes a dead menu item. The action is enabled for every
    /// running state; opening it from a routine or completion screen returns to that
    /// state instead of discarding it.
    var canOpenAreaConfiguration: Bool { true }

    /// Starts the one-second active-use clock after the application has installed its
    /// panel and entered its run loop. Keeping timer registration out of init avoids
    /// silently losing the timer while AppKit is still launching the accessory app.
    func startClock() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    var isClockRunning: Bool {
        timer?.isValid == true
    }

    func collapseCheckIn() {
        guard mode == .checkIn, statusText == nil else { return }
        isCheckInCollapsed = true
        // The collapse is the user's choice to defer seeing the same offer;
        // start its five-minute reminder window at that interaction, without
        // touching active-use credit.
        pendingOfferReminderDueAt = nowProvider().addingTimeInterval(Self.pendingOfferReminderInterval)
        notifySizeChange()
    }

    func restoreCheckIn() {
        guard mode == .checkIn, isCheckInCollapsed else { return }
        isCheckInCollapsed = false
        notifySizeChange()
    }

    var offersBalancedChoice: Bool { mode == .setup || mode == .configuration }

    func openAreaConfiguration() {
        guard mode != .configuration, mode != .setup else { return }
        let returnMode = mode
        configurationReturnMode = returnMode
        let now = nowProvider()
        switch returnMode {
        case .idle, .checkIn:
            // Settings is not active use and must not create a delayed callback delta.
            activeUseTracker.suspend(at: now)
        case .routine:
            // Re-baseline the aggregate signal so the settings visit cannot cancel the
            // routine when the panel returns.
            routineActivityDetector.suspendObservation(at: now, signal: activitySignalProvider())
        case .complete:
            // The completion timer is resumed when the completion screen returns.
            cancelCompletionAutoDismiss()
        case .setup, .configuration:
            break
        }
        mode = .configuration
        notifySizeChange()
    }

    func saveSettings(cadence: Cadence, areas: Set<BodyArea>) {
        guard !areas.isEmpty else { return }
        let returnMode = configurationReturnMode
        let wasConfiguration = mode == .configuration || mode == .setup
        let cadenceChanged = selectedCadence != cadence
        let now = nowProvider()
        cadencePreferences.save(cadence: cadence)
        bodyAreaPreferences.save(selectedAreas: areas)
        selectedCadence = cadence
        selectedAreas = bodyAreaPreferences.selectedAreas

        if returnMode != .routine {
            sessionSelection.clearPendingSession()
        }

        workInterval = testingIntervalOverride ?? cadence.interval
        if cadenceChanged {
            // Keep any active credit accrued before Settings opened, but never count
            // time spent editing the setting as active use.
            activeUseTracker.reconfigure(activeInterval: workInterval, at: now)
        } else {
            activeUseTracker.suspend(at: now)
        }
        updateCheckInProgress(at: now)

        guard wasConfiguration else { return }
        restoreFromConfiguration(returnMode, refreshPendingOffer: returnMode == .checkIn)
    }

    // Kept as a small compatibility shim for the existing menu/setup path.
    func saveSelectedAreas(_ areas: Set<BodyArea>) {
        saveSettings(cadence: selectedCadence, areas: areas)
    }

    func continueWithBalancedDefaults() {
        cadencePreferences.save(cadence: selectedCadence)
        bodyAreaPreferences.continueWithBalancedDefaults()
        selectedAreas = []
        if configurationReturnMode != .routine {
            sessionSelection.clearPendingSession()
        }
        guard offersBalancedChoice else { return }
        restoreFromConfiguration(configurationReturnMode, refreshPendingOffer: configurationReturnMode == .checkIn)
    }

    func diagnosticSnapshot(activityIsActive: Bool? = nil) -> CompanionDiagnosticSnapshot {
        let path: ActiveUsePath
        let presentation: PendingOfferPresentation
        switch mode {
        case .idle where scheduledCheckIn != nil:
            path = .scheduled
            presentation = .notPending
        case .idle where activityIsActive ?? userIsActive:
            path = .accumulating
            presentation = .notPending
        case .idle:
            path = .waitingForActivity
            presentation = .notPending
        case .checkIn where statusText != nil:
            path = .scheduled
            presentation = .notPending
        case .checkIn:
            path = .pendingOffer
            presentation = isCheckInCollapsed ? .collapsedOrb : .visibleChoices
        case .configuration:
            path = .settings
            presentation = configurationReturnMode == .checkIn && statusText == nil
                ? (isCheckInCollapsed ? .collapsedOrb : .visibleChoices)
                : .notPending
        case .routine:
            path = .routine
            presentation = .notPending
        case .complete:
            path = .complete
            presentation = .notPending
        case .setup:
            path = .settings
            presentation = .notPending
        }
        return CompanionDiagnosticSnapshot(
            cadence: selectedCadence,
            selectedAreas: BodyArea.allCases.filter { selectedAreas.contains($0) },
            mode: mode.diagnosticLabel,
            activeUsePath: path,
            pendingOfferPresentation: presentation
        )
    }

    func diagnosticReport(activityIsActive: Bool? = nil) -> String {
        diagnosticSnapshot(activityIsActive: activityIsActive).report
    }

    func cancelAreaConfiguration() {
        guard mode == .configuration else { return }
        restoreFromConfiguration(configurationReturnMode)
    }

    private func restoreFromConfiguration(_ returnMode: Mode?, refreshPendingOffer: Bool = false) {
        // Close-time observation is needed as well as the per-second configuration
        // guard for a Settings sheet opened and closed between clock ticks.
        activeUseTracker.suspend(at: nowProvider())
        if returnMode == .routine {
            // Discard the whole Settings visit's activity delta without spending protection budget.
            routineActivityDetector.resumeObservation(at: nowProvider(), signal: activitySignalProvider())
        }
        configurationReturnMode = nil
        if returnMode == .checkIn, refreshPendingOffer,
           let suggestion = sessionSelection.suggestion(
               from: MoveLibrary.all,
               selectedAreas: selectedAreas
           ) {
            // Settings changes may alter the invitation, but never the fact that a
            // decision is pending.
            routine = suggestion
        }
        mode = returnMode ?? .idle
        if returnMode == .complete {
            scheduleCompletionAutoDismiss()
        }
        notifySizeChange()
    }

    func startRoutine() {
        startRoutine(at: nowProvider(), activitySignal: activitySignalProvider())
    }

    func startRoutine(at date: Date, activitySignal: LocalActivitySignal) {
        cancelCompletionAutoDismiss()
        pendingOfferReminderDueAt = nil
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
        pendingOfferReminderDueAt = nil
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
        pendingOfferReminderDueAt = nil
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

    /// A locked session or system sleep is an observation boundary, never active
    /// work. The app's clock remains installed; this only re-anchors its state.
    func noteSystemInactive(at date: Date? = nil) {
        let date = date ?? nowProvider()
        // System inactivity follows the same half-rate decay as an observed idle
        // period. It must never erase prior work credit or create an offer at the
        // boundary; the next active sample can only resume from that decayed credit.
        activeUseTracker.markInactive(at: date)
        if mode == .routine {
            routineActivityDetector.resetObservation(
                at: date,
                signal: activitySignalProvider()
            )
        }
        updateCheckInProgress(at: date)
        persistState()
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
            handlePendingOfferReminder(at: now)
            return
        }

        if mode == .configuration {
            // The one-second clock remains alive through Settings, but the settings
            // visit is neither active work nor a routine step.
            activeUseTracker.suspend(at: now)
            updateCheckInProgress(at: now)
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
        // A manual offer supersedes any earlier Later/Tomorrow window. This
        // keeps the pending offer and its reminder independent on relaunch.
        scheduledCheckIn = nil
        activeUseTracker.reset(at: date)
        updateCheckInProgress(at: date)
        guard let suggestion = sessionSelection.suggestion(
            from: MoveLibrary.all,
            selectedAreas: selectedAreas
        ) else { return }
        routine = suggestion
        statusText = nil
        self.activityRecoveryExplanation = activityRecoveryExplanation
        isCheckInCollapsed = false
        pendingOfferReminderDueAt = date.addingTimeInterval(Self.pendingOfferReminderInterval)
        updateLastCompletedPauseContext(at: date)
        mode = .checkIn
        notifySizeChange()
        // Someone who just went back to work should not be spoken to or have the
        // app focus taken from them; the written explanation carries it.
        guard activityRecoveryExplanation == nil else { return }
        speaker.speak(Self.checkInPrompt)
    }

    /// Re-present the existing pending choice without composing another routine or
    /// resetting active-use credit. A visible offer only needs a reannouncement;
    /// a collapsed offer also asks AppKit to refit the panel back to its choices.
    private func handlePendingOfferReminder(at now: Date) {
        guard mode == .checkIn,
              statusText == nil,
              let dueAt = pendingOfferReminderDueAt,
              dueAt <= now else { return }

        pendingOfferReminderDueAt = now.addingTimeInterval(Self.pendingOfferReminderInterval)
        let wasCollapsed = isCheckInCollapsed
        isCheckInCollapsed = false
        if wasCollapsed {
            notifySizeChange()
        } else {
            persistState()
        }

        // Recovery offers intentionally remain silent, just like their initial
        // presentation. Normal pending offers are reannounced through the same
        // prompt used for the initial offer.
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
        pendingOfferReminderDueAt = nil
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
        pendingOfferReminderDueAt = nil
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

        pendingOfferReminderDueAt = nil
        switch state.mode {
        case .idle:
            mode = .idle
        case .checkIn where scheduledCheckIn != nil:
            mode = .idle
            isCheckInCollapsed = false
        case .checkIn:
            mode = .checkIn
            isCheckInCollapsed = state.isCheckInCollapsed
            // An older checkpoint can contain a pending offer but no reminder
            // deadline. Give it one relative to this launch instead of dropping
            // the decision or firing repeatedly for a stale deadline.
            pendingOfferReminderDueAt = validPendingOfferReminderDueAt(
                state.pendingOfferReminderDueAt,
                now: now
            )
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

    private func validPendingOfferReminderDueAt(_ candidate: Date?, now: Date) -> Date {
        guard let candidate,
              candidate.timeIntervalSinceReferenceDate.isFinite else {
            return now.addingTimeInterval(Self.pendingOfferReminderInterval)
        }
        return candidate
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
        } ?? "none yet"
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
