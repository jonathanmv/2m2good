import CoreGraphics
import Foundation

@MainActor
final class CompanionStore: ObservableObject {
    enum Mode: Equatable {
        case idle
        case checkIn
        case routine
        case complete
    }

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var routine: BreakRoutine
    @Published private(set) var stepIndex = 0
    @Published private(set) var elapsedInStep = 0
    @Published private(set) var isPaused = false
    @Published private(set) var statusText: String?
    @Published private(set) var checkInProgress: Double = 0
    @Published private(set) var nextCheckInRemainingSeconds: TimeInterval = 0

    let voice = VoiceService()
    var onSizeChange: ((Mode) -> Void)?

    private let speaker = GuideSpeaker()
    private let workInterval: TimeInterval
    private let idleThreshold: TimeInterval
    private let routineSelection: RoutineSelectionStore
    private var accumulatedActiveTime: TimeInterval = 0
    private var scheduledCheckIn: ScheduledCheckInWindow?
    private var lastTick = Date()
    private var timer: Timer?

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) {
        let configuredInterval = Double(environment["BREAK_INTERVAL_SECONDS"] ?? "")
        workInterval = max(5, configuredInterval ?? 60 * 60)
        let configuredIdle = Double(environment["BREAK_IDLE_THRESHOLD_SECONDS"] ?? "")
        idleThreshold = max(10, configuredIdle ?? 60)
        routineSelection = RoutineSelectionStore(defaults: defaults)
        routine = BreakRoutine.all[0]
        nextCheckInRemainingSeconds = workInterval

        voice.onCommand = { [weak self] command in
            self?.handle(command)
        }
        startClock()
    }

    deinit {
        timer?.invalidate()
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

    func startRoutine() {
        voice.stopListening()
        mode = .routine
        stepIndex = 0
        elapsedInStep = 0
        isPaused = false
        statusText = nil
        notifySizeChange()
        speaker.speak(currentStep.instruction)
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
        returnToIdle(after: 1.5)
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused { speaker.stop() } else { speaker.speak(currentStep.instruction) }
    }

    func nextRoutine() {
        guard mode == .routine,
              let next = RandomRoutineSelector.next(
                from: BreakRoutine.all,
                currentRoutineID: routine.id
              ) else { return }

        speaker.stop()
        routine = next
        stepIndex = 0
        elapsedInStep = 0
        isPaused = false
        statusText = nil
        speaker.speak(currentStep.instruction)
    }

    func endRoutine() {
        speaker.stop()
        finishRoutine()
    }

    func dismissCompletion() {
        mode = .idle
        notifySizeChange()
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
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        let keyboardIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        return min(idle, keyboardIdle) < idleThreshold
    }

    private func showCheckIn() {
        guard mode == .idle else { return }
        accumulatedActiveTime = 0
        guard let suggestion = routineSelection.suggestion(from: BreakRoutine.all) else { return }
        routine = suggestion
        statusText = nil
        mode = .checkIn
        notifySizeChange()
        // Keep the spoken prompt free of command words so recognition cannot act on
        // the companion's own voice as the microphone comes online.
        speaker.speak("Time for a small pause.")
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
            speaker.speak(currentStep.instruction)
        } else {
            finishRoutine()
        }
    }

    private func finishRoutine() {
        routineSelection.markCompleted(routine)
        mode = .complete
        accumulatedActiveTime = 0
        scheduledCheckIn = nil
        updateCheckInProgress(at: Date())
        statusText = nil
        speaker.speak("That’s it. Welcome back.")
        notifySizeChange()
    }

    private func returnToIdle(after seconds: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard self.mode == .checkIn else { return }
            self.mode = .idle
            self.statusText = nil
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
