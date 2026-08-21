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

    func testRoutineFocusTaxonomyIsCompleteAndConservative() {
        let expected: [String: Set<BodyFocus>] = [
            "neck-shoulders": [.neckShoulders, .upperBackPosture, .breathRelaxation],
            "eyes-posture": [.eyesFace, .upperBackPosture, .neckShoulders],
            "standing-reset": [.lowerLegsFeetAnkles, .upperBackPosture, .breathRelaxation],
            "hands-wrists": [.handsWristsForearms],
            "seated-twist": [.trunkMobility, .upperBackPosture],
            "breathing-reset": [.breathRelaxation],
            "feet-ankles": [.lowerLegsFeetAnkles],
            "jaw-face": [.eyesFace, .breathRelaxation],
            "upper-back": [.upperBackPosture, .chestSideBody, .neckShoulders],
            "side-stretch": [.chestSideBody, .trunkMobility]
        ]

        XCTAssertEqual(Dictionary(uniqueKeysWithValues: BreakRoutine.all.map { ($0.id, $0.focuses) }), expected)
        XCTAssertEqual(Set(BreakRoutine.all.flatMap(\.focuses)), Set(BodyFocus.allCases))
        XCTAssertTrue(BreakRoutine.all.allSatisfy { !$0.focuses.isEmpty })
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

    func testBalancedSelectionFavorsUnderrepresentedFocusAfterSkewedHistory() {
        let history = Array(repeating: "neck-shoulders", count: 6)
        XCTAssertEqual(
            BalancedRoutineSelector.suggestion(from: BreakRoutine.all, completionHistory: history)?.id,
            "hands-wrists"
        )
    }

    func testBalancedSelectionNeverImmediatelyRepeatsLastCompletedRoutine() {
        for routine in BreakRoutine.all {
            let selected = BalancedRoutineSelector.suggestion(
                from: BreakRoutine.all,
                completionHistory: [routine.id]
            )
            XCTAssertNotEqual(selected?.id, routine.id)
        }
    }

    func testBalancedSelectionUsesOnlyRecentCompletionWindow() {
        let olderHistory = Array(repeating: "hands-wrists", count: 6)
        let recentHistory = Array(repeating: "neck-shoulders", count: 6)
        XCTAssertEqual(
            BalancedRoutineSelector.suggestion(
                from: BreakRoutine.all,
                completionHistory: olderHistory + recentHistory
            )?.id,
            "hands-wrists",
            "Older hand-focused history should not affect the six-completion window"
        )
    }

    func testBalancedSelectionHasDeterministicFallbackWithoutTags() {
        let step = RoutineStep(
            title: "Settle",
            instruction: "Move gently, and stop if anything hurts.",
            duration: 120,
            motion: .still
        )
        let first = BreakRoutine(id: "first", title: "First", invitation: "Pause?", focuses: [], steps: [step])
        let second = BreakRoutine(id: "second", title: "Second", invitation: "Pause?", focuses: [], steps: [step])

        XCTAssertEqual(
            BalancedRoutineSelector.suggestion(
                from: [first, second],
                completionHistory: [first.id]
            ),
            second
        )
        XCTAssertEqual(
            BalancedRoutineSelector.suggestion(from: [first, second], completionHistory: []),
            first
        )
    }

    func testLegacyRotationPolicyProvidesDeterministicFallback() {
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

    func testSelectionStorePersistsPendingAndBalancedHistory() {
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
            restartedAfterCompletion.suggestion(from: BreakRoutine.all)?.id,
            "hands-wrists",
            "An app restart must retain completion history for balancing"
        )
    }

    func testSelectionStoreMigratesLegacyLastCompletedState() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("neck-shoulders", forKey: "routine.lastCompletedID")

        let migrated = RoutineSelectionStore(defaults: defaults)
        XCTAssertEqual(migrated.suggestion(from: BreakRoutine.all)?.id, "hands-wrists")
    }

    func testSelectionStoreRejectsStalePendingImmediateRepeat() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("neck-shoulders", forKey: "routine.lastCompletedID")
        defaults.set("neck-shoulders", forKey: "routine.pendingID")

        let store = RoutineSelectionStore(defaults: defaults)
        XCTAssertEqual(store.suggestion(from: BreakRoutine.all)?.id, "hands-wrists")
    }

    func testSelectionStoreLimitsPersistedHistoryToRecentWindow() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = RoutineSelectionStore(defaults: defaults)

        for routine in BreakRoutine.all.prefix(8) {
            store.markCompleted(routine)
        }

        XCTAssertEqual(
            defaults.stringArray(forKey: "routine.recentCompletionHistory"),
            Array(BreakRoutine.all.prefix(8).suffix(6).map(\.id))
        )
    }
}
