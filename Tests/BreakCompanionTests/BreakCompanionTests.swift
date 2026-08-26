import CryptoKit
import XCTest
@testable import BreakCompanion

@MainActor
private final class ManualDelayedActionScheduler: DelayedActionScheduling {
    private var pendingAction: (() -> Void)?

    func schedule(after _: TimeInterval, action: @escaping () -> Void) {
        pendingAction = action
    }

    func runPendingAction() {
        let action = pendingAction
        pendingAction = nil
        action?()
    }
}

final class BreakCompanionTests: XCTestCase {
    func testSemanticVersionIsSharedAndOrdersReleaseTags() {
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
        XCTAssertEqual(currentVersion.description, "0.1.1")
        XCTAssertEqual(SemanticVersion(tag: "v\(currentVersion)"), currentVersion)
        XCTAssertGreaterThan(nextVersion, currentVersion)
        XCTAssertLessThan(sameCorePrerelease, sameCoreStable)
        XCTAssertNil(SemanticVersion(tag: "release-\(currentVersion)"))
        XCTAssertEqual(
            ProductIdentity.diagnosticsIdentity,
            "\(ProductIdentity.name) \(currentVersion) (\(ProductIdentity.buildDisplay))"
        )
    }

    func testSemanticVersionRejectsNonASCIIIdentifiersAndOrdersLargeNumericIdentifiers() {
        let large = SemanticVersion(tag: "1.0.0-999999999999999999999")!
        let small = SemanticVersion(tag: "1.0.0-2")!

        XCTAssertGreaterThan(large, small)
        XCTAssertEqual(large.description, "1.0.0-999999999999999999999")
        XCTAssertNil(SemanticVersion(tag: "1.0.0-é"))
        XCTAssertNil(SemanticVersion(tag: "1.0.0-１２"))
    }

    func testSemanticVersionRejectsCoreNumbersOutsideRuntimeRange() {
        XCTAssertNil(SemanticVersion(tag: "9223372036854775807.0.0"))
        XCTAssertNil(SemanticVersion(tag: "9223372036854775808.0.0"))
        XCTAssertNil(SemanticVersion(tag: "999999999999999999999.0.0"))
        XCTAssertNil(SemanticVersion(tag: "0.999999999999999999999.0"))
        XCTAssertNil(SemanticVersion(tag: "0.0.999999999999999999999"))
    }

    func testReleaseChecksumMustMatchTheNamedArtifact() {
        let data = Data("update-payload".utf8)
        let checksum = Data("faf613f495c32b8434726bd719da5f8901270370aa14f4259b1d3ec23f998fe1  artifact.zip\n".utf8)
        XCTAssertTrue(UpdateArtifactVerifier.verify(data: data, checksumFile: checksum, expectedFileName: "artifact.zip"))
        XCTAssertEqual(
            UpdateArtifactVerifier.verifiedSHA256(data: data, checksumFile: checksum, expectedFileName: "artifact.zip"),
            "faf613f495c32b8434726bd719da5f8901270370aa14f4259b1d3ec23f998fe1"
        )
        XCTAssertFalse(UpdateArtifactVerifier.verify(data: Data("tampered".utf8), checksumFile: checksum, expectedFileName: "artifact.zip"))
        XCTAssertFalse(UpdateArtifactVerifier.verify(data: data, checksumFile: checksum, expectedFileName: "other.zip"))
    }

    func testGitHubReleaseSelectionRequiresExactHTTPSAssetsForThisMac() throws {
        let releaseVersion = nextReleaseVersion
        let releaseTag = "v\(releaseVersion)"
        let artifactName = "\(ProductIdentity.name)-\(releaseTag)-macos-x86_64.zip"
        let checksumName = "\(artifactName).sha256"
        let artifactURL = URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/\(releaseTag)/app.zip")!
        let checksumURL = URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/\(releaseTag)/app.sha256")!
        let release = GitHubRelease(
            tagName: releaseTag,
            htmlURL: URL(string: "https://github.com/\(ProductIdentity.releaseRepository)/releases/tag/\(releaseTag)")!,
            draft: false,
            prerelease: false,
            assets: [
                ReleaseAsset(name: artifactName, browserDownloadURL: artifactURL),
                ReleaseAsset(name: checksumName, browserDownloadURL: checksumURL)
            ]
        )
        let candidate = try GitHubReleaseSelector.candidate(
            from: release,
            currentVersion: ProductIdentity.currentVersion,
            architecture: "x86_64"
        )
        XCTAssertEqual(candidate?.artifactName, artifactName)
        XCTAssertEqual(candidate?.checksumName, checksumName)
        XCTAssertEqual(candidate?.artifactURL, artifactURL)

        let insecure = GitHubRelease(
            tagName: releaseTag,
            htmlURL: release.htmlURL,
            draft: false,
            prerelease: false,
            assets: [
                ReleaseAsset(name: artifactName, browserDownloadURL: URL(string: "http://example.com/app.zip")!),
                ReleaseAsset(name: checksumName, browserDownloadURL: checksumURL)
            ]
        )
        XCTAssertThrowsError(try GitHubReleaseSelector.candidate(
            from: insecure,
            currentVersion: ProductIdentity.currentVersion,
            architecture: "x86_64"
        ))
    }

    @MainActor
    func testMissingReadyUpdateCanReturnToManualCheck() async throws {
        let releaseVersion = nextReleaseVersion
        let releaseTag = "v\(releaseVersion)"
        let artifactName = "\(ProductIdentity.name)-\(releaseTag)-macos-arm64.zip"
        let artifactURL = URL(string: "https://github.com/\(ProductIdentity.releaseRepository)/releases/download/\(releaseTag)/app.zip")!
        let checksumURL = URL(string: "https://github.com/\(ProductIdentity.releaseRepository)/releases/download/\(releaseTag)/app.sha256")!
        let artifact = Data("update-payload".utf8)
        let checksum = Data("faf613f495c32b8434726bd719da5f8901270370aa14f4259b1d3ec23f998fe1  \(artifactName)\n".utf8)
        let releaseJSON: [String: Any] = [
            "tag_name": releaseTag,
            "html_url": "https://github.com/\(ProductIdentity.releaseRepository)/releases/tag/\(releaseTag)",
            "draft": false,
            "prerelease": false,
            "assets": [
                ["name": artifactName, "browser_download_url": artifactURL.absoluteString],
                ["name": "\(artifactName).sha256", "browser_download_url": checksumURL.absoluteString]
            ]
        ]
        let transport = StubUpdateTransport(responses: [
            ProductIdentity.releaseAPIURL.absoluteString: try JSONSerialization.data(withJSONObject: releaseJSON),
            artifactURL.absoluteString: artifact,
            checksumURL.absoluteString: checksum
        ])
        let service = GitHubReleasesUpdateService(
            transport: transport,
            currentVersion: ProductIdentity.currentVersion,
            architecture: "arm64"
        )
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let handoffLauncher = RecordingUpdateHandoffLauncher()
        let controller = UpdateController(
            service: service,
            defaults: defaults,
            handoffLauncher: handoffLauncher
        )

        let checkExpectation = expectation(description: "manual update check")
        controller.onEvent = { event in
            if case .manualResult = event { checkExpectation.fulfill() }
        }
        controller.checkManually(now: Date(timeIntervalSinceReferenceDate: 100_000))
        await fulfillment(of: [checkExpectation], timeout: 1)
        guard case .available = controller.state else {
            XCTFail("the fixture should make an update available")
            return
        }

        let downloadExpectation = expectation(description: "verified update download")
        controller.onEvent = { event in
            if case .downloaded = event { downloadExpectation.fulfill() }
        }
        controller.downloadAvailable()
        await fulfillment(of: [downloadExpectation], timeout: 1)
        guard case .ready(let downloaded) = controller.state else {
            XCTFail("the fixture should produce a ready update")
            return
        }
        let temporaryDirectory = downloaded.artifactURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.removeItem(at: downloaded.artifactURL)

        controller.resetReadyUpdate()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(handoffLauncher.downloadedUpdates.isEmpty, "cancelling the ready update must not launch installation")

        let retryExpectation = expectation(description: "retry update check")
        controller.onEvent = { event in
            if case .manualResult = event { retryExpectation.fulfill() }
        }
        controller.checkManually(now: Date(timeIntervalSinceReferenceDate: 100_001))
        await fulfillment(of: [retryExpectation], timeout: 1)
        guard case .available = controller.state else {
            XCTFail("resetting a missing download should permit another check")
            return
        }
    }

    func testUpdateHandoffCopiesItsHelperAndPassesTheVerifiedArtifactContract() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("2m2better-handoff-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let archive = root.appendingPathComponent("verified.zip")
        let payload = Data("verified archive".utf8)
        try payload.write(to: archive)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let sourceHelper = root.appendingPathComponent("source-helper.sh")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: sourceHelper)

        let candidate = UpdateCandidate(
            version: nextReleaseVersion,
            releaseURL: ProductIdentity.releasesURL,
            artifactName: "2m2better-v\(nextReleaseVersion)-macos-arm64.zip",
            artifactURL: archive,
            checksumName: "verified.zip.sha256",
            checksumURL: root.appendingPathComponent("verified.zip.sha256")
        )
        let downloaded = DownloadedUpdate(
            candidate: candidate,
            artifactURL: archive,
            verifiedSHA256: digest
        )
        let processLauncher = RecordingHandoffProcessLauncher()
        let launcher = UpdateInstallHandoffLauncher(
            helperURL: sourceHelper,
            processLauncher: processLauncher,
            processID: 1234
        )

        try launcher.launch(for: downloaded)

        XCTAssertEqual(processLauncher.executableURL?.path, "/bin/sh")
        XCTAssertEqual(Array(processLauncher.arguments.dropFirst().prefix(2)), ["--archive", archive.path])
        XCTAssertTrue(processLauncher.arguments.contains("--pid"))
        XCTAssertTrue(processLauncher.arguments.contains("1234"))
        XCTAssertTrue(processLauncher.arguments.contains("--sha256"))
        XCTAssertTrue(processLauncher.arguments.contains(digest))
        XCTAssertTrue(FileManager.default.fileExists(atPath: processLauncher.arguments[0]))

        let missing = DownloadedUpdate(
            candidate: candidate,
            artifactURL: root.appendingPathComponent("missing.zip"),
            verifiedSHA256: digest
        )
        XCTAssertThrowsError(try launcher.launch(for: missing))
        XCTAssertEqual(processLauncher.launchCount, 1, "a missing verified ZIP must not start a handoff")
    }

    func testAutomaticUpdateChecksAreBoundedToOnePerDay() {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        XCTAssertTrue(UpdateSourcePolicy.shouldAutomaticallyCheck(lastCheck: nil, now: now))
        XCTAssertFalse(UpdateSourcePolicy.shouldAutomaticallyCheck(lastCheck: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(UpdateSourcePolicy.shouldAutomaticallyCheck(lastCheck: now.addingTimeInterval(-86_400), now: now))
    }

    func testUpdateServiceSelectsAndVerifiesReleaseWithoutNetwork() async throws {
        let releaseVersion = nextReleaseVersion
        let releaseTag = "v\(releaseVersion)"
        let artifactName = "\(ProductIdentity.name)-\(releaseTag)-macos-arm64.zip"
        let apiURL = ProductIdentity.releaseAPIURL
        let artifactURL = URL(string: "https://github.com/\(ProductIdentity.releaseRepository)/releases/download/\(releaseTag)/app.zip")!
        let checksumURL = URL(string: "https://github.com/\(ProductIdentity.releaseRepository)/releases/download/\(releaseTag)/app.sha256")!
        let artifact = Data("update-payload".utf8)
        let checksum = Data("faf613f495c32b8434726bd719da5f8901270370aa14f4259b1d3ec23f998fe1  \(artifactName)\n".utf8)
        let releaseJSON: [String: Any] = [
            "tag_name": releaseTag,
            "html_url": "https://github.com/\(ProductIdentity.releaseRepository)/releases/tag/\(releaseTag)",
            "draft": false,
            "prerelease": false,
            "assets": [
                ["name": artifactName, "browser_download_url": artifactURL.absoluteString],
                ["name": "\(artifactName).sha256", "browser_download_url": checksumURL.absoluteString]
            ]
        ]
        let transport = StubUpdateTransport(responses: [
            apiURL.absoluteString: try JSONSerialization.data(withJSONObject: releaseJSON),
            artifactURL.absoluteString: artifact,
            checksumURL.absoluteString: checksum
        ])
        let service = GitHubReleasesUpdateService(
            transport: transport,
            currentVersion: ProductIdentity.currentVersion,
            architecture: "arm64"
        )

        let result = await service.checkForUpdate()
        guard case .available(let candidate) = result else {
            XCTFail("the valid release should be available: \(result)")
            return
        }
        let downloaded = try await service.downloadAndVerify(candidate)
        defer { try? FileManager.default.removeItem(at: downloaded.artifactURL.deletingLastPathComponent()) }
        XCTAssertEqual(try Data(contentsOf: downloaded.artifactURL), artifact)
        XCTAssertEqual(downloaded.candidate.artifactName, artifactName)
    }

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

    func testObservedIdleSampleResetsNearThresholdActiveUse() {
        let start = referenceDate(1_000)
        var tracker = makeNearDueTracker(start: start)
        XCTAssertEqual(tracker.accumulatedActiveTime, 3_599)

        _ = tracker.tick(at: start.addingTimeInterval(3_600), userIsActive: false)
        let resumed = tracker.tick(
            at: start.addingTimeInterval(3_601),
            userIsActive: true
        )

        XCTAssertTrue(resumed.didResetAfterIdle)
        XCTAssertEqual(resumed.activeSeconds, 1)
        XCTAssertFalse(resumed.shouldOfferCheckIn)
    }

    func testDelayedPostSleepCallbackDoesNotCountTheSleepGap() {
        let start = referenceDate(2_000)
        var tracker = makeNearDueTracker(start: start)

        let resumed = tracker.tick(
            at: start.addingTimeInterval(4 * 60 * 60),
            userIsActive: true
        )

        XCTAssertTrue(resumed.didResetAfterIdle)
        XCTAssertEqual(resumed.activeSeconds, ActiveUseTracker.maximumTimerDelta)
        XCTAssertFalse(resumed.shouldOfferCheckIn)
    }

    func testContinuousActiveUseStillReachesTheCheckInInterval() {
        let start = referenceDate(3_000)
        var tracker = ActiveUseTracker(
            activeInterval: 5,
            idleThreshold: 60,
            startedAt: start
        )

        for second in 1...4 {
            XCTAssertFalse(
                tracker.tick(at: start.addingTimeInterval(TimeInterval(second)), userIsActive: true)
                    .shouldOfferCheckIn
            )
        }
        let due = tracker.tick(at: start.addingTimeInterval(5), userIsActive: true)

        XCTAssertEqual(due.activeSeconds, 5)
        XCTAssertTrue(due.shouldOfferCheckIn)
    }

    func testFreshRelaunchStartsWithNoActiveCredit() {
        var tracker = ActiveUseTracker(
            activeInterval: 3_600,
            idleThreshold: 60,
            startedAt: referenceDate(4_000)
        )

        let firstSample = tracker.tick(
            at: referenceDate(4_001),
            userIsActive: true
        )

        XCTAssertEqual(firstSample.activeSeconds, 1)
        XCTAssertFalse(firstSample.shouldOfferCheckIn)
    }

    func testBelowThresholdLongIdleRemainsMaskedWithoutAnOffer() {
        let start = referenceDate(5_000)
        var tracker = ActiveUseTracker(
            activeInterval: 5,
            idleThreshold: 60,
            startedAt: start
        )
        _ = tracker.tick(at: start.addingTimeInterval(1), userIsActive: true)
        _ = tracker.tick(at: start.addingTimeInterval(2), userIsActive: true)
        _ = tracker.tick(at: start.addingTimeInterval(63), userIsActive: false)

        let resumed = tracker.tick(at: start.addingTimeInterval(3_600), userIsActive: true)

        XCTAssertTrue(resumed.didResetAfterIdle)
        XCTAssertEqual(resumed.activeSeconds, 2)
        XCTAssertFalse(resumed.shouldOfferCheckIn)
    }

    @MainActor
    func testCheckInButtonsProvideStartLaterAndTomorrowResponses() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = referenceDate(6_000)
        var now = start
        let scheduler = ManualDelayedActionScheduler()
        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            nowProvider: { now },
            postponementScheduler: scheduler
        )
        store.continueWithBalancedDefaults()
        store.offerBreakNow()
        XCTAssertEqual(store.mode, .checkIn)

        store.startRoutine(at: start, activitySignal: activitySignal(0, 0))
        XCTAssertEqual(store.mode, .routine)
        XCTAssertEqual(store.stepIndex, 0)
        store.endRoutine()
        store.dismissCompletion()

        store.offerBreakNow()
        XCTAssertEqual(store.mode, .checkIn)
        store.postpone(minutes: 60)
        XCTAssertEqual(store.statusText, "I’ll check back in an hour.")
        scheduler.runPendingAction()
        XCTAssertEqual(store.mode, .idle)

        now = start.addingTimeInterval(3_600)
        store.tickForTesting(at: now, userIsActive: false)
        XCTAssertEqual(store.mode, .idle)
        store.tickForTesting(at: now, userIsActive: true)
        XCTAssertEqual(store.mode, .checkIn)

        store.postponeUntilTomorrow()
        XCTAssertEqual(store.statusText, "See you tomorrow.")
        scheduler.runPendingAction()
        XCTAssertEqual(store.mode, .idle)
    }

    func testRoutineActivityDetectorGraceAndResetToleranceAreDeterministic() {
        var detector = RoutineActivityDetector()
        detector.start(at: Date(timeIntervalSinceReferenceDate: 100), signal: activitySignal(8, 8))

        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 101),
                isPaused: false,
                signal: activitySignal(0.1, 9)
            ),
            .initialGracePeriod
        )
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 104.9),
                isPaused: false,
                signal: activitySignal(4, 12.9)
            ),
            .noNewActivity
        )
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 106),
                isPaused: false,
                signal: activitySignal(5.1, 14)
            ),
            .noNewActivity,
            "The grace period expiring must not by itself read as resumed work"
        )
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 106.5),
                isPaused: false,
                signal: activitySignal(4.7, 14.5)
            ),
            .noNewActivity,
            "An aggregate age wobble inside the reset tolerance is not activity"
        )
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 107),
                isPaused: false,
                signal: activitySignal(0, 15)
            ),
            .resumedWork
        )
    }

    func testRecoveryPointerSignalsDoNotChangeIdleTiming() {
        let click = LocalActivitySignal(
            keyboardIdle: 60,
            mouseMovementIdle: 60,
            mouseClickIdle: 0.2,
            scrollWheelIdle: 60
        )
        XCTAssertEqual(click.pointerIdle, 0.2)
        XCTAssertEqual(click.workActivityIdle, 60)

        let drag = LocalActivitySignal(
            keyboardIdle: 60,
            mouseMovementIdle: 60,
            mouseClickIdle: 60,
            scrollWheelIdle: 60,
            mouseDragIdle: 0.2
        )
        XCTAssertEqual(drag.pointerIdle, 0.2)
        XCTAssertEqual(drag.workActivityIdle, 60)

        let keyboard = LocalActivitySignal(
            keyboardIdle: 0.2,
            mouseMovementIdle: 60,
            mouseClickIdle: 60,
            scrollWheelIdle: 60
        )
        XCTAssertEqual(keyboard.workActivityIdle, 0.2)
    }

    func testSustainedTypingThroughTheGracePeriodStillQualifiesAfterIt() {
        var detector = RoutineActivityDetector()
        detector.start(at: Date(timeIntervalSinceReferenceDate: 200), signal: activitySignal(30, 0.1))

        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 201),
                isPaused: false,
                signal: activitySignal(0.2, 1.1)
            ),
            .initialGracePeriod
        )
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 202),
                isPaused: false,
                signal: activitySignal(0.25, 2.1)
            ),
            .initialGracePeriod
        )
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 205),
                isPaused: false,
                signal: activitySignal(0.2, 5.1)
            ),
            .resumedWork,
            "Typing that never stopped must not be permanently consumed by a sample ignored during grace"
        )
    }

    func testSustainedTypingIsStillEligibleAfterPauseAndAfterCompanionControls() {
        var detector = RoutineActivityDetector()
        detector.start(at: Date(timeIntervalSinceReferenceDate: 300), signal: activitySignal(30, 30))

        detector.noteCompanionInteraction(at: Date(timeIntervalSinceReferenceDate: 306))
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 307),
                isPaused: false,
                signal: activitySignal(0.2, 37)
            ),
            .companionInteraction
        )
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 308),
                isPaused: true,
                signal: activitySignal(0.2, 38)
            ),
            .paused
        )
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 310),
                isPaused: false,
                signal: activitySignal(0.2, 40)
            ),
            .resumedWork,
            "Sustained typing stays eligible once pause and companion protection have ended"
        )
    }

    func testBriefPointerReachTowardACompanionControlDoesNotCancelTheRoutine() {
        var detector = RoutineActivityDetector()
        detector.start(at: referenceDate(100), signal: activitySignal(60, 25))

        XCTAssertEqual(
            detector.decision(at: referenceDate(129), isPaused: false, signal: activitySignal(89, 54)),
            .noNewActivity
        )
        XCTAssertEqual(
            detector.decision(at: referenceDate(130.3), isPaused: false, signal: activitySignal(90.3, 0.3)),
            .noNewActivity,
            "A single poll of pointer movement is a reach, not resumed work"
        )

        detector.noteCompanionInteraction(at: referenceDate(130.5))
        XCTAssertEqual(
            detector.decision(at: referenceDate(131.3), isPaused: false, signal: activitySignal(91.3, 0.5)),
            .companionInteraction,
            "The control the user was reaching for must open onto a live routine"
        )
    }

    func testSinglePointerNudgeAtTheGraceBoundaryDoesNotCancelTheRoutine() {
        var detector = RoutineActivityDetector()
        detector.start(at: referenceDate(100), signal: activitySignal(60, 60))

        XCTAssertEqual(
            detector.decision(at: referenceDate(104.2), isPaused: false, signal: activitySignal(64.2, 64.2)),
            .noNewActivity
        )
        XCTAssertEqual(
            detector.decision(at: referenceDate(105.2), isPaused: false, signal: activitySignal(65.2, 0.9)),
            .noNewActivity,
            "Nudging the pointer aside just after Start must not cancel the routine"
        )
        XCTAssertEqual(
            detector.decision(at: referenceDate(106.2), isPaused: false, signal: activitySignal(66.2, 1.9)),
            .noNewActivity
        )
    }

    func testPointerEvidenceGatheredWhileProtectedDoesNotCancelAfterResume() {
        var detector = RoutineActivityDetector()
        detector.start(at: referenceDate(0), signal: activitySignal(60, 60))
        XCTAssertEqual(
            detector.decision(at: referenceDate(10), isPaused: true, signal: activitySignal(70, 70)),
            .noNewActivity
        )

        detector.noteCompanionInteraction(at: referenceDate(40))
        XCTAssertEqual(
            detector.decision(at: referenceDate(41), isPaused: false, signal: activitySignal(101, 0.4)),
            .noNewActivity
        )
        XCTAssertEqual(
            detector.decision(at: referenceDate(42), isPaused: false, signal: activitySignal(102, 0.3)),
            .noNewActivity
        )
        XCTAssertEqual(
            detector.decision(at: referenceDate(43), isPaused: false, signal: activitySignal(103, 0.7)),
            .noNewActivity,
            "Withdrawing the pointer from a control must not cancel the routine the user just resumed"
        )
        XCTAssertEqual(
            detector.decision(at: referenceDate(44), isPaused: false, signal: activitySignal(104, 1.7)),
            .noNewActivity
        )
    }

    func testPointerEvidenceGatheredDuringGraceDoesNotCancelAtTheBoundary() {
        var detector = RoutineActivityDetector()
        detector.start(at: referenceDate(0), signal: activitySignal(60, 60))

        XCTAssertEqual(
            detector.decision(at: referenceDate(1), isPaused: false, signal: activitySignal(61, 0.4)),
            .noNewActivity
        )
        XCTAssertEqual(
            detector.decision(at: referenceDate(2), isPaused: false, signal: activitySignal(62, 0.3)),
            .noNewActivity
        )
        XCTAssertEqual(
            detector.decision(at: referenceDate(5.2), isPaused: false, signal: activitySignal(65.2, 0.6)),
            .noNewActivity,
            "Settling in during the grace period must not cancel the routine at the grace boundary"
        )
        XCTAssertEqual(
            detector.decision(at: referenceDate(6.2), isPaused: false, signal: activitySignal(66.2, 1.6)),
            .noNewActivity
        )
    }

    func testContinuousPointerMovementQualifiesOnTheSecondConsecutivePoll() {
        var detector = RoutineActivityDetector()
        detector.start(at: referenceDate(100), signal: activitySignal(60, 60))

        XCTAssertEqual(
            detector.decision(at: referenceDate(110), isPaused: false, signal: activitySignal(70, 0.3)),
            .noNewActivity
        )
        XCTAssertEqual(
            detector.decision(at: referenceDate(111), isPaused: false, signal: activitySignal(71, 0.4)),
            .resumedWork,
            "Pointer movement that spans consecutive polls is resumed work"
        )
    }

    func testMouseClicksAndScrollsQualifyWithoutPointerMovement() {
        var clickDetector = RoutineActivityDetector()
        clickDetector.start(
            at: referenceDate(100),
            signal: activitySignal(60, 60, mouseClickIdle: 60, scrollWheelIdle: 60)
        )
        XCTAssertEqual(
            clickDetector.decision(
                at: referenceDate(110),
                isPaused: false,
                signal: activitySignal(70, 70, mouseClickIdle: 0.3, scrollWheelIdle: 70)
            ),
            .noNewActivity
        )
        XCTAssertEqual(
            clickDetector.decision(
                at: referenceDate(111),
                isPaused: false,
                signal: activitySignal(71, 71, mouseClickIdle: 0.4, scrollWheelIdle: 71)
            ),
            .resumedWork,
            "A click without pointer movement is resumed work"
        )

        var scrollDetector = RoutineActivityDetector()
        scrollDetector.start(
            at: referenceDate(200),
            signal: activitySignal(60, 60, mouseClickIdle: 60, scrollWheelIdle: 60)
        )
        XCTAssertEqual(
            scrollDetector.decision(
                at: referenceDate(210),
                isPaused: false,
                signal: activitySignal(70, 70, mouseClickIdle: 70, scrollWheelIdle: 0.3)
            ),
            .noNewActivity
        )
        XCTAssertEqual(
            scrollDetector.decision(
                at: referenceDate(211),
                isPaused: false,
                signal: activitySignal(71, 71, mouseClickIdle: 71, scrollWheelIdle: 0.4)
            ),
            .resumedWork,
            "Scrolling without pointer movement is resumed work"
        )
    }

    func testCompanionProtectionCannotBeRenewedWithoutBound() {
        var detector = RoutineActivityDetector()
        detector.start(at: referenceDate(200), signal: activitySignal(60, 60))

        var poll = 206.0
        var uncancelledPolls = 0
        var decision = RoutineActivityDecision.noNewActivity
        while poll < 300 {
            detector.noteCompanionInteraction(at: referenceDate(poll))
            decision = detector.decision(
                at: referenceDate(poll),
                isPaused: false,
                signal: activitySignal(60 + poll - 200, 0.2)
            )
            if decision == .resumedWork { break }
            uncancelledPolls += 1
            poll += 1
        }

        XCTAssertEqual(decision, .resumedWork, "Companion protection must not be renewable without bound")
        XCTAssertGreaterThan(
            uncancelledPolls,
            10,
            "The protection budget must still cover a generous amount of deliberate control use"
        )
        XCTAssertLessThanOrEqual(
            detector.companionProtectionUsed,
            RoutineActivityPolicy.companionProtectionBudget
        )
    }

    func testRoutineActivityDetectorProtectsCompanionControlsAndPause() {
        var detector = RoutineActivityDetector()
        detector.start(at: Date(timeIntervalSinceReferenceDate: 200), signal: activitySignal(8, 8))
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 206),
                isPaused: false,
                signal: activitySignal(14, 14)
            ),
            .noNewActivity
        )

        detector.noteCompanionInteraction(at: Date(timeIntervalSinceReferenceDate: 206))
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 207),
                isPaused: false,
                signal: activitySignal(0, 15)
            ),
            .companionInteraction
        )
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 210),
                isPaused: false,
                signal: activitySignal(3, 18)
            ),
            .noNewActivity,
            "Companion protection expiring must not by itself read as resumed work"
        )

        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 211),
                isPaused: false,
                signal: activitySignal(0, 19)
            ),
            .resumedWork
        )

        detector.start(at: Date(timeIntervalSinceReferenceDate: 300), signal: activitySignal(8, 8))
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 306),
                isPaused: false,
                signal: activitySignal(14, 14)
            ),
            .noNewActivity
        )
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 307),
                isPaused: true,
                signal: activitySignal(0, 15)
            ),
            .paused
        )
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 308),
                isPaused: true,
                signal: activitySignal(1, 16)
            ),
            .paused,
            "Activity that continues while paused stays protected"
        )
        XCTAssertEqual(
            detector.decision(
                at: Date(timeIntervalSinceReferenceDate: 309),
                isPaused: false,
                signal: activitySignal(0, 17)
            ),
            .resumedWork,
            "Activity after Resume is eligible even when activity during Pause was ignored"
        )
    }

    @MainActor
    func testResumedActivityReturnsToFreshCheckInWithoutCompletionCredit() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults
        )
        store.continueWithBalancedDefaults()
        defaults.set(["shoulder-rolls"], forKey: "session.recentCompletedMoveIDs")
        store.startRoutine(at: Date(timeIntervalSinceReferenceDate: 400), activitySignal: activitySignal(8, 8))
        let pendingBeforeRecovery = defaults.stringArray(forKey: "session.pendingMoveIDs")

        XCTAssertEqual(
            store.evaluateRoutineActivity(
                signal: activitySignal(14, 14),
                at: Date(timeIntervalSinceReferenceDate: 406)
            ),
            .noNewActivity
        )
        XCTAssertEqual(
            store.evaluateRoutineActivity(
                signal: activitySignal(0, 15),
                at: Date(timeIntervalSinceReferenceDate: 407)
            ),
            .resumedWork
        )

        XCTAssertEqual(store.mode, .checkIn)
        XCTAssertNotNil(store.activityRecoveryExplanation)
        XCTAssertEqual(defaults.stringArray(forKey: "session.recentCompletedMoveIDs"), ["shoulder-rolls"])
        XCTAssertNotEqual(defaults.stringArray(forKey: "session.pendingMoveIDs"), pendingBeforeRecovery)

        store.startRoutine(at: Date(timeIntervalSinceReferenceDate: 408), activitySignal: activitySignal(0, 0))
        XCTAssertEqual(store.mode, .routine)
        XCTAssertEqual(store.stepIndex, 0)
        XCTAssertEqual(store.elapsedInStep, 0)
        XCTAssertFalse(store.isPaused)
        XCTAssertEqual(defaults.stringArray(forKey: "session.recentCompletedMoveIDs"), ["shoulder-rolls"])
        store.endRoutine()
    }

    @MainActor
    func testCompanionSurfaceInteractionKeepsTheRoutineRunningUntilProtectionExpires() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults
        )
        store.continueWithBalancedDefaults()
        store.startRoutine(at: referenceDate(0), activitySignal: activitySignal(30, 30))
        store.noteCompanionInteraction(at: referenceDate(6))

        XCTAssertEqual(
            store.evaluateRoutineActivity(
                signal: activitySignal(0.2, 0.2),
                at: referenceDate(7)
            ),
            .companionInteraction
        )
        XCTAssertEqual(store.mode, .routine)

        XCTAssertEqual(
            store.evaluateRoutineActivity(
                signal: activitySignal(0.2, 0.2),
                at: referenceDate(10)
            ),
            .resumedWork
        )
        XCTAssertEqual(store.mode, .checkIn)

        store.startRoutine(at: referenceDate(11), activitySignal: activitySignal(0, 0))
        store.endRoutine()
    }

    @MainActor
    func testNextRestartsActivityDetectionForTheNewRoutine() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults
        )
        store.continueWithBalancedDefaults()
        store.startRoutine(at: referenceDate(0), activitySignal: activitySignal(60, 60))
        // Spend the first routine's whole companion-protection budget.
        for poll in stride(from: 1.0, through: 30.0, by: 1.0) {
            store.noteCompanionInteraction(at: referenceDate(poll))
        }

        let previousRoutine = store.routine
        store.nextRoutine(at: referenceDate(30), activitySignal: activitySignal(90, 0.2))
        XCTAssertNotEqual(store.routine, previousRoutine)

        // Settling into the new routine is covered by its own grace period.
        XCTAssertEqual(
            store.evaluateRoutineActivity(signal: activitySignal(91, 0.3), at: referenceDate(31)),
            .noNewActivity
        )
        XCTAssertEqual(
            store.evaluateRoutineActivity(signal: activitySignal(0.2, 0.4), at: referenceDate(32)),
            .initialGracePeriod
        )
        XCTAssertEqual(store.mode, .routine)

        // The new routine also gets its own protection budget.
        store.noteCompanionInteraction(at: referenceDate(36))
        XCTAssertEqual(
            store.evaluateRoutineActivity(signal: activitySignal(96, 0.3), at: referenceDate(37)),
            .noNewActivity
        )
        XCTAssertEqual(
            store.evaluateRoutineActivity(signal: activitySignal(0.2, 0.4), at: referenceDate(38)),
            .companionInteraction
        )
        XCTAssertEqual(store.mode, .routine)
        XCTAssertEqual(store.stepIndex, 0)

        XCTAssertEqual(
            store.evaluateRoutineActivity(signal: activitySignal(100, 0.3), at: referenceDate(41)),
            .noNewActivity
        )
        XCTAssertEqual(
            store.evaluateRoutineActivity(signal: activitySignal(101, 0.4), at: referenceDate(42)),
            .resumedWork
        )
        XCTAssertEqual(store.mode, .checkIn)

        store.startRoutine(at: referenceDate(43), activitySignal: activitySignal(0, 0))
        store.endRoutine()
    }

    func testFirstPointerPollInsideGraceIsNotCarriedPastTheGraceBoundary() {
        var detector = RoutineActivityDetector()
        detector.start(at: referenceDate(0), signal: activitySignal(60, 60))

        XCTAssertEqual(
            detector.decision(at: referenceDate(4.5), isPaused: false, signal: activitySignal(64.5, 0.3)),
            .noNewActivity
        )
        XCTAssertEqual(
            detector.decision(at: referenceDate(5.5), isPaused: false, signal: activitySignal(65.5, 0.1)),
            .noNewActivity,
            "One mouse motion spanning the grace boundary must not cancel a routine just started"
        )
    }

    func testFirstPointerPollInsideCompanionProtectionIsNotCarriedPastIt() {
        var detector = RoutineActivityDetector()
        detector.start(at: referenceDate(0), signal: activitySignal(60, 60))
        detector.noteCompanionInteraction(at: referenceDate(40))

        XCTAssertEqual(
            detector.decision(at: referenceDate(41), isPaused: false, signal: activitySignal(101, 41)),
            .noNewActivity
        )
        XCTAssertEqual(
            detector.decision(at: referenceDate(42), isPaused: false, signal: activitySignal(102, 0.3)),
            .noNewActivity
        )
        XCTAssertEqual(
            detector.decision(at: referenceDate(43), isPaused: false, signal: activitySignal(103, 0.7)),
            .noNewActivity,
            "Pointer evidence seen while protected must not qualify on the first unprotected poll"
        )
    }

    func testKeyboardInputWhileTheCompanionHasKeyFocusIsCompanionInteraction() {
        var detector = RoutineActivityDetector()
        detector.start(at: referenceDate(0), signal: activitySignal(60, 60))

        XCTAssertEqual(
            detector.decision(
                at: referenceDate(10),
                isPaused: false,
                companionHasKeyboardFocus: true,
                signal: activitySignal(0.2, 70)
            ),
            .companionInteraction,
            "Keyboard navigation aimed at the companion's own panel must not cancel the routine"
        )
        XCTAssertEqual(
            detector.decision(
                at: referenceDate(11),
                isPaused: false,
                companionHasKeyboardFocus: true,
                signal: activitySignal(0.2, 71)
            ),
            .companionInteraction
        )

        var poll = 12.0
        var decision = RoutineActivityDecision.companionInteraction
        while poll < 100 {
            decision = detector.decision(
                at: referenceDate(poll),
                isPaused: false,
                companionHasKeyboardFocus: true,
                signal: activitySignal(0.2, 60 + poll)
            )
            if decision == .resumedWork { break }
            poll += 1
        }
        XCTAssertEqual(decision, .resumedWork, "Keyboard focus protection must share the bounded per-routine budget")
        XCTAssertLessThanOrEqual(
            detector.companionProtectionUsed,
            RoutineActivityPolicy.companionProtectionBudget
        )
    }

    @MainActor
    func testTypingIntoTheCompanionPanelDoesNotCancelTheRoutine() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults
        )
        store.continueWithBalancedDefaults()
        store.companionHasKeyboardFocus = { true }
        store.startRoutine(at: referenceDate(0), activitySignal: activitySignal(30, 30))

        XCTAssertEqual(
            store.evaluateRoutineActivity(signal: activitySignal(0.2, 40), at: referenceDate(7)),
            .companionInteraction
        )
        XCTAssertEqual(store.mode, .routine)

        store.companionHasKeyboardFocus = { false }
        XCTAssertEqual(
            store.evaluateRoutineActivity(signal: activitySignal(0.2, 44), at: referenceDate(11)),
            .resumedWork,
            "Typing once the companion no longer holds key focus is resumed work again"
        )
        XCTAssertEqual(store.mode, .checkIn)

        store.startRoutine(at: referenceDate(12), activitySignal: activitySignal(0, 0))
        store.endRoutine()
    }

    @MainActor
    func testActivityRecoveryCheckInIsSilentWhileANormalCheckInSpeaks() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let recoverySpeaker = RecordingSpeaker()
        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            speaker: recoverySpeaker
        )
        store.continueWithBalancedDefaults()
        store.startRoutine(at: referenceDate(0), activitySignal: activitySignal(30, 30))
        XCTAssertEqual(
            store.evaluateRoutineActivity(signal: activitySignal(0.2, 40), at: referenceDate(7)),
            .resumedWork
        )
        XCTAssertEqual(store.mode, .checkIn)
        XCTAssertNotNil(store.activityRecoveryExplanation)
        XCTAssertFalse(
            recoverySpeaker.spoken.contains(CompanionStore.checkInPrompt),
            "Someone who just went back to work must not be prompted out loud"
        )
        store.startRoutine(at: referenceDate(8), activitySignal: activitySignal(0, 0))
        store.endRoutine()

        let promptSuiteName = "\(suiteName).prompt"
        let promptDefaults = UserDefaults(suiteName: promptSuiteName)!
        promptDefaults.removePersistentDomain(forName: promptSuiteName)
        defer { promptDefaults.removePersistentDomain(forName: promptSuiteName) }

        let promptSpeaker = RecordingSpeaker()
        let promptStore = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: promptDefaults,
            speaker: promptSpeaker
        )
        promptStore.continueWithBalancedDefaults()
        promptStore.offerBreakNow()
        XCTAssertEqual(promptStore.mode, .checkIn)
        XCTAssertNil(promptStore.activityRecoveryExplanation)
        XCTAssertTrue(promptSpeaker.spoken.contains(CompanionStore.checkInPrompt))
        promptStore.startRoutine(at: referenceDate(1), activitySignal: activitySignal(0, 0))
        promptStore.endRoutine()
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
            let lateral = (text.contains("right") && text.contains("left"))
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

        let scarceLibrary = (1...2).map { makeMove("neck-\($0)", [.neckShoulders], bodyAreas: [.neck]) }
            + (1...12).map { makeMove("other-\($0)", [.breathRelaxation]) }
        XCTAssertLessThan(
            scarceLibrary.filter { $0.bodyAreas.contains(.neck) }.count,
            SessionComposer.sessionMoveCount
        )

        let store = SessionSelectionStore(defaults: defaults)
        let current = store.suggestion(from: scarceLibrary, selectedAreas: [.neck])!
        let next = store.nextSession(after: current, from: scarceLibrary, selectedAreas: [.neck])!

        XCTAssertTrue(Set(current.moveIDs).isDisjoint(with: next.moveIDs))
        XCTAssertEqual(Set(next.moveIDs).count, SessionComposer.sessionMoveCount)
        XCTAssertEqual(next.duration, 120)
        XCTAssertEqual(next.title, "Standing reset")
    }

    func testFollowUpSessionOnlyClaimsAnAreaItStillCarriesMovesFor() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let neckIDs = Set(MoveLibrary.all.filter { $0.bodyAreas.contains(.neck) }.map(\.id))
        let store = SessionSelectionStore(defaults: defaults)
        let current = store.suggestion(from: MoveLibrary.all, selectedAreas: [.neck])!
        XCTAssertEqual(current.title, "Neck standing reset")

        var session = current
        for round in 1...4 {
            session = store.nextSession(after: session, from: MoveLibrary.all, selectedAreas: [.neck])!
            let carried = Set(session.moveIDs).intersection(neckIDs)
            XCTAssertGreaterThanOrEqual(carried.count, 3, "round \(round)")
            XCTAssertEqual(session.title.contains("Neck"), !carried.isEmpty, "round \(round)")
            XCTAssertEqual(
                session.invitation.lowercased().contains("neck"),
                !carried.isEmpty,
                "round \(round)"
            )
            XCTAssertTrue(session.invitation.lowercased().contains("stand"))
            XCTAssertEqual(Set(session.moveIDs).count, SessionComposer.sessionMoveCount)
            XCTAssertEqual(session.duration, 120)
        }
    }

    func testRoutineDropsSelectedAreasThatTheComposedMovesDoNotCover() {
        let library = (1...6).map { makeMove("hands-\($0)", [.handsWristsForearms], bodyAreas: [.handsWrists]) }
        let routine = SessionComposer.compose(
            from: library,
            recentShownMoveIDs: [],
            recentCompletedMoveIDs: [],
            selectedAreas: [.neck, .handsWrists]
        )!

        XCTAssertEqual(routine.title, "Hands + wrists standing reset")
        XCTAssertTrue(routine.invitation.lowercased().contains("hands-and-wrists"))
        XCTAssertFalse(routine.invitation.lowercased().contains("neck"))
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

    private var nextReleaseVersion: SemanticVersion {
        let currentVersion = ProductIdentity.currentVersion
        return SemanticVersion(
            major: currentVersion.major,
            minor: currentVersion.minor,
            patch: currentVersion.patch + 1
        )
    }

    private func activitySignal(
        _ keyboardIdle: TimeInterval,
        _ pointerIdle: TimeInterval,
        mouseClickIdle: TimeInterval = .infinity,
        scrollWheelIdle: TimeInterval = .infinity
    ) -> LocalActivitySignal {
        LocalActivitySignal(
            keyboardIdle: keyboardIdle,
            mouseMovementIdle: pointerIdle,
            mouseClickIdle: mouseClickIdle,
            scrollWheelIdle: scrollWheelIdle
        )
    }

    private func referenceDate(_ secondsSinceReference: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: secondsSinceReference)
    }

    private func makeNearDueTracker(start: Date) -> ActiveUseTracker {
        var tracker = ActiveUseTracker(
            activeInterval: 3_600,
            idleThreshold: 60,
            startedAt: start
        )
        for second in 1...3_599 {
            _ = tracker.tick(
                at: start.addingTimeInterval(TimeInterval(second)),
                userIsActive: true
            )
        }
        return tracker
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

private final class RecordingSpeaker: RoutineSpeaking {
    private(set) var spoken: [String] = []

    func speak(_ text: String) {
        spoken.append(text)
    }

    func stop() {}
}

private final class RecordingUpdateHandoffLauncher: UpdateHandoffLaunching {
    private(set) var downloadedUpdates: [DownloadedUpdate] = []

    func launch(for downloadedUpdate: DownloadedUpdate) throws {
        downloadedUpdates.append(downloadedUpdate)
    }
}

private final class RecordingHandoffProcessLauncher: UpdateHandoffProcessLaunching {
    private(set) var executableURL: URL?
    private(set) var arguments: [String] = []
    private(set) var launchCount = 0

    func launch(executableURL: URL, arguments: [String]) throws {
        self.executableURL = executableURL
        self.arguments = arguments
        launchCount += 1
    }
}

private final class StubUpdateTransport: UpdateTransport {
    let responses: [String: Data]

    init(responses: [String: Data]) {
        self.responses = responses
    }

    func data(for request: URLRequest, maxBytes: Int) async throws -> Data {
        guard let url = request.url, let response = responses[url.absoluteString] else {
            throw UpdateFailure.unexpectedResponse
        }
        guard response.count <= maxBytes else {
            throw UpdateFailure.responseTooLarge
        }
        return response
    }
}
