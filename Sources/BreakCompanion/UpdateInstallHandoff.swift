import Foundation

protocol UpdateHandoffLaunching {
    func launch(for downloadedUpdate: DownloadedUpdate) throws
}

protocol UpdateHandoffProcessLaunching {
    func launch(executableURL: URL, arguments: [String]) throws
}

struct SystemUpdateHandoffProcessLauncher: UpdateHandoffProcessLaunching {
    func launch(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

struct UpdateInstallHandoffLauncher: UpdateHandoffLaunching {
    private let bundle: Bundle
    private let helperURL: URL?
    private let processLauncher: UpdateHandoffProcessLaunching
    private let fileManager: FileManager
    private let processID: Int32

    init(
        bundle: Bundle = .main,
        helperURL: URL? = nil,
        processLauncher: UpdateHandoffProcessLaunching = SystemUpdateHandoffProcessLauncher(),
        fileManager: FileManager = .default,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        self.bundle = bundle
        self.helperURL = helperURL
        self.processLauncher = processLauncher
        self.fileManager = fileManager
        self.processID = processID
    }

    func launch(for downloadedUpdate: DownloadedUpdate) throws {
        guard isRegularFile(downloadedUpdate.artifactURL) else {
            throw UpdateFailure.handoffUnavailable("the verified ZIP is no longer available")
        }
        guard downloadedUpdate.verifiedSHA256.count == 64,
              downloadedUpdate.verifiedSHA256.allSatisfy(\.isHexDigit) else {
            throw UpdateFailure.handoffUnavailable("the verified ZIP digest is invalid")
        }
        guard let sourceHelper = helperURL ?? bundle.url(forResource: "update-handoff", withExtension: "sh") else {
            throw UpdateFailure.handoffUnavailable("the bundled update helper is missing")
        }
        guard isRegularFile(sourceHelper) else {
            throw UpdateFailure.handoffUnavailable("the bundled update helper is not a regular file")
        }

        let handoffDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("\(ProductIdentity.name)-handoff-\(UUID().uuidString)", isDirectory: true)
        let helper = handoffDirectory.appendingPathComponent("update-handoff.sh")
        do {
            try fileManager.createDirectory(at: handoffDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceHelper, to: helper)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)

            try processLauncher.launch(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    helper.path,
                    "--archive", downloadedUpdate.artifactURL.path,
                    "--pid", String(processID),
                    "--sha256", downloadedUpdate.verifiedSHA256
                ]
            )
        } catch let failure as UpdateFailure {
            try? fileManager.removeItem(at: handoffDirectory)
            throw failure
        } catch {
            try? fileManager.removeItem(at: handoffDirectory)
            throw UpdateFailure.handoffUnavailable(error.localizedDescription)
        }
    }

    private func isRegularFile(_ url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]) else { return false }
        return values.isSymbolicLink != true
    }
}
