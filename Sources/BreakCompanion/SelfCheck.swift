import Foundation

enum SelfCheck {
    static func run() -> Bool {
        var failures: [String] = []

        let progressNow = Date(timeIntervalSinceReferenceDate: 1_000)
        let deferral = ScheduledCheckInWindow(
            startedAt: progressNow,
            dueAt: progressNow.addingTimeInterval(1_200)
        )
        let progressCases: [(TimeInterval, Double)] = [(0, 0), (1_800, 0.5), (3_240, 0.9)]
        for (activeSeconds, expected) in progressCases where BreakProgress.value(
            activeSeconds: activeSeconds,
            activeInterval: 3_600,
            scheduledWindow: nil,
            now: progressNow
        ) != expected {
            failures.append("active-use progress failed at \(expected)")
        }
        if BreakProgress.value(
            activeSeconds: 2_700,
            activeInterval: 3_600,
            scheduledWindow: deferral,
            now: progressNow
        ) != 0 {
            failures.append("a deferral should reset visible progress")
        }
        if BreakProgress.value(
            activeSeconds: 0,
            activeInterval: 3_600,
            scheduledWindow: deferral,
            now: progressNow.addingTimeInterval(600)
        ) != 0.5 {
            failures.append("deferred progress should use its scheduled window")
        }
        if BreakProgress.color(at: 0) != OrbProgressColor(red: 0.30, green: 0.68, blue: 0.52)
            || BreakProgress.color(at: 0.5) != OrbProgressColor(red: 0.88, green: 0.58, blue: 0.28)
            || BreakProgress.color(at: 1) != OrbProgressColor(red: 0.78, green: 0.34, blue: 0.32) {
            failures.append("orb color anchors should be green, orange, and muted red")
        }
        if BreakProgress.accessibilityValue(progress: 0.5, remainingSeconds: 1_800)
            != "Next break in about 30 minutes. 50 percent of the interval has elapsed." {
            failures.append("progress should have a non-color accessibility value")
        }

        if BreakRoutine.all.count != 10 {
            failures.append("expected ten routines")
        }
        if Set(BreakRoutine.all.map(\.id)).count != 10 {
            failures.append("routine identifiers should be unique")
        }
        for routine in BreakRoutine.all {
            if routine.duration != 120 {
                failures.append("\(routine.title) lasts \(routine.duration), not 120 seconds")
            }
            let script = routine.steps.map(\.instruction).joined(separator: " ").lowercased()
            if !script.contains("stop if anything hurts") {
                failures.append("\(routine.title) is missing safety language")
            }
        }
        if Set(BreakRoutine.all.flatMap(\.focuses)) != Set(BodyFocus.allCases) {
            failures.append("routine focus tags should cover the internal taxonomy")
        }
        if BreakRoutine.all.contains(where: { $0.focuses.isEmpty }) {
            failures.append("every routine should have at least one body focus")
        }

        let voiceCases: [(String, VoiceCommand)] = [
            ("yes, let's start", .start),
            ("maybe in 20 minutes", .later(minutes: 20)),
            ("maybe in twenty minutes", .later(minutes: 20)),
            ("try again in an hour", .later(minutes: 60)),
            ("two hours", .later(minutes: 120)),
            ("tomorrow please", .tomorrow)
        ]
        for (phrase, expected) in voiceCases where VoiceCommandParser.parse(phrase) != expected {
            failures.append("voice phrase failed: \(phrase)")
        }
        if CheckInVoiceAction.resolve(VoiceCommandParser.parse("start")) != .startRoutine {
            failures.append("recognized start should route to the offered routine")
        }

        if PointerMovementClassifier.classify(from: .zero, to: CGPoint(x: 4, y: 0)) != .tap {
            failures.append("movement at the threshold should remain a tap")
        }
        if PointerMovementClassifier.classify(from: .zero, to: CGPoint(x: 3, y: 4)) != .drag {
            failures.append("movement past the threshold should become a drag")
        }

        for current in BreakRoutine.all {
            let alternatives = BreakRoutine.all.filter { $0.id != current.id }
            let selectedIDs = Set(alternatives.indices.compactMap { index in
                RandomRoutineSelector.next(
                    from: BreakRoutine.all,
                    currentRoutineID: current.id,
                    chooseIndex: { _ in index }
                )?.id
            })
            if selectedIDs.contains(current.id) {
                failures.append("random next repeated the active routine")
            }
            if selectedIDs != Set(alternatives.map(\.id)) {
                failures.append("random next did not cover every alternative routine")
            }
        }

        let firstRoutine = BreakRoutine.all[0]
        let secondRoutine = BreakRoutine.all[1]
        let handsRoutine = BreakRoutine.all.first(where: { $0.id == "hands-wrists" })!
        let lastRoutine = BreakRoutine.all.last!
        if RoutineSelectionPolicy.suggestion(
            from: BreakRoutine.all,
            pendingRoutineID: firstRoutine.id,
            lastCompletedRoutineID: nil
        ) != firstRoutine {
            failures.append("a postponed routine should remain the current suggestion")
        }
        if RoutineSelectionPolicy.suggestion(
            from: BreakRoutine.all,
            pendingRoutineID: nil,
            lastCompletedRoutineID: firstRoutine.id
        ) != secondRoutine {
            failures.append("a completed routine should advance the next suggestion")
        }
        if RoutineSelectionPolicy.suggestion(
            from: BreakRoutine.all,
            pendingRoutineID: nil,
            lastCompletedRoutineID: lastRoutine.id
        ) != firstRoutine {
            failures.append("routine suggestions should wrap after the final routine")
        }
        if BalancedRoutineSelector.suggestion(
            from: BreakRoutine.all,
            completionHistory: Array(repeating: firstRoutine.id, count: 6)
        ) != handsRoutine {
            failures.append("balanced selection should favor an underrepresented focus")
        }
        for completed in BreakRoutine.all where BalancedRoutineSelector.suggestion(
            from: BreakRoutine.all,
            completionHistory: [completed.id]
        ) == completed {
            failures.append("balanced selection immediately repeated \(completed.title)")
        }
        let untaggedFirst = BreakRoutine(
            id: "untagged-first",
            title: "First",
            invitation: "Pause?",
            focuses: [],
            steps: firstRoutine.steps
        )
        let untaggedSecond = BreakRoutine(
            id: "untagged-second",
            title: "Second",
            invitation: "Pause?",
            focuses: [],
            steps: secondRoutine.steps
        )
        if BalancedRoutineSelector.suggestion(
            from: [untaggedFirst, untaggedSecond],
            completionHistory: [untaggedFirst.id]
        ) != untaggedSecond {
            failures.append("balanced selection should fall back to deterministic rotation")
        }

        let suiteName = "local.break-companion.pilot.self-check.\(ProcessInfo.processInfo.processIdentifier)"
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
            let firstLaunch = RoutineSelectionStore(defaults: defaults)
            _ = firstLaunch.suggestion(from: BreakRoutine.all)
            let restartedWhilePending = RoutineSelectionStore(defaults: defaults)
            if restartedWhilePending.suggestion(from: BreakRoutine.all) != firstRoutine {
                failures.append("a pending routine should survive a selection-store restart")
            }
            restartedWhilePending.markCompleted(firstRoutine)
            let restartedAfterCompletion = RoutineSelectionStore(defaults: defaults)
            if restartedAfterCompletion.suggestion(from: BreakRoutine.all) != handsRoutine {
                failures.append("completed routine state should survive a selection-store restart")
            }
            defaults.removePersistentDomain(forName: suiteName)
        } else {
            failures.append("could not create isolated preferences for persistence check")
        }

        if failures.isEmpty {
            print("Self-check passed: progress color and accessibility, ten routines, focus taxonomy, balanced history, safe fallback, random next, voice routing, pointer movement, and persistence.")
            return true
        }

        failures.forEach { print("Self-check failed: \($0)") }
        return false
    }
}
