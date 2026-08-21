import XCTest
@testable import BreakCompanion

final class BreakCompanionTests: XCTestCase {
    func testEveryRoutineIsExactlyTwoMinutes() {
        XCTAssertEqual(BreakRoutine.all.count, 10)
        XCTAssertEqual(Set(BreakRoutine.all.map(\.id)).count, 10)
        for routine in BreakRoutine.all {
            XCTAssertEqual(routine.duration, 120, "\(routine.title) should last two minutes")
            XCTAssertFalse(routine.steps.isEmpty)
        }
    }

    func testVoiceCommands() {
        XCTAssertEqual(VoiceCommandParser.parse("yes, let's start"), .start)
        XCTAssertEqual(VoiceCommandParser.parse("maybe in 20 minutes"), .later(minutes: 20))
        XCTAssertEqual(VoiceCommandParser.parse("maybe in twenty minutes"), .later(minutes: 20))
        XCTAssertEqual(VoiceCommandParser.parse("try again in an hour"), .later(minutes: 60))
        XCTAssertEqual(VoiceCommandParser.parse("two hours"), .later(minutes: 120))
        XCTAssertEqual(VoiceCommandParser.parse("tomorrow please"), .tomorrow)
        XCTAssertEqual(
            CheckInVoiceAction.resolve(VoiceCommandParser.parse("start")),
            .startRoutine,
            "A recognized start command must route to the offered routine"
        )
    }

    func testRoutineSafetyLanguage() {
        for routine in BreakRoutine.all {
            let script = routine.steps.map(\.instruction).joined(separator: " ").lowercased()
            XCTAssertTrue(script.contains("stop if anything hurts"))
            XCTAssertTrue(script.contains("gentl") || script.contains("slow"))
        }
    }

    func testPointerMovementClassifierKeepsADeadZoneForTaps() {
        XCTAssertEqual(
            PointerMovementClassifier.classify(from: .zero, to: .zero),
            .tap
        )
        XCTAssertEqual(
            PointerMovementClassifier.classify(from: .zero, to: CGPoint(x: 4, y: 0)),
            .tap,
            "Movement at the threshold should not turn a slightly shaky click into a drag"
        )
        XCTAssertEqual(
            PointerMovementClassifier.classify(from: .zero, to: CGPoint(x: 3, y: 4)),
            .drag,
            "Movement past the threshold should reposition the orb without activating it"
        )
    }

    func testRandomNextNeverRepeatsCurrentAndCoversTenRoutineLibrary() {
        XCTAssertEqual(BreakRoutine.all.count, 10)

        for current in BreakRoutine.all {
            let alternatives = BreakRoutine.all.filter { $0.id != current.id }
            let selected = alternatives.indices.compactMap { index in
                RandomRoutineSelector.next(
                    from: BreakRoutine.all,
                    currentRoutineID: current.id,
                    chooseIndex: { range in
                        XCTAssertTrue(range.contains(index))
                        return index
                    }
                )
            }

            XCTAssertEqual(selected.count, 9)
            XCTAssertFalse(selected.contains(where: { $0.id == current.id }))
            XCTAssertEqual(Set(selected.map(\.id)), Set(alternatives.map(\.id)))
        }
    }

    func testRandomNextNeedsAnAlternative() {
        XCTAssertNil(
            RandomRoutineSelector.next(
                from: [BreakRoutine.all[0]],
                currentRoutineID: BreakRoutine.all[0].id,
                chooseIndex: { _ in XCTFail("No random choice should be requested"); return 0 }
            )
        )
    }

    func testPostponementKeepsThePendingRoutine() {
        let pending = BreakRoutine.all[1]
        XCTAssertEqual(
            RoutineSelectionPolicy.suggestion(
                from: BreakRoutine.all,
                pendingRoutineID: pending.id,
                lastCompletedRoutineID: BreakRoutine.all[0].id
            ),
            pending
        )
    }

    func testCompletionAdvancesAndWrapsRoutineSelection() {
        XCTAssertEqual(
            RoutineSelectionPolicy.suggestion(
                from: BreakRoutine.all,
                pendingRoutineID: nil,
                lastCompletedRoutineID: BreakRoutine.all[0].id
            ),
            BreakRoutine.all[1]
        )
        XCTAssertEqual(
            RoutineSelectionPolicy.suggestion(
                from: BreakRoutine.all,
                pendingRoutineID: nil,
                lastCompletedRoutineID: BreakRoutine.all.last!.id
            ),
            BreakRoutine.all[0]
        )
    }

    func testSelectionStorePersistsPendingAndCompletedState() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstLaunch = RoutineSelectionStore(defaults: defaults)
        let firstSuggestion = firstLaunch.suggestion(from: BreakRoutine.all)
        XCTAssertEqual(firstSuggestion, BreakRoutine.all[0])

        let restartedWhilePending = RoutineSelectionStore(defaults: defaults)
        XCTAssertEqual(
            restartedWhilePending.suggestion(from: BreakRoutine.all),
            BreakRoutine.all[0],
            "An app restart must not replace a postponed or interrupted suggestion"
        )

        restartedWhilePending.markCompleted(BreakRoutine.all[0])
        let restartedAfterCompletion = RoutineSelectionStore(defaults: defaults)
        XCTAssertEqual(
            restartedAfterCompletion.suggestion(from: BreakRoutine.all),
            BreakRoutine.all[1],
            "An app restart after completion must advance to the next routine"
        )
    }
}
