import CoreGraphics
import Foundation

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

    let voice = VoiceService()
    var onSizeChange: ((Mode) -> Void)?
    /// Set by the app so keystrokes aimed at the companion's own panel are read as
    /// intentional interaction instead of resumed work.
    var companionHasKeyboardFocus: () -> Bool = { false }

    private let speaker: RoutineSpeaking
    private let workInterval: TimeInterval
    private let idleThreshold: TimeInterval
    private let sessionSelection: SessionSelectionStore
    private let bodyAreaPreferences: BodyAreaPreferences
    private var accumulatedActiveTime: TimeInterval = 0
    private var scheduledCheckIn: ScheduledCheckInWindow?
    private var lastTick = Date()
    private var timer: Timer?
    private var completionDismissTask: Task<Void, Never>?
    private var completionDismissalState = CompletionDismissalState()
    private var routineActivityDetector = RoutineActivityDetector()
    private let activitySignalProvider: () -> LocalActivitySignal

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        activitySignalProvider: @escaping () -> LocalActivitySignal = LocalActivitySignal.current,
        speaker: RoutineSpeaking? = nil
    ) {
        let configuredInterval = Double(environment["BREAK_INTERVAL_SECONDS"] ?? "")
        workInterval = max(5, configuredInterval ?? 60 * 60)
        let configuredIdle = Double(environment["BREAK_IDLE_THRESHOLD_SECONDS"] ?? "")
        idleThreshold = max(10, configuredIdle ?? 60)
        sessionSelection = SessionSelectionStore(defaults: defaults)
        bodyAreaPreferences = BodyAreaPreferences(defaults: defaults)
        self.activitySignalProvider = activitySignalProvider
        self.speaker = speaker ?? GuideSpeaker()
        selectedAreas = bodyAreaPreferences.selectedAreas
        routine = BreakRoutine.fallback
        nextCheckInRemainingSeconds = workInterval
        mode = bodyAreaPreferences.shouldPresentFirstRunSetup ? .setup : .idle

        voice.onCommand = { [weak self] command in
            self?.handle(command)
        }
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
        showCheckIn()
    }

    var canOpenAreaConfiguration: Bool { mode == .idle }

    var offersBalancedChoice: Bool { mode == .setup || mode == .configuration }

    func openAreaConfiguration() {
        guard canOpenAreaConfiguration else { return }
        mode = .configuration
        notifySizeChange()
    }

    func saveSelectedAreas(_ areas: Set<BodyArea>) {
        guard !areas.isEmpty else { return }
        bodyAreaPreferences.save(selectedAreas: areas)
        selectedAreas = bodyAreaPreferences.selectedAreas
        sessionSelection.clearPendingSession()
        guard offersBalancedChoice else { return }
        mode = .idle
        notifySizeChange()
    }

    func continueWithBalancedDefaults() {
        bodyAreaPreferences.continueWithBalancedDefaults()
        selectedAreas = []
        sessionSelection.clearPendingSession()
        guard offersBalancedChoice else { return }
        mode = .idle
        notifySizeChange()
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
        voice.stopListening()
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
        voice.stopListening()
        let now = Date()
        scheduledCheckIn = ScheduledCheckInWindow(
            startedAt: now,
            dueAt: now.addingTimeInterval(TimeInterval(minutes * 60))
        )
        accumulatedActiveTime = 0
        updateCheckInProgress(at: now)
        statusText = minutes == 60 ? "I’ll check back in an hour." : "I’ll check back in \(minutes) minutes."
        activityRecoveryExplanation = nil
        returnToIdle(after: 1.5)
    }

    func postponeUntilTomorrow() {
        voice.stopListening()
        let now = Date()
        let dueAt = Calendar.current.date(byAdding: .day, value: 1, to: now)
            ?? now.addingTimeInterval(24 * 60 * 60)
        scheduledCheckIn = ScheduledCheckInWindow(startedAt: now, dueAt: dueAt)
        accumulatedActiveTime = 0
        updateCheckInProgress(at: now)
        statusText = "See you tomorrow."
        activityRecoveryExplanation = nil
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
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        let now = Date()
        let delta = min(2, now.timeIntervalSince(lastTick))
        lastTick = now

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

        if let scheduledCheckIn {
            updateCheckInProgress(at: now)
            guard userIsActive else { return }
            if now >= scheduledCheckIn.dueAt {
                self.scheduledCheckIn = nil
                showCheckIn()
            }
            return
        }

        guard userIsActive else { return }
        accumulatedActiveTime += delta
        updateCheckInProgress(at: now)
        if accumulatedActiveTime >= workInterval {
            showCheckIn()
        }
    }

    private var userIsActive: Bool {
        let signal = LocalActivitySignal.currentWorkActivity()
        return signal.workActivityIdle < idleThreshold
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
            recoverFromResumedActivity()
        }
        return decision
    }

    private func showCheckIn(activityRecoveryExplanation: String? = nil) {
        guard mode == .idle else { return }
        cancelCompletionAutoDismiss()
        accumulatedActiveTime = 0
        guard let suggestion = sessionSelection.suggestion(
            from: MoveLibrary.all,
            selectedAreas: selectedAreas
        ) else { return }
        routine = suggestion
        statusText = nil
        self.activityRecoveryExplanation = activityRecoveryExplanation
        mode = .checkIn
        notifySizeChange()
        // Someone who just went back to work should not be spoken to or have the
        // microphone and app focus taken from them; the written explanation carries it.
        guard activityRecoveryExplanation == nil else { return }
        // Keep the spoken prompt free of command words so recognition cannot act on
        // the companion's own voice as the microphone comes online.
        speaker.speak(Self.checkInPrompt)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_200))
            guard self.mode == .checkIn else { return }
            self.voice.requestAndListen()
        }
    }

    private func handle(_ command: VoiceCommand) {
        guard mode == .checkIn else { return }
        switch CheckInVoiceAction.resolve(command) {
        case .startRoutine: startRoutine()
        case .postpone(let minutes): postpone(minutes: minutes)
        case .tomorrow: postponeUntilTomorrow()
        case .ignore: break
        }
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

    private func recoverFromResumedActivity() {
        guard mode == .routine else { return }
        speaker.stop()
        voice.stopListening()
        routineActivityDetector.reset()
        sessionSelection.clearPendingSession()
        accumulatedActiveTime = 0
        scheduledCheckIn = nil
        isPaused = false
        stepIndex = 0
        elapsedInStep = 0
        statusText = nil
        mode = .idle
        notifySizeChange()
        showCheckIn(
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
        mode = .complete
        accumulatedActiveTime = 0
        scheduledCheckIn = nil
        updateCheckInProgress(at: Date())
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
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard self.mode == .checkIn else { return }
            self.mode = .idle
            self.statusText = nil
            self.activityRecoveryExplanation = nil
            self.notifySizeChange()
        }
    }

    private func notifySizeChange() {
        onSizeChange?(mode)
    }

    private func updateCheckInProgress(at now: Date) {
        checkInProgress = BreakProgress.value(
            activeSeconds: accumulatedActiveTime,
            activeInterval: workInterval,
            scheduledWindow: scheduledCheckIn,
            now: now
        )
        nextCheckInRemainingSeconds = BreakProgress.remainingSeconds(
            activeSeconds: accumulatedActiveTime,
            activeInterval: workInterval,
            scheduledWindow: scheduledCheckIn,
            now: now
        )
    }
}
