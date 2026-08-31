import AppKit
import CryptoKit
import SwiftUI
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
        XCTAssertEqual(currentVersion.description, "0.1.6")
        XCTAssertEqual(ProductIdentity.buildNumber, "7")
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

    func testUpdateDialogModelKeepsTheNormalFlowConciseAndActionable() {
        let version = nextReleaseVersion
        let available = UpdateDialogModel(phase: .available(version))
        let copy = "\(available.title) \(available.message) \(available.primaryButtonTitle ?? "") \(available.secondaryButtonTitle ?? "")"
            .lowercased()

        XCTAssertEqual(available.primaryButtonTitle, "Install and Relaunch")
        XCTAssertEqual(available.secondaryButtonTitle, "Later")
        for implementationDetail in ["github", "zip", "sha", "checksum", "finder", "path"] {
            XCTAssertFalse(copy.contains(implementationDetail), implementationDetail)
        }

        let preparing = UpdateDialogModel(phase: .downloading)
        XCTAssertTrue(preparing.showsProgress)
        XCTAssertNil(preparing.primaryButtonTitle)
        XCTAssertEqual(preparing.secondaryButtonTitle, "Cancel")
        XCTAssertEqual(
            UpdateDialogModel(phase: .failed(.install)).message,
            "Your current version is unchanged. Try again."
        )
        XCTAssertEqual(UpdateDialogModel(phase: .current).primaryButtonTitle, "Done")
    }

    func testUpdateFailureDiagnosticsUseTheExistingPrivacySafeLogPath() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("2m2better-update-log-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        UpdateDiagnostics.record(.checksumMismatch, phase: "download", homeDirectory: home)

        let log = try String(contentsOf: UpdateDiagnostics.logURL(homeDirectory: home), encoding: .utf8)
        XCTAssertTrue(log.contains("2m2better update download failed."))
        XCTAssertTrue(log.contains("SHA-256 checksum"))
        XCTAssertFalse(log.lowercased().contains("keyboard"))
        XCTAssertFalse(log.lowercased().contains("pointer"))
    }

    @MainActor
    func testUpdateFlowUsesOneConsentThenVerifiesAndHandsOffWithoutAnotherDialog() async throws {
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
        let flow = UpdateFlowCoordinator(controller: controller)
        var phases: [UpdateDialogPhase] = []
        let checkExpectation = expectation(description: "manual update check")
        flow.onStateChange = { state in
            if let phase = flow.dialogModel?.phase {
                phases.append(phase)
            }
            if case .available = state {
                checkExpectation.fulfill()
            }
        }
        flow.checkManually(now: Date(timeIntervalSinceReferenceDate: 100_000))
        await fulfillment(of: [checkExpectation], timeout: 1)
        XCTAssertEqual(flow.dialogModel?.phase, .available(releaseVersion))

        let installExpectation = expectation(description: "update handoff started")
        flow.onStateChange = { state in
            if let phase = flow.dialogModel?.phase {
                phases.append(phase)
            }
            if case .installing = state {
                installExpectation.fulfill()
            }
        }
        flow.installAvailableUpdate()
        await fulfillment(of: [installExpectation], timeout: 1)

        XCTAssertEqual(flow.state, .installing(UpdateCandidate(
            version: releaseVersion,
            releaseURL: URL(string: "https://github.com/\(ProductIdentity.releaseRepository)/releases/tag/\(releaseTag)")!,
            artifactName: artifactName,
            artifactURL: artifactURL,
            checksumName: "\(artifactName).sha256",
            checksumURL: checksumURL
        )))
        XCTAssertEqual(handoffLauncher.downloadedUpdates.count, 1)
        XCTAssertTrue(
            phases.contains { phase in
                if case .downloaded = phase { return true }
                return false
            },
            "verification should pass through the downloaded controller state"
        )
        XCTAssertNil(flow.dialogModel?.primaryButtonTitle, "installation must not ask for a second confirmation")
        XCTAssertNil(flow.dialogModel?.secondaryButtonTitle)
        XCTAssertEqual(flow.dialogModel?.phase, .installing)
    }

    @MainActor
    func testAutomaticUpdateAvailabilityOpensTheSameConcisePrompt() async throws {
        let fixture = try makeUpdateFixture()
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = UpdateController(
            service: fixture,
            defaults: defaults,
            handoffLauncher: RecordingUpdateHandoffLauncher()
        )
        let flow = UpdateFlowCoordinator(controller: controller)
        let expectation = expectation(description: "automatic update availability")
        flow.onStateChange = { (state: UpdateFlowCoordinator.State) in
            if case .available = state { expectation.fulfill() }
        }

        flow.checkAutomatically(now: Date(timeIntervalSinceReferenceDate: 200_000))
        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertTrue(flow.shouldPresentDialog)
        XCTAssertEqual(flow.dialogModel?.primaryButtonTitle, "Install and Relaunch")
        XCTAssertEqual(flow.dialogModel?.secondaryButtonTitle, "Later")
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

    @MainActor
    func testPendingOfferWarmColorSurvivesCollapseToTheOrb() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "5"],
            defaults: defaults,
            speaker: RecordingSpeaker()
        )
        store.continueWithBalancedDefaults()
        store.offerBreakNow()
        XCTAssertEqual(store.mode, .checkIn)

        // showCheckIn resets progress to zero; pending state, not old progress,
        // must make both the full offer and its collapsed orb warm.
        let expandedColor = BreakProgress.color(
            at: store.checkInProgress,
            pendingOffer: true
        )
        store.collapseCheckIn()
        XCTAssertTrue(store.isCheckInCollapsed)
        XCTAssertEqual(store.diagnosticSnapshot().pendingOfferPresentation, .collapsedOrb)
        let collapsedColor = BreakProgress.color(
            at: store.checkInProgress,
            pendingOffer: true
        )

        XCTAssertEqual(collapsedColor, expandedColor)
        XCTAssertNotEqual(collapsedColor, BreakProgress.color(at: store.checkInProgress))
        XCTAssertLessThan(collapsedColor.green, 0.68)
        store.restoreCheckIn()
        XCTAssertFalse(store.isCheckInCollapsed)
    }

    @MainActor
    func testInactiveCollapsedPendingOfferStillRepeatsEveryFiveMinutesWithTheSameDecision() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = referenceDate(7_000)
        var now = start
        let speaker = RecordingSpeaker()
        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            speaker: speaker,
            nowProvider: { now }
        )
        store.continueWithBalancedDefaults()
        store.offerBreakNow()
        // Inactivity does not clear an already-active pending decision; its existing
        // five-minute reminder cadence remains unchanged.
        let offeredRoutine = store.routine
        let progressAfterOffer = store.checkInProgress
        let remainingAfterOffer = store.nextCheckInRemainingSeconds
        XCTAssertEqual(speaker.spoken, [CompanionStore.checkInPrompt])

        now = start.addingTimeInterval(60)
        store.collapseCheckIn()
        store.tickForTesting(
            at: now.addingTimeInterval(CompanionStore.pendingOfferReminderInterval - 1),
            userIsActive: false
        )
        XCTAssertTrue(store.isCheckInCollapsed, "the collapsed orb stays collapsed until its five-minute reminder")
        XCTAssertEqual(store.routine, offeredRoutine)

        store.tickForTesting(
            at: now.addingTimeInterval(CompanionStore.pendingOfferReminderInterval),
            userIsActive: false
        )
        XCTAssertEqual(store.mode, .checkIn)
        XCTAssertFalse(store.isCheckInCollapsed, "the first reminder must restore the existing pause choices")
        XCTAssertEqual(store.routine, offeredRoutine)
        XCTAssertEqual(store.checkInProgress, progressAfterOffer)
        XCTAssertEqual(store.nextCheckInRemainingSeconds, remainingAfterOffer)
        XCTAssertEqual(speaker.spoken, [CompanionStore.checkInPrompt, CompanionStore.checkInPrompt])

        now = now.addingTimeInterval(CompanionStore.pendingOfferReminderInterval)
        store.collapseCheckIn()
        store.tickForTesting(
            at: now.addingTimeInterval(CompanionStore.pendingOfferReminderInterval),
            userIsActive: false
        )
        XCTAssertEqual(store.mode, .checkIn)
        XCTAssertFalse(store.isCheckInCollapsed, "a second collapse must schedule another five-minute reminder")
        XCTAssertEqual(store.routine, offeredRoutine)
        XCTAssertEqual(speaker.spoken.count, 3)
    }

    @MainActor
    func testVisiblePendingOfferReannouncesWithoutDuplicatingItsState() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = referenceDate(7_500)
        let speaker = RecordingSpeaker()
        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            speaker: speaker,
            nowProvider: { start }
        )
        store.continueWithBalancedDefaults()
        var resizeEvents: [CompanionStore.Mode] = []
        store.onSizeChange = { resizeEvents.append($0) }
        store.offerBreakNow()
        let offeredRoutine = store.routine
        let shownIDs = defaults.stringArray(forKey: "session.recentShownMoveIDs")

        store.tickForTesting(
            at: start.addingTimeInterval(CompanionStore.pendingOfferReminderInterval),
            userIsActive: false
        )

        XCTAssertEqual(store.mode, .checkIn)
        XCTAssertFalse(store.isCheckInCollapsed)
        XCTAssertEqual(store.routine, offeredRoutine)
        XCTAssertEqual(defaults.stringArray(forKey: "session.recentShownMoveIDs"), shownIDs)
        XCTAssertEqual(resizeEvents, [.checkIn], "a visible reminder must not create a second presentation")
        XCTAssertEqual(speaker.spoken.count, 2, "a visible reminder should reannounce the existing prompt once")

        store.tickForTesting(
            at: start.addingTimeInterval(CompanionStore.pendingOfferReminderInterval + 1),
            userIsActive: false
        )
        XCTAssertEqual(speaker.spoken.count, 2, "one reminder deadline must not fire in a tight loop")
    }

    @MainActor
    func testExplicitStartLaterAndTomorrowStopPendingOfferReminders() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = referenceDate(8_000)
        var now = start
        let scheduler = ManualDelayedActionScheduler()
        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            activitySignalProvider: {
                LocalActivitySignal(keyboardIdle: 10_000, pointerIdle: 10_000)
            },
            speaker: RecordingSpeaker(),
            nowProvider: { now },
            postponementScheduler: scheduler
        )
        store.continueWithBalancedDefaults()

        store.offerBreakNow()
        store.collapseCheckIn()
        store.startRoutine(at: now, activitySignal: activitySignal(10_000, 10_000))
        store.tickForTesting(
            at: start.addingTimeInterval(CompanionStore.pendingOfferReminderInterval),
            userIsActive: false
        )
        XCTAssertEqual(store.mode, .routine, "Start must stop the pending reminder cadence")
        store.endRoutine()
        store.dismissCompletion()

        now = start.addingTimeInterval(1_000)
        store.offerBreakNow()
        store.collapseCheckIn()
        store.postpone(minutes: 60)
        store.tickForTesting(at: now.addingTimeInterval(CompanionStore.pendingOfferReminderInterval), userIsActive: false)
        XCTAssertEqual(store.mode, .checkIn, "Later's confirmation should remain on the existing path")
        scheduler.runPendingAction()
        XCTAssertEqual(store.mode, .idle)
        store.tickForTesting(at: now.addingTimeInterval(CompanionStore.pendingOfferReminderInterval * 2), userIsActive: false)
        XCTAssertEqual(store.mode, .idle, "Later must stop repeat reminders after returning to the orb")

        now = start.addingTimeInterval(2_000)
        store.offerBreakNow()
        store.collapseCheckIn()
        store.postponeUntilTomorrow()
        store.tickForTesting(at: now.addingTimeInterval(CompanionStore.pendingOfferReminderInterval), userIsActive: false)
        XCTAssertEqual(store.mode, .checkIn, "Tomorrow's confirmation should remain on the existing path")
        scheduler.runPendingAction()
        XCTAssertEqual(store.mode, .idle)
        store.tickForTesting(at: now.addingTimeInterval(CompanionStore.pendingOfferReminderInterval * 2), userIsActive: false)
        XCTAssertEqual(store.mode, .idle, "Tomorrow must stop repeat reminders after returning to the orb")
    }

    @MainActor
    func testPendingOfferReminderSurvivesRelaunchAndCoalescesAnOverdueDeadline() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("2m2better-reminder-state-\(UUID().uuidString)")
        let stateStore = CompanionStateStore(fileURL: stateURL)
        defer { try? FileManager.default.removeItem(at: stateURL) }

        let start = referenceDate(9_000)
        var now = start
        let first = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            speaker: RecordingSpeaker(),
            nowProvider: { now },
            stateStore: stateStore
        )
        first.continueWithBalancedDefaults()
        first.offerBreakNow()
        let offeredRoutine = first.routine
        first.collapseCheckIn()

        now = start.addingTimeInterval(CompanionStore.pendingOfferReminderInterval - 1)
        let restarted = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            speaker: RecordingSpeaker(),
            nowProvider: { now },
            stateStore: stateStore
        )
        restarted.continueWithBalancedDefaults()
        XCTAssertEqual(restarted.mode, .checkIn)
        XCTAssertTrue(restarted.isCheckInCollapsed)
        XCTAssertEqual(restarted.routine, offeredRoutine)

        restarted.tickForTesting(at: start.addingTimeInterval(CompanionStore.pendingOfferReminderInterval), userIsActive: false)
        XCTAssertEqual(restarted.mode, .checkIn)
        XCTAssertFalse(restarted.isCheckInCollapsed)
        XCTAssertEqual(restarted.routine, offeredRoutine)

        now = start.addingTimeInterval(3 * CompanionStore.pendingOfferReminderInterval)
        let overdueSpeaker = RecordingSpeaker()
        let overdue = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            speaker: overdueSpeaker,
            nowProvider: { now },
            stateStore: stateStore
        )
        overdue.continueWithBalancedDefaults()
        overdue.tickForTesting(at: now, userIsActive: false)
        XCTAssertEqual(overdue.mode, .checkIn)
        XCTAssertEqual(overdueSpeaker.spoken.count, 1, "an overdue relaunch reminder should be delivered once")
        overdue.tickForTesting(at: now, userIsActive: false)
        XCTAssertEqual(overdueSpeaker.spoken.count, 1, "handling an overdue deadline must move it forward five minutes")
    }

    @MainActor
    func testSettingsDoNotDiscardOrAccelerateAPendingReminder() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = referenceDate(9_500)
        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            speaker: RecordingSpeaker(),
            nowProvider: { start }
        )
        store.continueWithBalancedDefaults()
        store.offerBreakNow()
        let offeredRoutine = store.routine
        let progress = store.checkInProgress
        let remaining = store.nextCheckInRemainingSeconds
        store.collapseCheckIn()
        store.openAreaConfiguration()
        store.tickForTesting(at: start.addingTimeInterval(CompanionStore.pendingOfferReminderInterval), userIsActive: false)
        XCTAssertEqual(store.mode, .configuration, "Settings must not present a pending reminder over the settings surface")

        store.cancelAreaConfiguration()
        XCTAssertEqual(store.mode, .checkIn)
        XCTAssertTrue(store.isCheckInCollapsed)
        XCTAssertEqual(store.checkInProgress, progress)
        XCTAssertEqual(store.nextCheckInRemainingSeconds, remaining)
        store.tickForTesting(at: start.addingTimeInterval(CompanionStore.pendingOfferReminderInterval), userIsActive: false)
        XCTAssertEqual(store.mode, .checkIn)
        XCTAssertFalse(store.isCheckInCollapsed)
        XCTAssertEqual(store.routine, offeredRoutine)
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

    func testObservedIdleSampleDecaysNearThresholdActiveUse() {
        let start = referenceDate(1_000)
        var tracker = makeNearDueTracker(start: start)
        XCTAssertEqual(tracker.accumulatedActiveTime, 3_599)

        _ = tracker.tick(at: start.addingTimeInterval(3_600), userIsActive: false)
        let resumed = tracker.tick(
            at: start.addingTimeInterval(3_601),
            userIsActive: true
        )

        XCTAssertTrue(resumed.didResetAfterIdle)
        XCTAssertEqual(resumed.activeSeconds, 3_599.5)
        XCTAssertFalse(resumed.shouldOfferCheckIn)
    }

    func testDelayedActiveSampleAfterObservedIdleDiscountsTheGap() {
        let start = referenceDate(2_400)
        var tracker = ActiveUseTracker(
            activeInterval: 1_000,
            idleThreshold: 60,
            startedAt: start,
            persistenceState: ActiveUseTracker.PersistenceState(
                accumulatedActiveTime: 100,
                lastActiveSampleAt: start,
                lastSampleWasIdle: false
            )
        )

        _ = tracker.tick(at: start.addingTimeInterval(1), userIsActive: false)
        let resumed = tracker.tick(
            at: start.addingTimeInterval(601),
            userIsActive: true
        )

        XCTAssertTrue(resumed.didResetAfterIdle)
        XCTAssertEqual(resumed.activeSeconds, 2)
        XCTAssertFalse(resumed.shouldOfferCheckIn)
    }

    func testSystemBoundaryFollowedByObservedIdleDoesNotDoubleDecayOnReturn() {
        let start = referenceDate(2_450)
        let boundary = start.addingTimeInterval(1)
        var tracker = ActiveUseTracker(
            activeInterval: 100,
            idleThreshold: 60,
            startedAt: boundary,
            persistenceState: ActiveUseTracker.PersistenceState(
                accumulatedActiveTime: 49.5,
                lastActiveSampleAt: boundary,
                lastSampleWasIdle: false
            )
        )

        _ = tracker.markInactive(at: boundary)
        _ = tracker.tick(at: start.addingTimeInterval(2), userIsActive: false)
        let resumed = tracker.tick(
            at: start.addingTimeInterval(3),
            userIsActive: true
        )

        XCTAssertTrue(resumed.didResetAfterIdle)
        XCTAssertEqual(resumed.activeSeconds, 50)
        XCTAssertFalse(resumed.shouldOfferCheckIn)
    }

    func testActiveCadenceCreditUsesOneXAndInactiveUsesHalfX() {
        let start = referenceDate(2_500)
        var tracker = ActiveUseTracker(
            activeInterval: 3_600,
            idleThreshold: 60,
            startedAt: start
        )

        for second in 1...1_200 {
            _ = tracker.tick(
                at: start.addingTimeInterval(TimeInterval(second)),
                userIsActive: true
            )
        }
        XCTAssertEqual(tracker.accumulatedActiveTime, 1_200)

        let inactive = tracker.tick(
            at: start.addingTimeInterval(1_800),
            userIsActive: false
        )
        XCTAssertEqual(inactive.activeSeconds, 900, "10 inactive minutes should spend 5 minutes of credit")
        XCTAssertFalse(inactive.shouldOfferCheckIn, "inactivity must not offer a pause")
    }

    func testInactiveCadenceCreditClampsAtZero() {
        let start = referenceDate(2_700)
        var tracker = ActiveUseTracker(
            activeInterval: 3_600,
            idleThreshold: 60,
            startedAt: start
        )

        for second in 1...10 {
            _ = tracker.tick(
                at: start.addingTimeInterval(TimeInterval(second)),
                userIsActive: true
            )
        }
        let inactive = tracker.tick(
            at: start.addingTimeInterval(1_010),
            userIsActive: false
        )

        XCTAssertEqual(inactive.activeSeconds, 0)
        XCTAssertFalse(inactive.shouldOfferCheckIn)
    }

    func testInactiveToActiveTransitionResumesFromDecayedCredit() {
        let start = referenceDate(2_900)
        var tracker = ActiveUseTracker(
            activeInterval: 10,
            idleThreshold: 60,
            startedAt: start
        )

        for second in 1...8 {
            _ = tracker.tick(
                at: start.addingTimeInterval(TimeInterval(second)),
                userIsActive: true
            )
        }
        let inactive = tracker.tick(
            at: start.addingTimeInterval(12),
            userIsActive: false
        )
        XCTAssertEqual(inactive.activeSeconds, 6)
        XCTAssertFalse(inactive.shouldOfferCheckIn)

        let resumed = tracker.tick(
            at: start.addingTimeInterval(13),
            userIsActive: true
        )
        XCTAssertTrue(resumed.didResetAfterIdle)
        XCTAssertEqual(resumed.activeSeconds, 7)
        XCTAssertFalse(resumed.shouldOfferCheckIn, "returning to work must not immediately offer a pause")

        _ = tracker.tick(at: start.addingTimeInterval(14), userIsActive: true)
        _ = tracker.tick(at: start.addingTimeInterval(15), userIsActive: true)
        let due = tracker.tick(at: start.addingTimeInterval(16), userIsActive: true)
        XCTAssertEqual(due.activeSeconds, 10)
        XCTAssertTrue(due.shouldOfferCheckIn, "active use must earn the remaining credit after returning")
    }

    func testCadenceCreditPersistsAcrossTrackerRelaunch() {
        let start = referenceDate(3_100)
        var tracker = ActiveUseTracker(
            activeInterval: 3_600,
            idleThreshold: 60,
            startedAt: start
        )
        for second in 1...20 {
            _ = tracker.tick(
                at: start.addingTimeInterval(TimeInterval(second)),
                userIsActive: true
            )
        }

        let restarted = ActiveUseTracker(
            activeInterval: 3_600,
            idleThreshold: 60,
            startedAt: start.addingTimeInterval(20),
            persistenceState: tracker.persistenceState
        )
        XCTAssertEqual(restarted.accumulatedActiveTime, 20)

        var inactiveTracker = tracker
        _ = inactiveTracker.markInactive(at: start.addingTimeInterval(20))
        var restartedAfterSystemInactivity = ActiveUseTracker(
            activeInterval: 3_600,
            idleThreshold: 60,
            startedAt: start.addingTimeInterval(620),
            persistenceState: inactiveTracker.persistenceState
        )
        let resumed = restartedAfterSystemInactivity.tick(
            at: start.addingTimeInterval(621),
            userIsActive: true
        )
        XCTAssertEqual(resumed.activeSeconds, 2)
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

    func testInactiveSampleAfterSuspensionDefersTheFirstActiveOffer() {
        let start = referenceDate(3_400)
        var tracker = ActiveUseTracker(
            activeInterval: 10,
            idleThreshold: 60,
            startedAt: start,
            persistenceState: ActiveUseTracker.PersistenceState(
                accumulatedActiveTime: 9.5,
                lastActiveSampleAt: start,
                lastSampleWasIdle: false
            )
        )
        tracker.suspend(at: start)
        _ = tracker.tick(at: start.addingTimeInterval(1), userIsActive: false)

        let resumed = tracker.tick(
            at: start.addingTimeInterval(2),
            userIsActive: true
        )
        XCTAssertTrue(resumed.didResetAfterIdle)
        XCTAssertEqual(resumed.activeSeconds, 10)
        XCTAssertFalse(resumed.shouldOfferCheckIn)

        let due = tracker.tick(at: start.addingTimeInterval(3), userIsActive: true)
        XCTAssertTrue(due.shouldOfferCheckIn)
    }

    func testSuspendingActiveUseDoesNotGrantSettingsTime() {
        let start = referenceDate(3_500)
        var tracker = ActiveUseTracker(
            activeInterval: 5,
            idleThreshold: 60,
            startedAt: start
        )
        _ = tracker.tick(at: start.addingTimeInterval(1), userIsActive: true)
        tracker.suspend(at: start.addingTimeInterval(100))

        let resumed = tracker.tick(at: start.addingTimeInterval(101), userIsActive: true)

        XCTAssertFalse(resumed.didResetAfterIdle)
        XCTAssertEqual(resumed.activeSeconds, 2)
        XCTAssertFalse(resumed.shouldOfferCheckIn)
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
    func testSystemInactiveBoundaryDecaysCreditAndDefersOfferOnUnlock() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = referenceDate(5_100)
        let active = activitySignal(0.2, 0.2)
        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "5", "BREAK_IDLE_THRESHOLD_SECONDS": "10"],
            defaults: defaults,
            activitySignalProvider: { active },
            speaker: RecordingSpeaker(),
            nowProvider: { start }
        )
        store.continueWithBalancedDefaults()
        for second in 1...4 {
            store.tickForTesting(at: start.addingTimeInterval(TimeInterval(second)))
        }
        store.noteSystemInactive(at: start.addingTimeInterval(4))
        store.tickForTesting(at: start.addingTimeInterval(5))

        XCTAssertEqual(store.mode, .idle, "a system-inactive boundary must not offer on the first active sample")
        XCTAssertEqual(store.nextCheckInRemainingSeconds, 0.5)

        store.tickForTesting(at: start.addingTimeInterval(6))
        XCTAssertEqual(store.mode, .checkIn, "the next active sample may present the already-reached cadence")
    }

    @MainActor
    func testSystemInactiveBoundarySurvivesSettingsObservation() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = referenceDate(5_125)
        var now = start
        let store = CompanionStore(
            environment: [
                "BREAK_INTERVAL_SECONDS": "5",
                "BREAK_IDLE_THRESHOLD_SECONDS": "10"
            ],
            defaults: defaults,
            speaker: RecordingSpeaker(),
            nowProvider: { now }
        )
        store.continueWithBalancedDefaults()
        for second in 1...4 {
            store.tickForTesting(at: start.addingTimeInterval(TimeInterval(second)), userIsActive: true)
        }

        now = start.addingTimeInterval(4)
        store.openAreaConfiguration()
        store.noteSystemInactive(at: now)
        now = start.addingTimeInterval(5)
        store.tickForTesting(at: now, userIsActive: false)
        store.cancelAreaConfiguration()
        store.tickForTesting(at: start.addingTimeInterval(6), userIsActive: true)

        XCTAssertEqual(store.mode, .idle)
        XCTAssertEqual(store.nextCheckInRemainingSeconds, 0.5)
        store.tickForTesting(at: start.addingTimeInterval(7), userIsActive: true)
        XCTAssertEqual(store.mode, .checkIn)
    }

    @MainActor
    func testInactiveToActiveControllerTransitionDoesNotOfferImmediately() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = referenceDate(5_150)
        let store = CompanionStore(
            environment: [
                "BREAK_INTERVAL_SECONDS": "10",
                "BREAK_IDLE_THRESHOLD_SECONDS": "60"
            ],
            defaults: defaults,
            speaker: RecordingSpeaker(),
            nowProvider: { start }
        )
        store.continueWithBalancedDefaults()

        for second in 1...8 {
            store.tickForTesting(at: start.addingTimeInterval(TimeInterval(second)), userIsActive: true)
        }
        store.tickForTesting(at: start.addingTimeInterval(12), userIsActive: false)
        XCTAssertEqual(store.mode, .idle)
        XCTAssertEqual(store.checkInProgress, 0.6)

        store.tickForTesting(at: start.addingTimeInterval(13), userIsActive: true)
        XCTAssertEqual(store.mode, .idle)
        store.tickForTesting(at: start.addingTimeInterval(14), userIsActive: true)
        store.tickForTesting(at: start.addingTimeInterval(15), userIsActive: true)
        XCTAssertEqual(store.mode, .idle)
        store.tickForTesting(at: start.addingTimeInterval(16), userIsActive: true)
        XCTAssertEqual(store.mode, .checkIn)
    }

    @MainActor
    func testControllerCountsActiveKeyboardAndMouseWorkButExcludesIdleAndLockGaps() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = referenceDate(5_200)
        var signal = LocalActivitySignal(
            keyboardIdle: 10_000,
            mouseMovementIdle: 10_000,
            mouseClickIdle: 10_000,
            scrollWheelIdle: 10_000,
            mouseDragIdle: 10_000
        )
        let store = CompanionStore(
            environment: [
                "BREAK_INTERVAL_SECONDS": "5",
                "BREAK_IDLE_THRESHOLD_SECONDS": "10"
            ],
            defaults: defaults,
            activitySignalProvider: { signal },
            speaker: RecordingSpeaker(),
            nowProvider: { start }
        )
        store.continueWithBalancedDefaults()

        // A locked/idle period must be a mask, not active app uptime.
        for second in 1...20 {
            store.tickForTesting(at: start.addingTimeInterval(TimeInterval(second)))
        }
        XCTAssertEqual(store.mode, .idle)

        signal = LocalActivitySignal(keyboardIdle: 0.2, pointerIdle: 0.2)
        for second in 21...24 {
            store.tickForTesting(at: start.addingTimeInterval(TimeInterval(second)))
        }
        XCTAssertEqual(store.mode, .idle)
        store.tickForTesting(at: start.addingTimeInterval(25))
        XCTAssertEqual(store.mode, .checkIn, "the active controller path should offer at the configured cadence")
    }

    func testPauseRelativeTimeUsesLocalCalendarBoundariesAndIgnoresFutureHistory() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 12))!

        XCTAssertEqual(
            PauseRelativeTimeFormatter.string(
                for: now.addingTimeInterval(-23 * 60),
                relativeTo: now,
                calendar: calendar
            ),
            "23m ago"
        )
        XCTAssertEqual(
            PauseRelativeTimeFormatter.string(
                for: now.addingTimeInterval(-60 * 60),
                relativeTo: now,
                calendar: calendar
            ),
            "over 1h ago"
        )
        XCTAssertEqual(
            PauseRelativeTimeFormatter.string(
                for: now.addingTimeInterval(-90 * 60),
                relativeTo: now,
                calendar: calendar
            ),
            "over 1h ago"
        )
        XCTAssertEqual(
            PauseRelativeTimeFormatter.string(
                for: now.addingTimeInterval(-120 * 60),
                relativeTo: now,
                calendar: calendar
            ),
            "over 2h ago"
        )
        XCTAssertEqual(
            PauseRelativeTimeFormatter.string(
                for: calendar.date(from: DateComponents(year: 2026, month: 1, day: 9, hour: 23, minute: 59))!,
                relativeTo: now,
                calendar: calendar
            ),
            "yesterday"
        )
        XCTAssertEqual(
            PauseRelativeTimeFormatter.string(
                for: calendar.date(from: DateComponents(year: 2026, month: 1, day: 8, hour: 12))!,
                relativeTo: now,
                calendar: calendar
            ),
            "day before yesterday"
        )
        XCTAssertEqual(
            PauseRelativeTimeFormatter.string(
                for: calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 12))!,
                relativeTo: now,
                calendar: calendar
            ),
            "5 days ago"
        )
        XCTAssertEqual(
            PauseRelativeTimeFormatter.string(
                for: now.addingTimeInterval(60),
                relativeTo: now,
                calendar: calendar
            ),
            nil
        )
    }

    @MainActor
    func testPauseHistoryPersistsCompletedPausesAndCollapsePreservesDecision() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let scheduler = ManualDelayedActionScheduler()
        let start = referenceDate(10_000)
        var now = start
        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            activitySignalProvider: { LocalActivitySignal(keyboardIdle: 10_000, pointerIdle: 10_000) },
            speaker: RecordingSpeaker(),
            nowProvider: { now },
            postponementScheduler: scheduler
        )
        store.continueWithBalancedDefaults()
        var resizedModes: [CompanionStore.Mode] = []
        store.onSizeChange = { resizedModes.append($0) }
        store.offerBreakNow()
        XCTAssertEqual(store.mode, .checkIn)
        XCTAssertEqual(store.lastCompletedPauseContext, "none yet", "No completed pause should show an honest empty context")

        let remainingBeforeCollapse = store.nextCheckInRemainingSeconds
        let progressBeforeCollapse = store.checkInProgress
        store.collapseCheckIn()
        XCTAssertTrue(store.isCheckInCollapsed)
        XCTAssertEqual(store.mode, .checkIn)
        XCTAssertEqual(store.nextCheckInRemainingSeconds, remainingBeforeCollapse)
        XCTAssertEqual(store.checkInProgress, progressBeforeCollapse)

        store.tickForTesting(at: start.addingTimeInterval(30), userIsActive: true)
        XCTAssertEqual(store.mode, .checkIn, "Hiding the prompt must not turn it into an idle/deferral state")
        store.restoreCheckIn()
        XCTAssertFalse(store.isCheckInCollapsed)
        XCTAssertEqual(resizedModes, [.checkIn, .checkIn, .checkIn], "Offer, collapse, and restore must refit the real panel without changing mode")
        store.startRoutine(at: start, activitySignal: LocalActivitySignal(keyboardIdle: 10_000, pointerIdle: 10_000))
        XCTAssertEqual(store.mode, .routine, "The existing Start choice must still work after restore")

        for second in 1...119 {
            store.tickForTesting(at: start.addingTimeInterval(TimeInterval(second)), userIsActive: false)
        }
        now = start.addingTimeInterval(120)
        store.tickForTesting(at: now, userIsActive: false)
        XCTAssertEqual(store.mode, .complete)
        XCTAssertEqual(PauseHistoryStore(defaults: defaults).completedPauseDates.count, 1)
        store.dismissCompletion()

        now = start.addingTimeInterval(120 + 23 * 60)
        store.offerBreakNow()
        XCTAssertEqual(store.lastCompletedPauseContext, "23m ago")

        let restarted = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            speaker: RecordingSpeaker(),
            nowProvider: { now },
            postponementScheduler: scheduler
        )
        restarted.continueWithBalancedDefaults()
        restarted.offerBreakNow()
        XCTAssertEqual(restarted.lastCompletedPauseContext, "23m ago", "Completed pause context must survive relaunch")

        let remainingAfterRelaunch = restarted.nextCheckInRemainingSeconds
        restarted.collapseCheckIn()
        restarted.restoreCheckIn()
        XCTAssertEqual(restarted.nextCheckInRemainingSeconds, remainingAfterRelaunch)
        restarted.postpone(minutes: 60)
        XCTAssertEqual(restarted.statusText, "I’ll check back in an hour.")
        scheduler.runPendingAction()
        XCTAssertEqual(restarted.mode, .idle, "Later must retain its existing deferral behavior after restore")
    }

    @MainActor
    func testTimerAndRoutineStateSurviveRelaunchOutsideTheAppBundle() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("2m2better-state-\(UUID().uuidString)", isDirectory: false)
        let stateStore = CompanionStateStore(fileURL: stateURL)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: stateURL)
        }

        let productionPath = CompanionStateStore().fileURL.path
        XCTAssertTrue(productionPath.contains("Library/Application Support/2m2better"))
        let start = referenceDate(20_000)
        var now = start
        let signal = LocalActivitySignal(keyboardIdle: 10_000, pointerIdle: 10_000)
        let firstStore = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            activitySignalProvider: { signal },
            speaker: RecordingSpeaker(),
            nowProvider: { now },
            stateStore: stateStore
        )
        firstStore.continueWithBalancedDefaults()
        firstStore.tickForTesting(at: start.addingTimeInterval(1), userIsActive: true)
        XCTAssertEqual(firstStore.nextCheckInRemainingSeconds, 3_599)

        now = start.addingTimeInterval(2)
        let restartedIdle = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            activitySignalProvider: { signal },
            speaker: RecordingSpeaker(),
            nowProvider: { now },
            stateStore: stateStore
        )
        XCTAssertEqual(restartedIdle.nextCheckInRemainingSeconds, 3_599)
        restartedIdle.tickForTesting(at: start.addingTimeInterval(3), userIsActive: true)
        XCTAssertEqual(restartedIdle.nextCheckInRemainingSeconds, 3_598)

        restartedIdle.offerBreakNow()
        restartedIdle.startRoutine(at: start.addingTimeInterval(4), activitySignal: signal)
        for second in 1...7 {
            restartedIdle.tickForTesting(at: start.addingTimeInterval(4 + TimeInterval(second)), userIsActive: false)
        }
        restartedIdle.togglePause()

        now = start.addingTimeInterval(12)
        let restartedRoutine = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            activitySignalProvider: { signal },
            speaker: RecordingSpeaker(),
            nowProvider: { now },
            stateStore: stateStore
        )
        XCTAssertEqual(restartedRoutine.mode, .routine)
        XCTAssertEqual(restartedRoutine.elapsedInStep, 7)
        XCTAssertTrue(restartedRoutine.isPaused, "The active pause session must resume from durable state")
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

    func testQualifyingInputSignalsChangeAutomaticIdleTiming() {
        let click = LocalActivitySignal(
            keyboardIdle: 60,
            mouseMovementIdle: 60,
            mouseClickIdle: 0.2,
            scrollWheelIdle: 60
        )
        XCTAssertEqual(click.pointerIdle, 0.2)
        XCTAssertEqual(click.workActivityIdle, 0.2)

        let scroll = LocalActivitySignal(
            keyboardIdle: 60,
            mouseMovementIdle: 60,
            mouseClickIdle: 60,
            scrollWheelIdle: 0.2
        )
        XCTAssertEqual(scroll.pointerIdle, 0.2)
        XCTAssertEqual(scroll.workActivityIdle, 0.2)

        let drag = LocalActivitySignal(
            keyboardIdle: 60,
            mouseMovementIdle: 60,
            mouseClickIdle: 60,
            scrollWheelIdle: 60,
            mouseDragIdle: 0.2
        )
        XCTAssertEqual(drag.pointerIdle, 0.2)
        XCTAssertEqual(drag.workActivityIdle, 0.2)

        let keyboard = LocalActivitySignal(
            keyboardIdle: 0.2,
            mouseMovementIdle: 60,
            mouseClickIdle: 60,
            scrollWheelIdle: 60
        )
        XCTAssertEqual(keyboard.workActivityIdle, 0.2)

        let idle = LocalActivitySignal(
            keyboardIdle: 60,
            mouseMovementIdle: 60,
            mouseClickIdle: 60,
            scrollWheelIdle: 60,
            mouseDragIdle: 60
        )
        XCTAssertEqual(idle.workActivityIdle, 60)
    }

    @MainActor
    func testDefaultIdleThresholdKeepsRecentKeyboardOrMouseInputActive() {
        XCTAssertEqual(CompanionStore.defaultIdleThreshold, 180)

        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var signal = activitySignal(CompanionStore.defaultIdleThreshold - 0.001, 10_000)
        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            activitySignalProvider: { signal },
            speaker: RecordingSpeaker(),
            nowProvider: { self.referenceDate(5_450) }
        )
        store.continueWithBalancedDefaults()

        XCTAssertEqual(store.diagnosticSnapshot().activeUsePath, .accumulating)

        signal = activitySignal(10_000, CompanionStore.defaultIdleThreshold - 0.001)
        XCTAssertEqual(store.diagnosticSnapshot().activeUsePath, .accumulating)

        signal = activitySignal(CompanionStore.defaultIdleThreshold, 10_000)
        XCTAssertEqual(store.diagnosticSnapshot().activeUsePath, .waitingForActivity)

        signal = activitySignal(10_000, CompanionStore.defaultIdleThreshold)
        XCTAssertEqual(store.diagnosticSnapshot().activeUsePath, .waitingForActivity)
    }

    @MainActor
    func testEnvironmentIdleThresholdOverrideRemainsStrictAndDeterministic() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var signal = activitySignal(10.001, 10_000)
        let store = CompanionStore(
            environment: [
                "BREAK_INTERVAL_SECONDS": "3600",
                "BREAK_IDLE_THRESHOLD_SECONDS": "10"
            ],
            defaults: defaults,
            activitySignalProvider: { signal },
            speaker: RecordingSpeaker(),
            nowProvider: { self.referenceDate(5_475) }
        )
        store.continueWithBalancedDefaults()

        XCTAssertEqual(store.diagnosticSnapshot().activeUsePath, .waitingForActivity)

        signal = activitySignal(9.999, 10_000)
        XCTAssertEqual(store.diagnosticSnapshot().activeUsePath, .accumulating)

        signal = activitySignal(10_000, 10.001)
        XCTAssertEqual(store.diagnosticSnapshot().activeUsePath, .waitingForActivity)

        signal = activitySignal(10_000, 9.999)
        XCTAssertEqual(store.diagnosticSnapshot().activeUsePath, .accumulating)
    }

    @MainActor
    func testAutomaticActivitySignalsOfferForKeyboardMovementDragClickAndScroll() {
        let start = referenceDate(5_500)
        let cases: [(String, LocalActivitySignal)] = [
            ("keyboard", activitySignal(0.2, 60)),
            ("movement", activitySignal(60, 0.2)),
            ("drag", activitySignal(60, 60, mouseDragIdle: 0.2)),
            ("click", activitySignal(60, 60, mouseClickIdle: 0.2)),
            ("scroll", activitySignal(60, 60, scrollWheelIdle: 0.2))
        ]

        for (label, signal) in cases {
            let suiteName = "BreakCompanionTests.automatic-\(label)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            defer { defaults.removePersistentDomain(forName: suiteName) }

            var signals = Array(repeating: signal, count: 5)
            let store = CompanionStore(
                environment: [
                    "BREAK_INTERVAL_SECONDS": "5",
                    "BREAK_IDLE_THRESHOLD_SECONDS": "10"
                ],
                defaults: defaults,
                activitySignalProvider: { signals.removeFirst() },
                speaker: RecordingSpeaker(),
                nowProvider: { start }
            )
            store.continueWithBalancedDefaults()
            for second in 1...5 {
                store.tickForTesting(at: start.addingTimeInterval(TimeInterval(second)))
            }

            XCTAssertEqual(store.mode, .checkIn, label)
        }
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

    func testCadenceDefaultsPersistAndMigrateSafely() {
        XCTAssertEqual(Cadence.allCases, [.twentyMinutes, .oneHour, .threeHours])
        XCTAssertEqual(
            Cadence.allCases.map(\.label),
            ["Every 20 minutes", "Every hour", "Every 3 hours"]
        )
        XCTAssertEqual(
            Cadence.allCases.map(\.interval),
            [1_200, 3_600, 10_800]
        )

        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fresh = CadencePreferences(defaults: defaults)
        XCTAssertEqual(fresh.selectedCadence, .oneHour)
        XCTAssertEqual(defaults.string(forKey: CadencePreferences.selectedCadenceKey), Cadence.oneHour.rawValue)

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(Cadence.threeHours.interval, forKey: CadencePreferences.legacyIntervalKey)
        XCTAssertEqual(CadencePreferences(defaults: defaults).selectedCadence, .threeHours)

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("not-a-cadence", forKey: CadencePreferences.selectedCadenceKey)
        XCTAssertEqual(CadencePreferences(defaults: defaults).selectedCadence, .oneHour)
        XCTAssertEqual(defaults.string(forKey: CadencePreferences.selectedCadenceKey), Cadence.oneHour.rawValue)
    }

    @MainActor
    func testSettingsPersistCadenceAndAreasAndCadenceControlsTheTimer() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = referenceDate(20_000)
        let store = CompanionStore(
            environment: [:],
            defaults: defaults,
            speaker: RecordingSpeaker(),
            nowProvider: { start }
        )
        XCTAssertEqual(store.selectedCadence, .oneHour)
        XCTAssertEqual(store.nextCheckInRemainingSeconds, Cadence.oneHour.interval)

        store.saveSettings(cadence: .twentyMinutes, areas: [.neck, .handsWrists])
        XCTAssertEqual(store.mode, .idle)
        XCTAssertEqual(store.selectedCadence, .twentyMinutes)
        XCTAssertEqual(store.selectedAreas, [.neck, .handsWrists])
        XCTAssertEqual(store.nextCheckInRemainingSeconds, Cadence.twentyMinutes.interval)
        XCTAssertEqual(
            defaults.string(forKey: CadencePreferences.selectedCadenceKey),
            Cadence.twentyMinutes.rawValue
        )

        for second in 1..<Int(Cadence.twentyMinutes.interval) {
            store.tickForTesting(at: start.addingTimeInterval(TimeInterval(second)), userIsActive: true)
        }
        XCTAssertEqual(store.mode, .idle)
        store.tickForTesting(
            at: start.addingTimeInterval(Cadence.twentyMinutes.interval),
            userIsActive: true
        )
        XCTAssertEqual(store.mode, .checkIn)

        let restarted = CompanionStore(
            environment: [:],
            defaults: defaults,
            speaker: RecordingSpeaker(),
            nowProvider: { start }
        )
        XCTAssertEqual(restarted.selectedCadence, .twentyMinutes)
        XCTAssertEqual(restarted.selectedAreas, [.neck, .handsWrists])
    }

    @MainActor
    func testDiagnosticsReportOnlyCoarseLocalCadenceAreaModeAndPath() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let scheduler = ManualDelayedActionScheduler()
        let store = CompanionStore(
            environment: [:],
            defaults: defaults,
            speaker: RecordingSpeaker(),
            nowProvider: { self.referenceDate(30_000) },
            postponementScheduler: scheduler
        )
        store.continueWithBalancedDefaults()

        XCTAssertEqual(
            store.diagnosticSnapshot(activityIsActive: false),
            CompanionDiagnosticSnapshot(
                cadence: .oneHour,
                selectedAreas: [],
                mode: "idle",
                activeUsePath: .waitingForActivity
            )
        )
        XCTAssertEqual(
            store.diagnosticSnapshot(activityIsActive: true).activeUsePath,
            .accumulating
        )

        store.offerBreakNow()
        XCTAssertEqual(store.diagnosticSnapshot(activityIsActive: true).activeUsePath, .pendingOffer)
        XCTAssertEqual(
            store.diagnosticSnapshot(activityIsActive: true).pendingOfferPresentation,
            .visibleChoices
        )
        XCTAssertTrue(store.diagnosticReport().contains("active-use path: pending offer"))
        XCTAssertTrue(store.diagnosticReport().contains("offer presentation: visible pause choices"))
        store.collapseCheckIn()
        XCTAssertEqual(store.diagnosticSnapshot().pendingOfferPresentation, .collapsedOrb)
        store.restoreCheckIn()
        store.postpone(minutes: 60)
        scheduler.runPendingAction()
        XCTAssertEqual(store.diagnosticSnapshot(activityIsActive: true).activeUsePath, .scheduled)

        let report = store.diagnosticReport(activityIsActive: true)
        XCTAssertTrue(report.contains("cadence: Every hour"))
        XCTAssertTrue(report.contains("body areas: balanced mix"))
        XCTAssertTrue(report.contains("mode: idle"))
        XCTAssertTrue(report.contains("active-use path: scheduled check-in"))
        for forbidden in ["keyboardIdle", "pointer", "coordinates", "content", "analytics", "network"] {
            XCTAssertFalse(report.lowercased().contains(forbidden.lowercased()), forbidden)
        }
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
        XCTAssertTrue(store.canOpenAreaConfiguration)
        XCTAssertTrue(store.offersBalancedChoice)

        store.saveSelectedAreas([.neck])
        XCTAssertEqual(store.mode, .idle)
        XCTAssertEqual(store.selectedAreas, [.neck])
        XCTAssertTrue(store.canOpenAreaConfiguration)
        XCTAssertFalse(store.offersBalancedChoice)

        store.openAreaConfiguration()
        XCTAssertEqual(store.mode, .configuration)
        XCTAssertTrue(store.canOpenAreaConfiguration)
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
    func testSettingsStayActionableAndPreserveAnUndecidedCheckIn() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = referenceDate(31_000)
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("2m2better-settings-state-\(UUID().uuidString)")
        let stateStore = CompanionStateStore(fileURL: stateURL)
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "5"],
            defaults: defaults,
            speaker: RecordingSpeaker(),
            nowProvider: { start },
            stateStore: stateStore
        )
        store.continueWithBalancedDefaults()
        store.offerBreakNow()
        XCTAssertEqual(store.mode, .checkIn)
        XCTAssertTrue(store.canOpenAreaConfiguration)

        store.openAreaConfiguration()
        XCTAssertEqual(store.mode, .configuration)
        store.cancelAreaConfiguration()
        XCTAssertEqual(store.mode, .checkIn, "cancelling settings must restore the pending offer")

        store.openAreaConfiguration()
        store.saveSettings(cadence: .twentyMinutes, areas: [.neck])
        XCTAssertEqual(store.mode, .checkIn, "saving settings must restore the pending offer")
        XCTAssertEqual(store.selectedCadence, .twentyMinutes)
        XCTAssertEqual(store.selectedAreas, [.neck])
        XCTAssertTrue(store.routine.invitation.lowercased().contains("neck"))

        store.openAreaConfiguration()
        let restarted = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "5"],
            defaults: defaults,
            speaker: RecordingSpeaker(),
            nowProvider: { start },
            stateStore: stateStore
        )
        XCTAssertEqual(restarted.mode, .checkIn, "an update while settings are open must not discard the offer")
        XCTAssertEqual(restarted.selectedAreas, [.neck])
    }

    @MainActor
    func testSettingsPreserveIdleCreditAndRoutineAndCompletionStates() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = referenceDate(32_000)
        let now = start
        let idleSignal = activitySignal(10_000, 10_000)
        let store = CompanionStore(
            environment: [:],
            defaults: defaults,
            activitySignalProvider: { idleSignal },
            speaker: RecordingSpeaker(),
            nowProvider: { now }
        )
        store.continueWithBalancedDefaults()
        store.tickForTesting(at: start.addingTimeInterval(1), userIsActive: true)
        store.tickForTesting(at: start.addingTimeInterval(2), userIsActive: true)
        XCTAssertEqual(store.nextCheckInRemainingSeconds, Cadence.oneHour.interval - 2)

        store.openAreaConfiguration()
        XCTAssertEqual(store.mode, .configuration)
        store.tickForTesting(at: start.addingTimeInterval(100), userIsActive: true)
        store.saveSettings(cadence: .twentyMinutes, areas: [.neck])
        XCTAssertEqual(store.mode, .idle)
        XCTAssertEqual(store.nextCheckInRemainingSeconds, Cadence.twentyMinutes.interval - 2)

        store.offerBreakNow()
        store.openAreaConfiguration()
        store.cancelAreaConfiguration()
        XCTAssertEqual(store.mode, .checkIn)
        XCTAssertEqual(store.diagnosticSnapshot().activeUsePath, .pendingOffer)

        store.startRoutine(at: now, activitySignal: activitySignal(30, 30))
        store.openAreaConfiguration()
        XCTAssertEqual(store.mode, .configuration)
        store.tickForTesting(at: now.addingTimeInterval(60), userIsActive: true)
        store.cancelAreaConfiguration()
        XCTAssertEqual(store.mode, .routine)
        XCTAssertEqual(store.elapsedInStep, 0, "Settings must not advance a routine step")

        store.openAreaConfiguration()
        store.saveSettings(cadence: .oneHour, areas: [.shoulders])
        XCTAssertEqual(store.mode, .routine)
        XCTAssertEqual(store.selectedAreas, [.shoulders])
        store.endRoutine()
        store.dismissCompletion()

        store.offerBreakNow()
        store.startRoutine(at: now, activitySignal: activitySignal(10_000, 10_000))
        for second in 1...120 {
            store.tickForTesting(at: now.addingTimeInterval(TimeInterval(second)), userIsActive: false)
        }
        XCTAssertEqual(store.mode, .complete)
        store.openAreaConfiguration()
        XCTAssertEqual(store.mode, .configuration)
        store.cancelAreaConfiguration()
        XCTAssertEqual(store.mode, .complete)
    }

    @MainActor
    func testSettingsVisitLongerThanCompanionToleranceDoesNotCancelRoutineOnReturnButSustainedWorkStillDoes() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = referenceDate(40_000)
        var now = start
        var signal = activitySignal(50, 50)
        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            activitySignalProvider: { signal },
            speaker: RecordingSpeaker(),
            nowProvider: { now }
        )
        store.continueWithBalancedDefaults()
        store.startRoutine(at: start, activitySignal: signal)

        for second in 1...9 {
            now = start.addingTimeInterval(TimeInterval(second))
            store.tickForTesting(at: now, userIsActive: false)
        }
        XCTAssertEqual(store.mode, .routine)
        XCTAssertEqual(store.elapsedInStep, 9)

        // Open Settings mid-routine with a fresh click.
        signal = activitySignal(50, 0.05)
        now = start.addingTimeInterval(10)
        store.openAreaConfiguration()
        XCTAssertEqual(store.mode, .configuration)

        // Stay in Settings well past the 3-second companion-interaction tolerance.
        now = start.addingTimeInterval(25)
        signal = activitySignal(50, 12)
        store.saveSettings(cadence: .twentyMinutes, areas: [.neck])
        XCTAssertEqual(store.mode, .routine, "Saving settings mid-routine must return to the routine")
        XCTAssertEqual(store.elapsedInStep, 9, "Settings must not advance the routine step")

        // The very next tick catches the closing interaction's own residual freshness.
        now = start.addingTimeInterval(26)
        signal = activitySignal(0.05, 50)
        store.tickForTesting(at: now, userIsActive: true)
        XCTAssertEqual(store.mode, .routine, "A settings visit longer than the interaction tolerance must not silently cancel the routine on return")
        XCTAssertEqual(store.elapsedInStep, 10)

        // Genuine sustained activity after the short return grace must still resume-cancel it.
        for second in 27...29 {
            now = start.addingTimeInterval(TimeInterval(second))
            store.tickForTesting(at: now, userIsActive: true)
        }
        XCTAssertEqual(store.mode, .checkIn, "Genuine sustained work after returning from Settings must still be detected")
    }

    @MainActor
    func testAutomaticThresholdCrossingRequestsVisiblePendingOfferAndClockCanStartAfterSetup() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = referenceDate(33_000)
        let active = activitySignal(0.2, 0.2)
        let store = CompanionStore(
            environment: [
                "BREAK_INTERVAL_SECONDS": "5",
                "BREAK_IDLE_THRESHOLD_SECONDS": "10"
            ],
            defaults: defaults,
            activitySignalProvider: { active },
            speaker: RecordingSpeaker(),
            nowProvider: { start }
        )
        store.continueWithBalancedDefaults()
        var resizedModes: [CompanionStore.Mode] = []
        store.onSizeChange = { resizedModes.append($0) }
        XCTAssertFalse(store.isClockRunning)
        store.startClock()
        XCTAssertTrue(store.isClockRunning)

        for second in 1...5 {
            store.tickForTesting(at: start.addingTimeInterval(TimeInterval(second)))
        }
        XCTAssertEqual(store.mode, .checkIn)
        XCTAssertEqual(resizedModes, [.checkIn])
        XCTAssertEqual(store.checkInProgress, 0)
        XCTAssertEqual(store.nextCheckInRemainingSeconds, 5)
        XCTAssertEqual(store.diagnosticSnapshot().activeUsePath, .pendingOffer)
        XCTAssertEqual(store.diagnosticSnapshot().pendingOfferPresentation, .visibleChoices)
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

    func testPauseScreenCollapseControlUsesChevronAccessibilityAndEscape() {
        XCTAssertEqual(PauseScreenControl.collapse.systemImage, "chevron.up")
        XCTAssertEqual(PauseScreenControl.collapse.title, "Collapse pause screen")
        XCTAssertFalse(PauseScreenControl.collapse.accessibilityLabel.isEmpty)
        XCTAssertFalse(PauseScreenControl.collapse.accessibilityHint.isEmpty)
        XCTAssertNotNil(PauseScreenControl.collapse.keyboardShortcut)
    }

    @MainActor
    func testPauseScreenCollapseControlIsReachableByEscapeThroughTheRealKeyboardSeam() {
        let suiteName = "BreakCompanionTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = referenceDate(20_000)
        let store = CompanionStore(
            environment: ["BREAK_INTERVAL_SECONDS": "3600"],
            defaults: defaults,
            speaker: RecordingSpeaker(),
            nowProvider: { start }
        )
        store.continueWithBalancedDefaults()
        store.offerBreakNow()
        XCTAssertEqual(store.mode, .checkIn)

        let panel = CompanionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 370, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: CompanionView(store: store))
        hostingView.frame = NSRect(x: 0, y: 0, width: 370, height: 420)
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()

        func escapeKeyDown() -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber,
                context: nil,
                characters: "\u{1B}",
                charactersIgnoringModifiers: "\u{1B}",
                isARepeat: false,
                keyCode: 53
            )!
        }

        let selectedAreasBeforeCollapse = store.selectedAreas
        let remainingBeforeCollapse = store.nextCheckInRemainingSeconds
        XCTAssertTrue(
            panel.performKeyEquivalent(with: escapeKeyDown()),
            "Escape must reach the rendered collapse control through its real keyboard shortcut wiring"
        )
        XCTAssertTrue(store.isCheckInCollapsed)
        XCTAssertEqual(store.mode, .checkIn, "collapsing through the keyboard must preserve the pending decision")
        XCTAssertEqual(store.nextCheckInRemainingSeconds, remainingBeforeCollapse)
        XCTAssertEqual(store.selectedAreas, selectedAreasBeforeCollapse)

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()
        XCTAssertFalse(
            panel.performKeyEquivalent(with: escapeKeyDown()),
            "the collapsed orb view has no Escape-bound control, so a second Escape must not be swallowed"
        )

        store.restoreCheckIn()
        XCTAssertFalse(store.isCheckInCollapsed)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()
        XCTAssertTrue(
            panel.performKeyEquivalent(with: escapeKeyDown()),
            "restoring the pause screen must bring the collapse control's keyboard shortcut back"
        )
        XCTAssertTrue(store.isCheckInCollapsed, "the real Escape seam must still reach collapse after a restore")
    }

    @MainActor
    func testCompanionPanelUsesAppKitBackgroundDragging() {
        let panel = CompanionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        XCTAssertTrue(panel.isMovableByWindowBackground)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
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

    private func makeUpdateFixture() throws -> GitHubReleasesUpdateService {
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
        return GitHubReleasesUpdateService(
            transport: transport,
            currentVersion: ProductIdentity.currentVersion,
            architecture: "arm64"
        )
    }

    private func activitySignal(
        _ keyboardIdle: TimeInterval,
        _ pointerIdle: TimeInterval,
        mouseClickIdle: TimeInterval = .infinity,
        scrollWheelIdle: TimeInterval = .infinity,
        mouseDragIdle: TimeInterval = .infinity
    ) -> LocalActivitySignal {
        LocalActivitySignal(
            keyboardIdle: keyboardIdle,
            mouseMovementIdle: pointerIdle,
            mouseClickIdle: mouseClickIdle,
            scrollWheelIdle: scrollWheelIdle,
            mouseDragIdle: mouseDragIdle
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
