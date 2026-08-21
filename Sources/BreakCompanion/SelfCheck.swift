import Foundation

enum SelfCheck {
    static func run() -> Bool {
        var failures: [String] = []

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
            if restartedAfterCompletion.suggestion(from: BreakRoutine.all) != secondRoutine {
                failures.append("completed routine state should survive a selection-store restart")
            }
            defaults.removePersistentDomain(forName: suiteName)
        } else {
            failures.append("could not create isolated preferences for persistence check")
        }

        if failures.isEmpty {
            print("Self-check passed: ten routines, timing, safety language, voice command routing, random next, pointer movement, and persisted selection.")
            return true
        }

        failures.forEach { print("Self-check failed: \($0)") }
        return false
    }
}
