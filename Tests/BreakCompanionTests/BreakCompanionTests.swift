import XCTest
@testable import BreakCompanion

final class BreakCompanionTests: XCTestCase {
    func testBreakProgressAtBeginningMidpointNearDueAndDeferralReset() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let deferral = ScheduledCheckInWindow(
            startedAt: start,
            dueAt: start.addingTimeInterval(1_200)
        )

        XCTAssertEqual(BreakProgress.value(activeSeconds: 0, activeInterval: 3_600, scheduledWindow: nil, now: start), 0)
        XCTAssertEqual(BreakProgress.value(activeSeconds: 1_800, activeInterval: 3_600, scheduledWindow: nil, now: start), 0.5)
        XCTAssertEqual(BreakProgress.value(activeSeconds: 3_240, activeInterval: 3_600, scheduledWindow: nil, now: start), 0.9)
        XCTAssertEqual(BreakProgress.value(activeSeconds: 4_000, activeInterval: 3_600, scheduledWindow: nil, now: start), 1)
        XCTAssertEqual(BreakProgress.value(activeSeconds: 2_700, activeInterval: 3_600, scheduledWindow: deferral, now: start), 0)
        XCTAssertEqual(BreakProgress.value(activeSeconds: 0, activeInterval: 3_600, scheduledWindow: deferral, now: start.addingTimeInterval(600)), 0.5)
        XCTAssertEqual(BreakProgress.remainingSeconds(activeSeconds: 0, activeInterval: 3_600, scheduledWindow: deferral, now: start.addingTimeInterval(600)), 600)
    }

    func testBreakProgressColorAndAccessibilityMapping() {
        XCTAssertEqual(BreakProgress.color(at: 0), OrbProgressColor(red: 0.30, green: 0.68, blue: 0.52))
        XCTAssertEqual(BreakProgress.color(at: 0.5), OrbProgressColor(red: 0.88, green: 0.58, blue: 0.28))
        XCTAssertEqual(BreakProgress.color(at: 1), OrbProgressColor(red: 0.78, green: 0.34, blue: 0.32))
        XCTAssertEqual(
            BreakProgress.accessibilityValue(progress: 0.5, remainingSeconds: 1_800),
            "Next break in about 30 minutes. 50 percent of the interval has elapsed."
        )
    }

    func testAffirmativeVoiceVariantsStartTheOfferedBreak() {
        let phrases = [
            "yeah", "yes", "yep", "let's do it", "let’s do it", "LET'S GO!",
            "let us do it", "okay", "ready", "sure", "go ahead", "sounds good"
        ]
        for phrase in phrases {
            XCTAssertEqual(VoiceCommandParser.parse(phrase), .start, phrase)
            XCTAssertEqual(
                CheckInVoiceAction.resolve(VoiceCommandParser.parse(phrase)),
                .startRoutine,
                phrase
            )
        }
    }

    func testPostponementVoiceCommandsRemainMoreSpecificThanAffirmatives() {
        XCTAssertEqual(VoiceCommandParser.parse("maybe in 20 minutes"), .later(minutes: 20))
        XCTAssertEqual(VoiceCommandParser.parse("maybe in twenty minutes"), .later(minutes: 20))
        XCTAssertEqual(VoiceCommandParser.parse("yes, later in an hour"), .later(minutes: 60))
        XCTAssertEqual(VoiceCommandParser.parse("two hours"), .later(minutes: 120))
        XCTAssertEqual(VoiceCommandParser.parse("tomorrow please"), .tomorrow)
        XCTAssertEqual(VoiceCommandParser.parse("yesterday"), .unknown)
    }

    func testEnterDismissesOnlyTheVisibleCompletion() {
        XCTAssertTrue(
            CompletionDismissalPolicy.shouldDismiss(
                isCompletionVisible: true,
                characters: "\r",
                keyCode: 36
            )
        )
        XCTAssertTrue(
            CompletionDismissalPolicy.shouldDismiss(
                isCompletionVisible: true,
                characters: nil,
                keyCode: 76
            )
        )
        XCTAssertFalse(
            CompletionDismissalPolicy.shouldDismiss(
                isCompletionVisible: false,
                characters: "\r",
                keyCode: 36
            )
        )
        XCTAssertFalse(
            CompletionDismissalPolicy.shouldDismiss(
                isCompletionVisible: true,
                characters: " ",
                keyCode: 49
            )
        )
    }

    func testCompletionAutoDismissDelayAndCancellationTokensAreDeterministic() {
        XCTAssertEqual(CompletionDismissalState.delaySeconds, 10)
        var state = CompletionDismissalState()
        let first = state.begin()
        XCTAssertTrue(state.isCurrent(first))

        state.cancel()
        XCTAssertFalse(state.isCurrent(first), "Manual Done must invalidate its pending automatic dismissal")

        let second = state.begin()
        XCTAssertTrue(state.isCurrent(second))
        XCTAssertFalse(state.isCurrent(first), "A stale task from an earlier completion must not close a future screen")
    }

    func testBodyAreaOptionsMatchTheScoutRecommendation() {
        XCTAssertEqual(
            BodyArea.allCases.map(\.label),
            ["Lower back", "Neck", "Shoulders", "Hands + wrists"]
        )
        XCTAssertEqual(BodyArea.allCases.count, 4)
        XCTAssertGreaterThanOrEqual(
            MoveLibrary.all.filter { $0.bodyAreas.contains(.lowerBack) }.count,
            6
        )
        XCTAssertGreaterThanOrEqual(
            MoveLibrary.all.filter { $0.bodyAreas.contains(.handsWrists) }.count,
            6
        )
        XCTAssertFalse(BodyArea.allCases.map(\.label).contains("Upper back"))
        XCTAssertFalse(BodyArea.allCases.map(\.label).contains("Eyes"))
    }

    func testMoveLibraryIsLargeUniqueStandingOnlyAndConservative() {
        XCTAssertGreaterThanOrEqual(MoveLibrary.all.count, 20)
        XCTAssertEqual(Set(MoveLibrary.all.map(\.id)).count, MoveLibrary.all.count)
        XCTAssertTrue(MoveLibrary.all.allSatisfy(\.supportsStanding))
        XCTAssertTrue(MoveLibrary.all.allSatisfy { !$0.focuses.isEmpty })
        XCTAssertEqual(Set(MoveLibrary.all.flatMap(\.focuses)), Set(BodyFocus.allCases))

        for move in MoveLibrary.all {
            let text = "\(move.title) \(move.instruction)".lowercased()
            XCTAssertFalse(text.contains("seated"), move.id)
            XCTAssertFalse(text.contains("sit down"), move.id)
            XCTAssertFalse(text.contains("chair"), move.id)
        }
    }

    func testEveryMotionCueMatchesTheDirectionItsInstructionAsks() {
        for move in MoveLibrary.all {
            let text = move.instruction.lowercased()
            let lateral = text.contains("right and left")
                || text.contains("left and right")
                || text.contains("side to side")
                || text.contains("one foot to the other")
            let forwardBack = text.contains("forward and back")
                || (text.contains("toes") && text.contains("heels"))

            if forwardBack {
                XCTAssertTrue([.rise, .breathe].contains(move.motion), move.id)
            }
            if lateral {
                XCTAssertEqual(move.motion, .sideToSide, move.id)
            }
            XCTAssertFalse(lateral && forwardBack, move.id)
        }
    }

    func testSelectedAreasPrioritizeAtLeastThreeMatchingMoves() {
        for area in [BodyArea.lowerBack, .neck, .shoulders, .handsWrists] {
            let matchingIDs = Set(
                MoveLibrary.all
                    .filter { $0.bodyAreas.contains(area) }
                    .map(\.id)
            )
            let routine = SessionComposer.compose(
                from: MoveLibrary.all,
                recentShownMoveIDs: [],
                recentCompletedMoveIDs: [],
                selectedAreas: [area]
            )

            XCTAssertNotNil(routine, area.label)
            XCTAssertGreaterThanOrEqual(
                Set(routine?.moveIDs ?? []).intersection(matchingIDs).count,
                3,
                area.label
            )
            XCTAssertTrue(routine?.invitation.lowercased().contains(area.invitationNoun) == true)
            XCTAssertTrue(routine?.invitation.lowercased().contains("stand") == true, area.label)
            XCTAssertTrue(routine?.title.lowercased().contains("standing reset") == true, area.label)
            XCTAssertEqual(routine?.duration, 120)
            XCTAssertEqual(Set(routine?.moveIDs ?? []).count, 6)
        }
    }

    func testMultipleSelectedAreasStillAnnounceAStandingReset() {
        let routine = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: [],
            recentCompletedMoveIDs: [],
            selectedAreas: [.lowerBack, .handsWrists]
        )!

        XCTAssertTrue(routine.invitation.lowercased().contains("stand"))
        XCTAssertTrue(routine.invitation.lowercased().contains("lower-back"))
        XCTAssertTrue(routine.invitation.lowercased().contains("hands-and-wrists"))
        XCTAssertEqual(routine.title, "Standing reset")
    }

    func testSelectedCopyStaysSupportiveAndNonDiagnostic() {
        let routine = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: [],
            recentCompletedMoveIDs: [],
            selectedAreas: [.lowerBack, .handsWrists]
        )!
        let productCopy = [ProductIdentity.name, ProductIdentity.configureAreasMenuTitle]
            + BodyArea.allCases.flatMap { [$0.label, $0.setupDescription, $0.invitationNoun] }
        let text = ([routine.title, routine.invitation] + routine.steps.map(\.instruction) + productCopy)
            .joined(separator: " ")
            .lowercased()
        for forbidden in [
            "treat", "cure", "prevent", "posture", "pain", "injur", "diagnos",
            "therap", "symptom", "rsi", "sciatica", "carpal tunnel", "medical", "clinic"
        ] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
    }

    func testAreaBiasStopsAtTheQuotaSoOtherContentStillReachesTheSession() {
        let library = (1...6).map { makeMove("back-\($0)", [.lowerBack], bodyAreas: [.lowerBack]) }
            + [
                makeMove("hands", [.handsWristsForearms]),
                makeMove("eyes", [.eyesFace]),
                makeMove("breath", [.breathRelaxation]),
                makeMove("feet", [.lowerLegsFeetAnkles])
            ]

        let routine = SessionComposer.compose(
            from: library,
            recentShownMoveIDs: [],
            recentCompletedMoveIDs: [],
            selectedAreas: [.lowerBack]
        )

        let moveIDs = routine?.moveIDs ?? []
        XCTAssertEqual(moveIDs.count, 6)
        XCTAssertEqual(moveIDs.filter { $0.hasPrefix("back-") }.count, 3)
        XCTAssertEqual(Set(moveIDs).intersection(["hands", "eyes", "breath"]).count, 3)
    }

    func testNextSessionAvoidsCurrentMovesEvenWhenTheAreaHasFewTaggedMoves() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let taggedNeckMoves = MoveLibrary.all.filter { $0.bodyAreas.contains(.neck) }
        XCTAssertLessThan(taggedNeckMoves.count, SessionComposer.sessionMoveCount)

        let store = SessionSelectionStore(defaults: defaults)
        let current = store.suggestion(from: MoveLibrary.all, selectedAreas: [.neck])!
        let next = store.nextSession(after: current, from: MoveLibrary.all, selectedAreas: [.neck])!

        XCTAssertTrue(Set(current.moveIDs).isDisjoint(with: next.moveIDs))
        XCTAssertEqual(Set(next.moveIDs).count, SessionComposer.sessionMoveCount)
        XCTAssertEqual(next.duration, 120)
    }

    func testComposedSessionIsStandingSafeUniqueAndExactlyTwoMinutes() {
        let routine = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: [],
            recentCompletedMoveIDs: []
        )

        XCTAssertNotNil(routine)
        XCTAssertEqual(routine?.steps.count, 6)
        XCTAssertEqual(routine?.duration, 120)
        XCTAssertEqual(Set(routine?.moveIDs ?? []).count, 6)
        XCTAssertTrue(routine?.invitation.lowercased().contains("stand") == true)
        XCTAssertTrue(routine?.steps.first?.instruction.lowercased().contains("stand when") == true)
        XCTAssertTrue(routine?.steps.first?.instruction.lowercased().contains("move gently") == true)
        XCTAssertTrue(routine?.steps.first?.instruction.lowercased().contains("stop if anything hurts") == true)
        XCTAssertTrue(routine?.steps.allSatisfy { $0.duration == 20 } == true)
    }

    func testSpokenGuidanceFitsAStepWhileTheScreenKeepsTheFullBoundary() {
        let routine = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: [],
            recentCompletedMoveIDs: []
        )!
        let first = routine.steps[0]

        XCTAssertTrue(first.instruction.contains("This is a standing reset."))
        XCTAssertTrue(first.instruction.lowercased().contains("stay in a comfortable range"))
        XCTAssertTrue(first.instruction.lowercased().contains("you feel unwell"))

        XCTAssertTrue(first.spokenInstruction.lowercased().contains("stand when you’re ready"))
        XCTAssertTrue(first.spokenInstruction.lowercased().contains("with support nearby if useful"))
        XCTAssertTrue(first.spokenInstruction.lowercased().contains("move gently"))
        XCTAssertTrue(first.spokenInstruction.lowercased().contains("stop if anything hurts"))
        XCTAssertLessThan(first.spokenInstruction.count, first.instruction.count)
        XCTAssertLessThanOrEqual(
            first.spokenInstruction.split(separator: " ").count,
            50,
            "step one speech must fit inside its twenty-second step"
        )

        for step in routine.steps.dropFirst() {
            XCTAssertEqual(step.spokenInstruction, step.instruction, step.id)
        }
    }

    func testNextCompositionAvoidsEveryMoveFromCurrentAndRecentSessions() {
        let first = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: [],
            recentCompletedMoveIDs: []
        )!
        let second = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: first.moveIDs,
            recentCompletedMoveIDs: [],
            excluding: Set(first.moveIDs)
        )!
        let third = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: first.moveIDs + second.moveIDs,
            recentCompletedMoveIDs: [],
            excluding: Set(second.moveIDs)
        )!

        XCTAssertTrue(Set(first.moveIDs).isDisjoint(with: second.moveIDs))
        XCTAssertTrue(Set(second.moveIDs).isDisjoint(with: third.moveIDs))
        XCTAssertTrue(Set(first.moveIDs).isDisjoint(with: third.moveIDs))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(second.id, third.id)
    }

    func testComposerFavorsUnderrepresentedFocusAreas() {
        let focusedLibrary = [
            makeMove("neck-a", [.neckShoulders]),
            makeMove("hands", [.handsWristsForearms]),
            makeMove("neck-b", [.neckShoulders]),
            makeMove("neck-c", [.neckShoulders]),
            makeMove("neck-d", [.neckShoulders]),
            makeMove("neck-e", [.neckShoulders]),
            makeMove("neck-f", [.neckShoulders])
        ]

        let routine = SessionComposer.compose(
            from: focusedLibrary,
            recentShownMoveIDs: [],
            recentCompletedMoveIDs: Array(repeating: "neck-a", count: 8)
        )
        XCTAssertEqual(routine?.moveIDs.first, "hands")
    }

    func testComposerHasDeterministicFallbackWhenHistoryCoversLibrary() {
        let allIDs = MoveLibrary.all.map(\.id)
        let current = Set(MoveLibrary.all.prefix(6).map(\.id))
        let first = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: allIDs,
            recentCompletedMoveIDs: allIDs,
            excluding: current
        )
        let second = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: allIDs,
            recentCompletedMoveIDs: allIDs,
            excluding: current
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first?.duration, 120)
        XCTAssertTrue(current.isDisjoint(with: first?.moveIDs ?? []))
    }

    func testMinimumLibraryFallbackRemainsSafeWhenNoAlternativeExists() {
        let minimumLibrary = Array(MoveLibrary.all.prefix(6))
        let current = Set(minimumLibrary.map(\.id))
        let fallback = SessionComposer.compose(
            from: minimumLibrary,
            recentShownMoveIDs: minimumLibrary.map(\.id),
            recentCompletedMoveIDs: [],
            excluding: current
        )

        XCTAssertEqual(fallback?.moveIDs, minimumLibrary.map(\.id))
        XCTAssertEqual(fallback?.duration, 120)
        XCTAssertNil(
            SessionComposer.compose(
                from: Array(minimumLibrary.prefix(5)),
                recentShownMoveIDs: [],
                recentCompletedMoveIDs: []
            )
        )
    }

    func testShownHistoryIncludesSkippedNextSessionsAndSurvivesRestart() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstStore = SessionSelectionStore(defaults: defaults)
        let first = firstStore.suggestion(from: MoveLibrary.all)!
        let second = firstStore.nextSession(after: first, from: MoveLibrary.all)!
        XCTAssertTrue(Set(first.moveIDs).isDisjoint(with: second.moveIDs))

        let restarted = SessionSelectionStore(defaults: defaults)
        XCTAssertEqual(restarted.suggestion(from: MoveLibrary.all), second)
        let third = restarted.nextSession(after: second, from: MoveLibrary.all)!
        XCTAssertTrue(Set(second.moveIDs).isDisjoint(with: third.moveIDs))
        XCTAssertTrue(Set(first.moveIDs).isDisjoint(with: third.moveIDs))

        let shown = defaults.stringArray(forKey: "session.recentShownMoveIDs")
        XCTAssertEqual(shown, first.moveIDs + second.moveIDs + third.moveIDs)
        XCTAssertEqual(defaults.stringArray(forKey: "session.pendingMoveIDs"), third.moveIDs)
    }

    func testCompletedMoveHistoryPersistsIsBoundedAndInfluencesRestart() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SessionSelectionStore(defaults: defaults)
        var routine = store.suggestion(from: MoveLibrary.all)!
        for _ in 0..<6 {
            store.markCompleted(routine)
            routine = store.suggestion(from: MoveLibrary.all)!
        }

        let completed = defaults.stringArray(forKey: "session.recentCompletedMoveIDs") ?? []
        let shown = defaults.stringArray(forKey: "session.recentShownMoveIDs") ?? []
        XCTAssertEqual(completed.count, SessionSelectionStore.completedHistoryLimit)
        XCTAssertLessThanOrEqual(shown.count, SessionSelectionStore.shownHistoryLimit)
        XCTAssertEqual(SessionSelectionStore(defaults: defaults).suggestion(from: MoveLibrary.all), routine)
    }

    func testEndingOrSkippingClearsPendingButRetainsShownHistory() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SessionSelectionStore(defaults: defaults)
        let shown = store.suggestion(from: MoveLibrary.all)!
        store.clearPendingSession()

        XCTAssertNil(defaults.object(forKey: "session.pendingMoveIDs"))
        XCTAssertNil(defaults.object(forKey: "session.recentCompletedMoveIDs"))
        XCTAssertEqual(defaults.stringArray(forKey: "session.recentShownMoveIDs"), shown.moveIDs)
    }

    func testLegacyRoutineHistoryMigratesToMoveFocusHistorySafely() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["neck-shoulders", "hands-wrists"], forKey: "routine.recentCompletionHistory")
        defaults.set("hands-wrists", forKey: "routine.pendingID")

        let store = SessionSelectionStore(defaults: defaults)
        XCTAssertNotNil(store.suggestion(from: MoveLibrary.all))
        XCTAssertNil(defaults.object(forKey: "routine.pendingID"))
        XCTAssertNil(defaults.object(forKey: "routine.recentCompletionHistory"))
        XCTAssertEqual(
            defaults.stringArray(forKey: "session.recentCompletedMoveIDs"),
            ["shoulder-rolls", "neck-turns", "upper-back-open", "hand-shake", "wrist-circles", "finger-fan"]
        )
    }

    func testBodyAreaPreferencesDefaultPersistAndMigrateSafely() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fresh = BodyAreaPreferences(defaults: defaults)
        XCTAssertTrue(fresh.shouldPresentFirstRunSetup)
        XCTAssertTrue(fresh.selectedAreas.isEmpty)

        fresh.save(selectedAreas: [.neck, .handsWrists])
        let restarted = BodyAreaPreferences(defaults: defaults)
        XCTAssertEqual(restarted.selectedAreas, [.neck, .handsWrists])
        XCTAssertTrue(restarted.onboardingCompleted)
        XCTAssertFalse(restarted.shouldPresentFirstRunSetup)

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("lowerBack", forKey: BodyAreaPreferences.legacyPreferredAreaKey)
        let migrated = BodyAreaPreferences(defaults: defaults)
        XCTAssertEqual(migrated.selectedAreas, [.lowerBack])
        XCTAssertTrue(migrated.onboardingCompleted)
        XCTAssertEqual(defaults.string(forKey: BodyAreaPreferences.legacyPreferredAreaKey), "lowerBack")

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(["shoulder-rolls"], forKey: "session.recentShownMoveIDs")
        let existing = BodyAreaPreferences(defaults: defaults)
        XCTAssertTrue(existing.selectedAreas.isEmpty)
        XCTAssertFalse(existing.shouldPresentFirstRunSetup)
    }

    @MainActor
    func testBodyAreaConfigurationCanBeReopenedFromMenuBarPath() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(ProductIdentity.configureAreasMenuTitle, "Choose body areas…")
        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults
        )
        XCTAssertEqual(store.mode, .setup)
        store.saveSelectedAreas([.neck])
        XCTAssertEqual(store.mode, .idle)
        store.openAreaConfiguration()
        XCTAssertEqual(store.mode, .configuration)
        store.saveSelectedAreas([.lowerBack, .handsWrists])
        XCTAssertEqual(store.mode, .idle)
        XCTAssertEqual(store.selectedAreas, [.lowerBack, .handsWrists])
    }

    @MainActor
    func testConfigurationAvailabilityFollowsIdleAndOffersBalancedReturn() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults
        )
        XCTAssertEqual(store.mode, .setup)
        XCTAssertFalse(store.canOpenAreaConfiguration)
        XCTAssertTrue(store.offersBalancedChoice)

        store.saveSelectedAreas([.neck])
        XCTAssertEqual(store.mode, .idle)
        XCTAssertEqual(store.selectedAreas, [.neck])
        XCTAssertTrue(store.canOpenAreaConfiguration)
        XCTAssertFalse(store.offersBalancedChoice)

        store.openAreaConfiguration()
        XCTAssertEqual(store.mode, .configuration)
        XCTAssertFalse(store.canOpenAreaConfiguration)
        XCTAssertTrue(store.offersBalancedChoice)

        store.continueWithBalancedDefaults()
        XCTAssertEqual(store.mode, .idle)
        XCTAssertTrue(store.selectedAreas.isEmpty)

        let restarted = BodyAreaPreferences(defaults: defaults)
        XCTAssertTrue(restarted.selectedAreas.isEmpty)
        XCTAssertTrue(restarted.onboardingCompleted)
        XCTAssertFalse(restarted.shouldPresentFirstRunSetup)

        let reopened = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults
        )
        XCTAssertEqual(reopened.mode, .idle)
        XCTAssertTrue(reopened.selectedAreas.isEmpty)
    }

    @MainActor
    func testNextRequestsAPanelRefitForTheNewSessionContent() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults
        )
        store.continueWithBalancedDefaults()
        store.startRoutine()

        var resizedModes: [CompanionStore.Mode] = []
        store.onSizeChange = { resizedModes.append($0) }
        let current = store.routine
        store.nextRoutine()

        XCTAssertNotEqual(store.routine, current)
        XCTAssertEqual(store.stepIndex, 0)
        XCTAssertEqual(resizedModes, [.routine])

        store.endRoutine()
    }

    func testPointerMovementClassifierKeepsTapDeadZone() {
        XCTAssertEqual(PointerMovementClassifier.classify(from: .zero, to: CGPoint(x: 4, y: 0)), .tap)
        XCTAssertEqual(PointerMovementClassifier.classify(from: .zero, to: CGPoint(x: 3, y: 4)), .drag)
    }

    private func makeMove(
        _ id: String,
        _ focuses: Set<BodyFocus>,
        bodyAreas: Set<BodyArea> = []
    ) -> BreakMove {
        BreakMove(
            id: id,
            title: id,
            instruction: "Move slowly and comfortably.",
            focuses: focuses,
            bodyAreas: bodyAreas,
            motion: .still,
            supportsStanding: true
        )
    }
}
