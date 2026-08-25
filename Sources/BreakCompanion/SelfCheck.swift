import Foundation

enum SelfCheck {
    static func run() -> Bool {
        var failures: [String] = []

        checkReleaseIdentity(&failures)
        checkUpdateSupport(&failures)
        checkProgress(&failures)
        checkVoice(&failures)
        checkCompletion(&failures)
        checkMoveLibraryAndComposition(&failures)
        checkPersistence(&failures)
        checkConfigurationFlow(&failures)
        checkSupportiveCopy(&failures)
        checkPointer(&failures)
        checkActivityDetectionAndRecovery(&failures)

        if failures.isEmpty {
            print("Self-check passed: \(ProductIdentity.diagnosticsIdentity), semantic-version comparisons, GitHub Release asset selection and checksum verification, standing session composition, body-area selection, first-run and menu-bar configuration, legacy migration, supportive wording, recent-shown persistence, focus balance, voice variants, completion dismissal, progress color, pointer movement, and routine activity recovery.")
            return true
        }

        failures.forEach { print("Self-check failed: \($0)") }
        return false
    }

    private static func checkReleaseIdentity(_ failures: inout [String]) {
        let currentVersion = ProductIdentity.currentVersion
        let nextVersion = SemanticVersion(
            major: currentVersion.major,
            minor: currentVersion.minor,
            patch: currentVersion.patch + 1
        )
        let sameCoreStable = SemanticVersion(
            major: currentVersion.major,
            minor: currentVersion.minor,
            patch: currentVersion.patch
        )
        let sameCorePrerelease = SemanticVersion(
            major: currentVersion.major,
            minor: currentVersion.minor,
            patch: currentVersion.patch,
            prerelease: [.text("self-check")]
        )
        guard let largeNumericPrerelease = SemanticVersion(tag: "1.0.0-999999999999999999999"),
              let smallNumericPrerelease = SemanticVersion(tag: "1.0.0-2"),
              SemanticVersion(tag: "v\(currentVersion)") == currentVersion,
              nextVersion > currentVersion,
              sameCorePrerelease < sameCoreStable,
              largeNumericPrerelease > smallNumericPrerelease,
              SemanticVersion(tag: "1.0.0-é") == nil,
              SemanticVersion(tag: "not-a-version") == nil else {
            failures.append("semantic-version parsing or ordering is not deterministic")
            return
        }
        if ProductIdentity.diagnosticsIdentity != "\(ProductIdentity.name) \(currentVersion) (\(ProductIdentity.buildDisplay))" {
            failures.append("diagnostics should use the shared release identity")
        }
    }

    private static func checkUpdateSupport(_ failures: inout [String]) {
        let payload = Data("update-payload".utf8)
        let checksum = Data("faf613f495c32b8434726bd719da5f8901270370aa14f4259b1d3ec23f998fe1  artifact.zip\n".utf8)
        if !UpdateArtifactVerifier.verify(data: payload, checksumFile: checksum, expectedFileName: "artifact.zip")
            || UpdateArtifactVerifier.verify(data: Data("tampered".utf8), checksumFile: checksum, expectedFileName: "artifact.zip") {
            failures.append("release checksum verification accepted the wrong artifact")
        }

        let currentVersion = ProductIdentity.currentVersion
        let fixtureVersion = SemanticVersion(
            major: currentVersion.major,
            minor: currentVersion.minor,
            patch: currentVersion.patch + 1
        )
        let fixtureTag = "v\(fixtureVersion)"
        let artifactName = "\(ProductIdentity.name)-\(fixtureTag)-macos-arm64.zip"
        let checksumName = "\(artifactName).sha256"
        let release = GitHubRelease(
            tagName: fixtureTag,
            htmlURL: URL(string: "https://github.com/\(ProductIdentity.releaseRepository)/releases/tag/\(fixtureTag)")!,
            draft: false,
            prerelease: false,
            assets: [
                ReleaseAsset(
                    name: artifactName,
                    browserDownloadURL: URL(string: "https://github.com/\(ProductIdentity.releaseRepository)/releases/download/\(fixtureTag)/arm.zip")!
                ),
                ReleaseAsset(
                    name: checksumName,
                    browserDownloadURL: URL(string: "https://github.com/\(ProductIdentity.releaseRepository)/releases/download/\(fixtureTag)/arm.sha256")!
                )
            ]
        )
        do {
            guard let candidate = try GitHubReleaseSelector.candidate(
                from: release,
                currentVersion: currentVersion,
                architecture: "arm64"
            ), candidate.version == fixtureVersion else {
                failures.append("GitHub Release asset selection did not find the exact architecture contract")
                return
            }
        } catch {
            failures.append("valid GitHub Release assets were rejected: \(error.localizedDescription)")
        }

        let unsafe = ReleaseAsset(
            name: artifactName,
            browserDownloadURL: URL(string: "http://example.com/update.zip")!
        )
        let unsafeChecksum = ReleaseAsset(
            name: checksumName,
            browserDownloadURL: URL(string: "https://github.com/\(ProductIdentity.releaseRepository)/releases/download/\(fixtureTag)/update.sha256")!
        )
        let unsafeRelease = GitHubRelease(
            tagName: fixtureTag,
            htmlURL: release.htmlURL,
            draft: false,
            prerelease: false,
            assets: [unsafe, unsafeChecksum]
        )
        do {
            _ = try GitHubReleaseSelector.candidate(
                from: unsafeRelease,
                currentVersion: currentVersion,
                architecture: "arm64"
            )
            failures.append("an insecure GitHub asset URL was accepted")
        } catch let failure as UpdateFailure {
            if failure != .invalidAssetURL("http://example.com/update.zip") {
                failures.append("an insecure asset failed with the wrong recovery error")
            }
        } catch {
            failures.append("an insecure asset failed with an unexpected error")
        }
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
        if let neckSession = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: [],
            recentCompletedMoveIDs: [],
            selectedAreas: [.neck]
        ), let neckFollowUp = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: neckSession.moveIDs,
            recentCompletedMoveIDs: [],
            excluding: Set(neckSession.moveIDs),
            selectedAreas: [.neck]
        ) {
            let neckIDs = Set(MoveLibrary.all.filter { $0.bodyAreas.contains(.neck) }.map(\.id))
            let carried = Set(neckFollowUp.moveIDs).intersection(neckIDs)
            let announcesNeck = neckFollowUp.title.lowercased().contains("neck")
                || neckFollowUp.invitation.lowercased().contains("neck")
            if carried.isEmpty, announcesNeck {
                failures.append("a session should not announce an area it carries no movements for")
            }
            if carried.count < 3 {
                failures.append("a follow-up session should keep the selected-area quota")
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

    // Mirrors the XCTest configuration cases so they also run without Xcode's XCTest.
    private static func checkConfigurationFlow(_ failures: inout [String]) {
        MainActor.assumeIsolated {
            withIsolatedDefaults("configuration") { defaults in
                let fresh = CompanionStore(environment: [:], defaults: defaults)
                if fresh.mode != .setup || !fresh.selectedAreas.isEmpty {
                    failures.append("a fresh install should open the body-area setup")
                }
                if fresh.voice.isListening {
                    failures.append("setup should never require the microphone")
                }
                fresh.saveSelectedAreas([.lowerBack, .handsWrists])
                if fresh.mode != .idle || fresh.selectedAreas != [.lowerBack, .handsWrists] {
                    failures.append("saving areas should return to the orb with the selection kept")
                }
                if !fresh.canOpenAreaConfiguration {
                    failures.append("the menu-bar configuration item should be reachable while idle")
                }
                fresh.openAreaConfiguration()
                if fresh.mode != .configuration || !fresh.offersBalancedChoice {
                    failures.append("the menu bar should reopen the same configuration")
                }
                fresh.cancelAreaConfiguration()
                if fresh.mode != .idle || fresh.selectedAreas != [.lowerBack, .handsWrists] {
                    failures.append("cancelling configuration should leave the selection untouched")
                }

                let restarted = CompanionStore(environment: [:], defaults: defaults)
                if restarted.mode != .idle || restarted.selectedAreas != [.lowerBack, .handsWrists] {
                    failures.append("a saved selection should survive a restart without asking again")
                }
            }

            withIsolatedDefaults("existing-user") { defaults in
                defaults.set(["shoulder-rolls", "neck-turns"], forKey: "session.recentShownMoveIDs")
                let existing = CompanionStore(environment: [:], defaults: defaults)
                if existing.mode != .idle || !existing.selectedAreas.isEmpty {
                    failures.append("an existing install should stay usable on the balanced default")
                }
                if defaults.stringArray(forKey: "session.recentShownMoveIDs")
                    != ["shoulder-rolls", "neck-turns"] {
                    failures.append("existing move history should not be erased")
                }
            }

            withIsolatedDefaults("legacy-area") { defaults in
                defaults.set("shoulders", forKey: BodyAreaPreferences.legacyPreferredAreaKey)
                let migrated = CompanionStore(environment: [:], defaults: defaults)
                if migrated.mode != .idle || migrated.selectedAreas != [.shoulders] {
                    failures.append("a recognized legacy preference should migrate without a setup wall")
                }
            }

            withIsolatedDefaults("unknown-legacy-area") { defaults in
                defaults.set("upperBack", forKey: BodyAreaPreferences.legacyPreferredAreaKey)
                let unknown = CompanionStore(environment: [:], defaults: defaults)
                if !unknown.selectedAreas.isEmpty || unknown.mode != .setup {
                    failures.append("an unrecognized legacy preference should fall back to setup, not guess")
                }
                if defaults.string(forKey: BodyAreaPreferences.legacyPreferredAreaKey) != "upperBack" {
                    failures.append("an unrecognized legacy preference should not be silently rewritten")
                }
            }
        }
    }

    private static func checkSupportiveCopy(_ failures: inout [String]) {
        let clinicalTerms = [
            "cure", "heal", "treat", "diagnos", "symptom", "pain relief",
            "prevent", "rsi", "carpal", "sciatica", "posture correction", "eliminate"
        ]
        var copy = BodyArea.allCases.flatMap { [$0.label, $0.setupDescription, $0.invitationNoun] }
        copy.append(contentsOf: MoveLibrary.all.flatMap { [$0.title, $0.instruction] })
        if let routine = SessionComposer.compose(
            from: MoveLibrary.all,
            recentShownMoveIDs: [],
            recentCompletedMoveIDs: [],
            selectedAreas: [.lowerBack]
        ) {
            copy.append(routine.title)
            copy.append(routine.invitation)
            copy.append(contentsOf: routine.steps.flatMap { [$0.instruction, $0.spokenInstruction] })
        } else {
            failures.append("could not compose a session to check its wording")
        }
        for text in copy.map({ $0.lowercased() }) {
            for term in clinicalTerms where text.contains(term) {
                failures.append("user-facing copy makes a clinical claim: \(term)")
            }
        }
    }

    private static func withIsolatedDefaults(
        _ label: String,
        _ body: (UserDefaults) -> Void
    ) {
        let suiteName = "local.break-companion.pilot.self-check.\(label).\(ProcessInfo.processInfo.processIdentifier)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removePersistentDomain(forName: suiteName)
        body(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private static func checkPointer(_ failures: inout [String]) {
        if PointerMovementClassifier.classify(from: .zero, to: CGPoint(x: 4, y: 0)) != .tap {
            failures.append("movement at the pointer threshold should remain a tap")
        }
        if PointerMovementClassifier.classify(from: .zero, to: CGPoint(x: 3, y: 4)) != .drag {
            failures.append("movement past the pointer threshold should become a drag")
        }
    }

    private static func checkActivityDetectionAndRecovery(_ failures: inout [String]) {
        var detector = RoutineActivityDetector()
        let start = Date(timeIntervalSinceReferenceDate: 400)
        detector.start(at: start, signal: LocalActivitySignal(keyboardIdle: 8, pointerIdle: 8))
        if detector.decision(
            at: start.addingTimeInterval(6),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 14, pointerIdle: 14)
        ) != .noNewActivity {
            failures.append("ageing idle signals should not read as resumed work")
        }
        if detector.decision(
            at: start.addingTimeInterval(7),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 0, pointerIdle: 15)
        ) != .resumedWork {
            failures.append("a post-grace activity reset should qualify as resumed work")
        }

        var sustained = RoutineActivityDetector()
        sustained.start(at: start, signal: LocalActivitySignal(keyboardIdle: 30, pointerIdle: 0.1))
        if sustained.decision(
            at: start.addingTimeInterval(1),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 0.2, pointerIdle: 1.1)
        ) != .initialGracePeriod {
            failures.append("activity inside the initial grace period should be tolerated")
        }
        if sustained.decision(
            at: start.addingTimeInterval(5),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 0.2, pointerIdle: 5.1)
        ) != .resumedWork {
            failures.append("typing that continues past the grace period should qualify as resumed work")
        }

        var pointer = RoutineActivityDetector()
        pointer.start(at: start, signal: LocalActivitySignal(keyboardIdle: 60, pointerIdle: 25))
        if pointer.decision(
            at: start.addingTimeInterval(30.3),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 90.3, pointerIdle: 0.3)
        ) != .noNewActivity {
            failures.append("a brief pointer reach toward a companion control should not cancel a routine")
        }
        pointer.noteCompanionInteraction(at: start.addingTimeInterval(30.5))
        if pointer.decision(
            at: start.addingTimeInterval(31.3),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 91.3, pointerIdle: 0.5)
        ) != .companionInteraction {
            failures.append("a companion control should open onto a live routine")
        }

        var withdrawing = RoutineActivityDetector()
        withdrawing.start(at: start, signal: LocalActivitySignal(keyboardIdle: 60, pointerIdle: 60))
        withdrawing.noteCompanionInteraction(at: start.addingTimeInterval(40))
        _ = withdrawing.decision(
            at: start.addingTimeInterval(41),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 101, pointerIdle: 0.4)
        )
        _ = withdrawing.decision(
            at: start.addingTimeInterval(42),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 102, pointerIdle: 0.3)
        )
        if withdrawing.decision(
            at: start.addingTimeInterval(43),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 103, pointerIdle: 0.7)
        ) != .noNewActivity {
            failures.append("pointer evidence gathered while protected should not cancel a routine")
        }

        var focused = RoutineActivityDetector()
        focused.start(at: start, signal: LocalActivitySignal(keyboardIdle: 60, pointerIdle: 60))
        if focused.decision(
            at: start.addingTimeInterval(10),
            isPaused: false,
            companionHasKeyboardFocus: true,
            signal: LocalActivitySignal(keyboardIdle: 0.2, pointerIdle: 70)
        ) != .companionInteraction {
            failures.append("keyboard input aimed at the companion panel should not cancel a routine")
        }

        var boundary = RoutineActivityDetector()
        boundary.start(at: start, signal: LocalActivitySignal(keyboardIdle: 60, pointerIdle: 60))
        _ = boundary.decision(
            at: start.addingTimeInterval(4.5),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 64.5, pointerIdle: 0.3)
        )
        if boundary.decision(
            at: start.addingTimeInterval(5.5),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 65.5, pointerIdle: 0.1)
        ) != .noNewActivity {
            failures.append("one mouse motion spanning the grace boundary should not cancel a routine")
        }

        var settling = RoutineActivityDetector()
        settling.start(at: start, signal: LocalActivitySignal(keyboardIdle: 60, pointerIdle: 60))
        _ = settling.decision(
            at: start.addingTimeInterval(1),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 61, pointerIdle: 0.4)
        )
        _ = settling.decision(
            at: start.addingTimeInterval(2),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 62, pointerIdle: 0.3)
        )
        if settling.decision(
            at: start.addingTimeInterval(5.2),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 65.2, pointerIdle: 0.6)
        ) != .noNewActivity {
            failures.append("settling in during the grace period should not cancel at the grace boundary")
        }

        var mousing = RoutineActivityDetector()
        mousing.start(at: start, signal: LocalActivitySignal(keyboardIdle: 60, pointerIdle: 60))
        _ = mousing.decision(
            at: start.addingTimeInterval(10),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 70, pointerIdle: 0.3)
        )
        if mousing.decision(
            at: start.addingTimeInterval(11),
            isPaused: false,
            signal: LocalActivitySignal(keyboardIdle: 71, pointerIdle: 0.4)
        ) != .resumedWork {
            failures.append("pointer movement across consecutive polls should qualify as resumed work")
        }

        var clicking = RoutineActivityDetector()
        clicking.start(
            at: start,
            signal: LocalActivitySignal(
                keyboardIdle: 60,
                mouseMovementIdle: 60,
                mouseClickIdle: 60,
                scrollWheelIdle: 60
            )
        )
        _ = clicking.decision(
            at: start.addingTimeInterval(10),
            isPaused: false,
            signal: LocalActivitySignal(
                keyboardIdle: 70,
                mouseMovementIdle: 70,
                mouseClickIdle: 0.3,
                scrollWheelIdle: 70
            )
        )
        if clicking.decision(
            at: start.addingTimeInterval(11),
            isPaused: false,
            signal: LocalActivitySignal(
                keyboardIdle: 71,
                mouseMovementIdle: 71,
                mouseClickIdle: 0.4,
                scrollWheelIdle: 71
            )
        ) != .resumedWork {
            failures.append("mouse clicks without movement should qualify as resumed work")
        }

        var scrolling = RoutineActivityDetector()
        scrolling.start(
            at: start,
            signal: LocalActivitySignal(
                keyboardIdle: 60,
                mouseMovementIdle: 60,
                mouseClickIdle: 60,
                scrollWheelIdle: 60
            )
        )
        _ = scrolling.decision(
            at: start.addingTimeInterval(10),
            isPaused: false,
            signal: LocalActivitySignal(
                keyboardIdle: 70,
                mouseMovementIdle: 70,
                mouseClickIdle: 70,
                scrollWheelIdle: 0.3
            )
        )
        if scrolling.decision(
            at: start.addingTimeInterval(11),
            isPaused: false,
            signal: LocalActivitySignal(
                keyboardIdle: 71,
                mouseMovementIdle: 71,
                mouseClickIdle: 71,
                scrollWheelIdle: 0.4
            )
        ) != .resumedWork {
            failures.append("scrolling without movement should qualify as resumed work")
        }

        var budgeted = RoutineActivityDetector()
        budgeted.start(at: start, signal: LocalActivitySignal(keyboardIdle: 60, pointerIdle: 60))
        var poll = 6.0
        var lastDecision = RoutineActivityDecision.noNewActivity
        while poll < 100 {
            budgeted.noteCompanionInteraction(at: start.addingTimeInterval(poll))
            lastDecision = budgeted.decision(
                at: start.addingTimeInterval(poll),
                isPaused: false,
                signal: LocalActivitySignal(keyboardIdle: 60 + poll, pointerIdle: 0.2)
            )
            if lastDecision == .resumedWork { break }
            poll += 1
        }
        if lastDecision != .resumedWork
            || budgeted.companionProtectionUsed > RoutineActivityPolicy.companionProtectionBudget {
            failures.append("companion protection should be capped by its per-routine budget")
        }

        MainActor.assumeIsolated {
            withIsolatedDefaults("activity-recovery") { defaults in
                let store = CompanionStore(environment: ["BREAK_INTERVAL_SECONDS": "3600"], defaults: defaults)
                store.continueWithBalancedDefaults()
                defaults.set(["shoulder-rolls"], forKey: "session.recentCompletedMoveIDs")
                store.startRoutine(at: start, activitySignal: LocalActivitySignal(keyboardIdle: 8, pointerIdle: 8))
                if store.evaluateRoutineActivity(
                    signal: LocalActivitySignal(keyboardIdle: 14, pointerIdle: 14),
                    at: start.addingTimeInterval(6)
                ) != .noNewActivity {
                    failures.append("an unattended routine should keep running")
                }
                _ = store.evaluateRoutineActivity(
                    signal: LocalActivitySignal(keyboardIdle: 0, pointerIdle: 15),
                    at: start.addingTimeInterval(7)
                )
                if store.mode != .checkIn
                    || store.activityRecoveryExplanation == nil
                    || defaults.stringArray(forKey: "session.recentCompletedMoveIDs") != ["shoulder-rolls"] {
                    failures.append("resumed activity should recover without completion credit")
                }
                store.startRoutine(at: start.addingTimeInterval(8), activitySignal: LocalActivitySignal(keyboardIdle: 0, pointerIdle: 0))
                store.endRoutine()
            }

            withIsolatedDefaults("activity-companion-protection") { defaults in
                let store = CompanionStore(environment: ["BREAK_INTERVAL_SECONDS": "3600"], defaults: defaults)
                store.continueWithBalancedDefaults()
                store.startRoutine(at: start, activitySignal: LocalActivitySignal(keyboardIdle: 30, pointerIdle: 30))
                store.noteCompanionInteraction(at: start.addingTimeInterval(6))
                if store.evaluateRoutineActivity(
                    signal: LocalActivitySignal(keyboardIdle: 0.2, pointerIdle: 0.2),
                    at: start.addingTimeInterval(7)
                ) != .companionInteraction || store.mode != .routine {
                    failures.append("interacting with the companion should not cancel the routine")
                }
                if store.evaluateRoutineActivity(
                    signal: LocalActivitySignal(keyboardIdle: 0.2, pointerIdle: 0.2),
                    at: start.addingTimeInterval(10)
                ) != .resumedWork || store.mode != .checkIn {
                    failures.append("work resumed after companion protection should recover")
                }
                store.startRoutine(at: start.addingTimeInterval(11), activitySignal: LocalActivitySignal(keyboardIdle: 0, pointerIdle: 0))
                store.endRoutine()
            }

            withIsolatedDefaults("activity-next-restart") { defaults in
                let store = CompanionStore(environment: ["BREAK_INTERVAL_SECONDS": "3600"], defaults: defaults)
                store.continueWithBalancedDefaults()
                store.startRoutine(at: start, activitySignal: LocalActivitySignal(keyboardIdle: 60, pointerIdle: 60))
                var poll = 1.0
                while poll <= 30 {
                    store.noteCompanionInteraction(at: start.addingTimeInterval(poll))
                    poll += 1
                }
                store.nextRoutine(at: start.addingTimeInterval(30), activitySignal: LocalActivitySignal(keyboardIdle: 90, pointerIdle: 0.2))
                _ = store.evaluateRoutineActivity(
                    signal: LocalActivitySignal(keyboardIdle: 91, pointerIdle: 0.3),
                    at: start.addingTimeInterval(31)
                )
                if store.evaluateRoutineActivity(
                    signal: LocalActivitySignal(keyboardIdle: 0.2, pointerIdle: 0.4),
                    at: start.addingTimeInterval(32)
                ) != .initialGracePeriod || store.mode != .routine {
                    failures.append("Next should give the new routine its own grace period")
                }
                store.noteCompanionInteraction(at: start.addingTimeInterval(36))
                _ = store.evaluateRoutineActivity(
                    signal: LocalActivitySignal(keyboardIdle: 96, pointerIdle: 0.3),
                    at: start.addingTimeInterval(37)
                )
                if store.evaluateRoutineActivity(
                    signal: LocalActivitySignal(keyboardIdle: 0.2, pointerIdle: 0.4),
                    at: start.addingTimeInterval(38)
                ) != .companionInteraction {
                    failures.append("Next should give the new routine its own protection budget")
                }
                store.endRoutine()
            }
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
