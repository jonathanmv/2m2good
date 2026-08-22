import Foundation

enum SelfCheck {
    static func run() -> Bool {
        var failures: [String] = []

        checkProgress(&failures)
        checkVoice(&failures)
        checkCompletion(&failures)
        checkMoveLibraryAndComposition(&failures)
        checkPersistence(&failures)
        checkPointer(&failures)

        if failures.isEmpty {
            print("Self-check passed: 2M2Better standing session composition, body-area selection, recent-shown persistence, focus balance, voice variants, completion dismissal, progress color, and pointer movement.")
            return true
        }

        failures.forEach { print("Self-check failed: \($0)") }
        return false
    }

    private static func checkProgress(_ failures: inout [String]) {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let deferral = ScheduledCheckInWindow(
            startedAt: now,
            dueAt: now.addingTimeInterval(1_200)
        )
        let cases: [(TimeInterval, Double)] = [(0, 0), (1_800, 0.5), (3_240, 0.9)]
        for (seconds, expected) in cases where BreakProgress.value(
            activeSeconds: seconds,
            activeInterval: 3_600,
            scheduledWindow: nil,
            now: now
        ) != expected {
            failures.append("active-use progress failed at \(expected)")
        }
        if BreakProgress.value(
            activeSeconds: 2_700,
            activeInterval: 3_600,
            scheduledWindow: deferral,
            now: now
        ) != 0 {
            failures.append("a deferral should reset visible progress")
        }
        if BreakProgress.color(at: 0) != OrbProgressColor(red: 0.30, green: 0.68, blue: 0.52)
            || BreakProgress.color(at: 0.5) != OrbProgressColor(red: 0.88, green: 0.58, blue: 0.28)
            || BreakProgress.color(at: 1) != OrbProgressColor(red: 0.78, green: 0.34, blue: 0.32) {
            failures.append("orb progress color anchors changed")
        }
    }

    private static func checkVoice(_ failures: inout [String]) {
        let affirmativePhrases = [
            "yeah", "yes", "yep", "let's do it", "let’s do it",
            "LET'S GO!", "let us do it", "okay", "ready", "go ahead"
        ]
        for phrase in affirmativePhrases {
            let command = VoiceCommandParser.parse(phrase)
            if command != .start || CheckInVoiceAction.resolve(command) != .startRoutine {
                failures.append("affirmative voice phrase failed: \(phrase)")
            }
        }
        let otherCases: [(String, VoiceCommand)] = [
            ("maybe in 20 minutes", .later(minutes: 20)),
            ("maybe in twenty minutes", .later(minutes: 20)),
            ("yes, later in an hour", .later(minutes: 60)),
            ("two hours", .later(minutes: 120)),
            ("tomorrow please", .tomorrow),
            ("yesterday", .unknown)
        ]
        for (phrase, expected) in otherCases where VoiceCommandParser.parse(phrase) != expected {
            failures.append("voice command precedence failed: \(phrase)")
        }
    }

    private static func checkCompletion(_ failures: inout [String]) {
        if CompletionDismissalState.delaySeconds != 10 {
            failures.append("completion auto-dismiss should be ten seconds")
        }
        if !CompletionDismissalPolicy.shouldDismiss(
            isCompletionVisible: true,
            characters: "\r",
            keyCode: 36
        ) {
            failures.append("Return should dismiss the visible completion")
        }
        if CompletionDismissalPolicy.shouldDismiss(
            isCompletionVisible: false,
            characters: "\r",
            keyCode: 36
        ) {
            failures.append("Return should not dismiss outside completion")
        }
        var state = CompletionDismissalState()
        let staleToken = state.begin()
        state.cancel()
        let currentToken = state.begin()
        if state.isCurrent(staleToken) || !state.isCurrent(currentToken) {
            failures.append("completion cancellation should reject stale timers")
        }
    }

    private static func checkMoveLibraryAndComposition(_ failures: inout [String]) {
        if MoveLibrary.all.count < 20 {
            failures.append("expected at least twenty standing movements")
        }
        if Set(MoveLibrary.all.map(\.id)).count != MoveLibrary.all.count {
            failures.append("movement identifiers should be unique")
        }
        if MoveLibrary.all.contains(where: { !$0.supportsStanding || $0.focuses.isEmpty }) {
            failures.append("every movement should be standing-compatible and focus-tagged")
        }
        if Set(MoveLibrary.all.flatMap(\.focuses)) != Set(BodyFocus.allCases) {
            failures.append("movement focus tags should cover the internal taxonomy")
        }
        if BodyArea.allCases.map(\.label) != ["Lower back", "Neck", "Shoulders", "Hands + wrists"] {
            failures.append("body-area labels should match the approved v1 set")
        }
        for area in BodyArea.allCases {
            let matching = MoveLibrary.all.filter { !$0.bodyAreas.isDisjoint(with: [area]) }
            guard let areaRoutine = SessionComposer.compose(
                from: MoveLibrary.all,
                recentShownMoveIDs: [],
                recentCompletedMoveIDs: [],
                selectedAreas: [area]
            ) else {
                failures.append("could not compose a selected-area session for \(area.label)")
                continue
            }
            if matching.count < 3
                || Set(areaRoutine.moveIDs).intersection(Set(matching.map(\.id))).count < 3
                || areaRoutine.duration != 120
                || areaRoutine.steps.count != 6 {
                failures.append("selected-area composition failed for \(area.label)")
            }
        }
        for move in MoveLibrary.all {
            let text = "\(move.title) \(move.instruction)".lowercased()
            if text.contains("seated") || text.contains("sit down") || text.contains("chair") {
                failures.append("\(move.id) contains seated-only guidance")
            }
        }

        guard let first = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: [],
            recentCompletedMoveIDs: []
        ) else {
            failures.append("could not compose an initial session")
            return
        }
        if first.duration != 120 || first.steps.count != 6 || Set(first.moveIDs).count != 6 {
            failures.append("a composed session should contain six unique twenty-second moves")
        }
        let firstInstruction = first.steps.first?.instruction.lowercased() ?? ""
        if !first.invitation.lowercased().contains("stand")
            || !firstInstruction.contains("stand when")
            || !firstInstruction.contains("move gently")
            || !firstInstruction.contains("stop if anything hurts") {
            failures.append("every session should invite safe, gentle standing")
        }

        guard let second = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: first.moveIDs,
            recentCompletedMoveIDs: [],
            excluding: Set(first.moveIDs)
        ), let third = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: first.moveIDs + second.moveIDs,
            recentCompletedMoveIDs: [],
            excluding: Set(second.moveIDs)
        ) else {
            failures.append("could not compose replacement sessions")
            return
        }
        if !Set(first.moveIDs).isDisjoint(with: second.moveIDs)
            || !Set(second.moveIDs).isDisjoint(with: third.moveIDs)
            || !Set(first.moveIDs).isDisjoint(with: third.moveIDs) {
            failures.append("Next should avoid current and recently shown movements")
        }

        let allIDs = MoveLibrary.all.map(\.id)
        let currentIDs = Set(MoveLibrary.all.prefix(6).map(\.id))
        let fallbackA = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: allIDs,
            recentCompletedMoveIDs: allIDs,
            excluding: currentIDs
        )
        let fallbackB = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: allIDs,
            recentCompletedMoveIDs: allIDs,
            excluding: currentIDs
        )
        if fallbackA != fallbackB || !currentIDs.isDisjoint(with: fallbackA?.moveIDs ?? []) {
            failures.append("composition fallback should be deterministic and avoid the active session")
        }

        let focusedLibrary = [
            makeMove("neck-a", [.neckShoulders]),
            makeMove("hands", [.handsWristsForearms]),
            makeMove("neck-b", [.neckShoulders]),
            makeMove("neck-c", [.neckShoulders]),
            makeMove("neck-d", [.neckShoulders]),
            makeMove("neck-e", [.neckShoulders]),
            makeMove("neck-f", [.neckShoulders])
        ]
        if SessionComposer.compose(
            from: focusedLibrary,
            recentShownMoveIDs: [],
            recentCompletedMoveIDs: Array(repeating: "neck-a", count: 8)
        )?.moveIDs.first != "hands" {
            failures.append("ordinary composition should favor an underrepresented focus")
        }
    }

    private static func checkPersistence(_ failures: inout [String]) {
        let suiteName = "local.break-companion.pilot.self-check.\(ProcessInfo.processInfo.processIdentifier)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            failures.append("could not create isolated preferences")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let freshPreferences = BodyAreaPreferences(defaults: defaults)
        if !freshPreferences.shouldPresentFirstRunSetup || !freshPreferences.selectedAreas.isEmpty {
            failures.append("fresh preferences should request body-area setup")
        }
        freshPreferences.save(selectedAreas: [.neck, .shoulders])
        if BodyAreaPreferences(defaults: defaults).selectedAreas != [.neck, .shoulders] {
            failures.append("selected body areas should survive a restart")
        }

        let firstStore = SessionSelectionStore(defaults: defaults)
        guard let first = firstStore.suggestion(from: MoveLibrary.all),
              let second = firstStore.nextSession(after: first, from: MoveLibrary.all) else {
            failures.append("could not persist shown sessions")
            return
        }
        let restarted = SessionSelectionStore(defaults: defaults)
        if restarted.suggestion(from: MoveLibrary.all) != second {
            failures.append("pending composition should survive restart")
        }
        guard let third = restarted.nextSession(after: second, from: MoveLibrary.all) else {
            failures.append("could not compose after restart")
            return
        }
        if !Set(second.moveIDs).isDisjoint(with: third.moveIDs)
            || !Set(first.moveIDs).isDisjoint(with: third.moveIDs) {
            failures.append("skipped and switched sessions should stay in recent-shown history")
        }
        restarted.markCompleted(third)
        if defaults.stringArray(forKey: "session.recentCompletedMoveIDs") != third.moveIDs {
            failures.append("completed movement history should persist locally")
        }
        if defaults.object(forKey: "session.pendingMoveIDs") != nil {
            failures.append("completion should clear the pending composition")
        }

        guard let afterCompletion = restarted.suggestion(from: MoveLibrary.all) else {
            failures.append("could not compose after completion")
            return
        }
        let shownBeforeEnd = defaults.stringArray(forKey: "session.recentShownMoveIDs")
        let completedBeforeEnd = defaults.stringArray(forKey: "session.recentCompletedMoveIDs")
        restarted.clearPendingSession()
        if defaults.object(forKey: "session.pendingMoveIDs") != nil
            || defaults.stringArray(forKey: "session.recentShownMoveIDs") != shownBeforeEnd
            || defaults.stringArray(forKey: "session.recentCompletedMoveIDs") != completedBeforeEnd
            || afterCompletion.moveIDs.isEmpty {
            failures.append("ending should keep shown history without recording completion")
        }
    }

    private static func checkPointer(_ failures: inout [String]) {
        if PointerMovementClassifier.classify(from: .zero, to: CGPoint(x: 4, y: 0)) != .tap {
            failures.append("movement at the pointer threshold should remain a tap")
        }
        if PointerMovementClassifier.classify(from: .zero, to: CGPoint(x: 3, y: 4)) != .drag {
            failures.append("movement past the pointer threshold should become a drag")
        }
    }

    private static func makeMove(_ id: String, _ focuses: Set<BodyFocus>) -> BreakMove {
        BreakMove(
            id: id,
            title: id,
            instruction: "Move slowly and comfortably.",
            focuses: focuses,
            motion: .still,
            supportsStanding: true
        )
    }
}
