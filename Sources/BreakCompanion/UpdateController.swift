import Foundation

@MainActor
final class UpdateController {
    enum State: Equatable {
        case idle
        case checking
        case current
        case available(UpdateCandidate)
        case downloading(UpdateCandidate)
        case ready(DownloadedUpdate)
        case failed(UpdateFailure)
    }

    enum Event {
        case stateChanged
        case manualResult(UpdateCheckResult)
        case downloaded(DownloadedUpdate)
        case downloadFailed(UpdateFailure)
    }

    static let lastCheckKey = "update.lastGitHubReleaseCheck"

    private(set) var state: State = .idle {
        didSet { onEvent?(.stateChanged) }
    }
    var onEvent: ((Event) -> Void)?

    private let service: GitHubReleasesUpdateService
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?
    private var manualCheckPending = false

    init(
        service: GitHubReleasesUpdateService = GitHubReleasesUpdateService(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
    }

    deinit {
        task?.cancel()
    }

    var menuTitle: String {
        switch state {
        case .idle, .current: return "Check for Updates…"
        case .checking: return "Checking for Updates…"
        case .available(let candidate): return "Update Available: \(candidate.version)…"
        case .downloading: return "Verifying Update…"
        case .ready: return "Show Verified Update…"
        case .failed: return "Retry Update Check…"
        }
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading: return true
        default: return false
        }
    }

    func checkAutomatically(now: Date = Date()) {
        guard task == nil else { return }
        let timestamp = defaults.double(forKey: Self.lastCheckKey)
        let lastCheck = timestamp == 0 ? nil : Date(timeIntervalSince1970: timestamp)
        guard UpdateSourcePolicy.shouldAutomaticallyCheck(lastCheck: lastCheck, now: now) else { return }
        startCheck(manual: false, now: now)
    }

    func checkManually(now: Date = Date()) {
        guard task == nil else { return }
        startCheck(manual: true, now: now)
    }

    func downloadAvailable() {
        guard task == nil, case .available(let candidate) = state else { return }
        state = .downloading(candidate)
        task = Task { [weak self, service] in
            do {
                let downloaded = try await service.downloadAndVerify(candidate)
                guard !Task.isCancelled else { return }
                self?.finishDownload(downloaded)
            } catch let failure as UpdateFailure {
                guard !Task.isCancelled else { return }
                self?.finishDownload(failure: failure)
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishDownload(failure: .unableToSave)
            }
        }
    }

    func markReadyUpdateAsShown() {
        guard case .ready = state else { return }
        state = .current
    }

    func resetReadyUpdate() {
        guard case .ready = state else { return }
        state = .idle
    }

    private func startCheck(manual: Bool, now: Date) {
        manualCheckPending = manual
        state = .checking
        defaults.set(now.timeIntervalSince1970, forKey: Self.lastCheckKey)
        task = Task { [weak self, service] in
            let result = await service.checkForUpdate()
            guard !Task.isCancelled else { return }
            self?.finishCheck(result)
        }
    }

    private func finishCheck(_ result: UpdateCheckResult) {
        task = nil
        switch result {
        case .current:
            state = .current
        case .available(let candidate):
            state = .available(candidate)
        case .failed(let failure):
            state = .failed(failure)
        }
        if manualCheckPending {
            onEvent?(.manualResult(result))
        }
        manualCheckPending = false
    }

    private func finishDownload(_ downloaded: DownloadedUpdate) {
        task = nil
        state = .ready(downloaded)
        onEvent?(.downloaded(downloaded))
    }

    private func finishDownload(failure: UpdateFailure) {
        task = nil
        state = .failed(failure)
        onEvent?(.downloadFailed(failure))
    }
}
