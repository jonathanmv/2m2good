import Foundation

/// The small set of states that the update window is allowed to show. Technical
/// release details stay in UpdateFailure and the update log instead of being
/// presented as part of the normal consent flow.
enum UpdateDialogPhase: Equatable {
    case checking
    case available(SemanticVersion)
    case downloaded(SemanticVersion)
    case downloading
    case installing
    case current
    case failed(UpdateDialogFailure)
    case success
}

enum UpdateDialogFailure: Equatable {
    case check
    case download
    case install
}

struct UpdateDialogModel: Equatable {
    let phase: UpdateDialogPhase

    var title: String {
        switch phase {
        case .checking: return "Checking for updates…"
        case .available: return "A new version is ready"
        case .downloaded: return "Ready to relaunch"
        case .downloading: return "Preparing your update…"
        case .installing: return "Installing your update…"
        case .current: return "You’re up to date"
        case .failed(.check): return "Updates are unavailable"
        case .failed(.download): return "Update couldn’t be prepared"
        case .failed(.install): return "Update couldn’t be installed"
        case .success: return "You’re all set"
        }
    }

    var message: String {
        switch phase {
        case .checking:
            return "Looking for a newer version."
        case .available(let version):
            return "\(ProductIdentity.name) \(version) is ready. Install it and relaunch now?"
        case .downloaded(let version):
            return "\(ProductIdentity.name) \(version) is ready. Install it and relaunch now?"
        case .downloading:
            return "This should only take a moment."
        case .installing:
            return "\(ProductIdentity.name) will relaunch when it’s ready."
        case .current:
            return "You already have the newest version."
        case .failed(.check):
            return "We couldn’t check for an update. Try again later."
        case .failed(.download):
            return "We couldn’t prepare the update. Try again."
        case .failed(.install):
            return "Your current version is unchanged. Try again."
        case .success:
            return "The latest version is installed."
        }
    }

    var primaryButtonTitle: String? {
        switch phase {
        case .available, .downloaded: return "Install and Relaunch"
        case .current, .success: return "Done"
        case .failed: return "Try Again"
        case .checking, .downloading, .installing: return nil
        }
    }

    var secondaryButtonTitle: String? {
        switch phase {
        case .available, .downloaded: return "Later"
        case .checking, .downloading, .failed: return "Cancel"
        case .current, .installing, .success: return nil
        }
    }

    var showsProgress: Bool {
        switch phase {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    var accessibilityProgressLabel: String? {
        switch phase {
        case .checking: return "Checking for updates"
        case .downloading: return "Preparing update"
        case .installing: return "Installing update"
        default: return nil
        }
    }
}

/// Owns the user-facing update flow while UpdateController remains responsible
/// for release verification and the install handoff. Keeping this seam separate
/// lets the real controller and the real window actions be exercised together.
@MainActor
final class UpdateFlowCoordinator {
    enum State: Equatable {
        case idle
        case checking
        case current
        case available(UpdateCandidate)
        case downloading(UpdateCandidate)
        case downloaded(DownloadedUpdate)
        case installing(UpdateCandidate)
        case failed(UpdateDialogFailure, retryCandidate: UpdateCandidate?)
    }

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    private(set) var shouldPresentDialog = false
    var onStateChange: ((State) -> Void)?

    let controller: UpdateController
    private var consentedCandidate: UpdateCandidate?

    init(controller: UpdateController) {
        self.controller = controller
        controller.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    func checkAutomatically(now: Date = Date()) {
        controller.checkAutomatically(now: now)
    }

    func checkManually(now: Date = Date()) {
        guard !controller.isBusy else { return }
        consentedCandidate = nil
        shouldPresentDialog = true
        state = .checking
        controller.checkManually(now: now)
    }

    func installAvailableUpdate() {
        switch state {
        case .available(let candidate):
            consentedCandidate = candidate
            shouldPresentDialog = true
            state = .downloading(candidate)
            guard controller.downloadAvailable() else {
                fail(.download, retryCandidate: candidate)
                return
            }
        case .downloaded(let downloaded):
            consentedCandidate = downloaded.candidate
            shouldPresentDialog = true
            _ = controller.installReadyUpdate()
        default:
            break
        }
    }

    func retry() {
        guard case .failed(_, let candidate) = state else { return }
        guard let candidate else {
            checkManually()
            return
        }

        consentedCandidate = candidate
        shouldPresentDialog = true
        state = .downloading(candidate)
        guard controller.retryDownload(candidate) else {
            fail(.download, retryCandidate: candidate)
            return
        }
    }

    /// Closes the current user-facing window. An in-flight check/download is
    /// cancelled; once installation has started the helper owns the handoff.
    func cancelOrDismiss() {
        switch state {
        case .checking, .downloading:
            controller.cancel()
            state = .idle
        case .downloaded:
            controller.resetReadyUpdate()
            state = .idle
        case .current, .failed:
            state = .idle
        case .available:
            // Keep the candidate so the menu can reopen the same prompt.
            break
        case .installing, .idle:
            break
        }
        shouldPresentDialog = false
        onStateChange?(state)
    }

    var dialogModel: UpdateDialogModel? {
        guard shouldPresentDialog else { return nil }
        switch state {
        case .idle: return nil
        case .checking: return UpdateDialogModel(phase: .checking)
        case .current: return UpdateDialogModel(phase: .current)
        case .available(let candidate): return UpdateDialogModel(phase: .available(candidate.version))
        case .downloading: return UpdateDialogModel(phase: .downloading)
        case .downloaded(let downloaded):
            return UpdateDialogModel(phase: .downloaded(downloaded.candidate.version))
        case .installing: return UpdateDialogModel(phase: .installing)
        case .failed(let failure, _): return UpdateDialogModel(phase: .failed(failure))
        }
    }

    private func handle(_ event: UpdateController.Event) {
        switch event {
        case .stateChanged:
            break
        case .manualResult(let result):
            shouldPresentDialog = true
            handleCheckResult(result, manual: true)
        case .automaticResult(let result):
            handleCheckResult(result, manual: false)
        case .downloaded(let downloaded):
            guard shouldPresentDialog else { return }
            state = .downloaded(downloaded)
            // The user's Install and Relaunch choice applies to the whole
            // operation. Once verification finishes, continue without another
            // technical confirmation dialog.
            if consentedCandidate == downloaded.candidate {
                _ = controller.installReadyUpdate()
            }
        case .downloadFailed(let failure):
            UpdateDiagnostics.record(failure, phase: "download")
            fail(.download, retryCandidate: consentedCandidate)
        case .installStarted:
            if let candidate = consentedCandidate {
                state = .installing(candidate)
            }
        case .installFailed(let failure):
            UpdateDiagnostics.record(failure, phase: "install")
            let candidate = consentedCandidate
            fail(.install, retryCandidate: candidate)
        }
    }

    private func handleCheckResult(_ result: UpdateCheckResult, manual: Bool) {
        switch result {
        case .current:
            if manual {
                state = .current
            } else {
                state = .idle
            }
        case .available(let candidate):
            shouldPresentDialog = true
            state = .available(candidate)
        case .failed(let failure):
            UpdateDiagnostics.record(failure, phase: "check")
            if manual {
                fail(.check, retryCandidate: nil)
            } else {
                // Automatic checks stay quiet unless there is an update to
                // offer. The diagnostic log remains available for support.
                state = .idle
            }
        }
    }

    private func fail(_ failure: UpdateDialogFailure, retryCandidate: UpdateCandidate?) {
        shouldPresentDialog = true
        state = .failed(failure, retryCandidate: retryCandidate)
    }
}

enum UpdateDiagnostics {
    static func logURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(ProductIdentity.name, isDirectory: true)
            .appendingPathComponent("update.log")
    }

    static func record(
        _ failure: UpdateFailure,
        phase: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let url = logURL(homeDirectory: homeDirectory)
        let directory = url.deletingLastPathComponent()
        let detail = failure.localizedDescription
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let entry = "2m2better update \(phase) failed.\nReason: \(detail)\n"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(entry.utf8))
                try handle.close()
            } else {
                try Data(entry.utf8).write(to: url, options: .atomic)
            }
        } catch {
            // A diagnostics failure must never alter the update decision or UI.
        }
    }
}
