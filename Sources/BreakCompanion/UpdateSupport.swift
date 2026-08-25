import CryptoKit
import Foundation

struct ReleaseAsset: Decodable, Equatable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct GitHubRelease: Decodable, Equatable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [ReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

struct UpdateCandidate: Equatable {
    let version: SemanticVersion
    let releaseURL: URL
    let artifactName: String
    let artifactURL: URL
    let checksumName: String
    let checksumURL: URL
}

struct DownloadedUpdate: Equatable {
    let candidate: UpdateCandidate
    let artifactURL: URL
}

enum UpdateFailure: Error, Equatable, LocalizedError {
    case invalidSourceURL
    case network(String)
    case invalidRelease(String)
    case missingAsset(String)
    case invalidAssetURL(String)
    case responseTooLarge
    case unexpectedResponse
    case invalidChecksum
    case checksumMismatch
    case unableToSave

    var errorDescription: String? {
        switch self {
        case .invalidSourceURL:
            return "The configured GitHub Releases source is invalid."
        case .network(let message):
            return "GitHub Releases could not be reached: \(message)"
        case .invalidRelease(let message):
            return "The GitHub release was not accepted: \(message)"
        case .missingAsset(let name):
            return "The release does not contain the required verified asset \(name)."
        case .invalidAssetURL(let url):
            return "The release asset did not use an approved GitHub HTTPS URL: \(url)"
        case .responseTooLarge:
            return "The update response exceeded the safety limit."
        case .unexpectedResponse:
            return "GitHub returned an unexpected response."
        case .invalidChecksum:
            return "The release checksum file was missing or malformed."
        case .checksumMismatch:
            return "The downloaded update failed its SHA-256 checksum. Nothing was opened or installed."
        case .unableToSave:
            return "The verified update could not be saved locally. Nothing was installed."
        }
    }
}

enum UpdateCheckResult: Equatable {
    case current
    case available(UpdateCandidate)
    case failed(UpdateFailure)
}

enum UpdateSourcePolicy {
    static let maxReleaseResponseBytes = 256 * 1024
    static let maxChecksumResponseBytes = 32 * 1024
    static let maxArtifactBytes = 250 * 1024 * 1024
    static let requestTimeout: TimeInterval = 8
    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60
    static let supportedGitHubHosts = Set([
        "api.github.com",
        "github.com",
        "objects.githubusercontent.com"
    ])

    static func isApprovedGitHubURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host.map { supportedGitHubHosts.contains($0.lowercased()) } == true
    }

    static func isApprovedReleasePageURL(_ url: URL) -> Bool {
        isApprovedGitHubURL(url)
            && url.host?.lowercased() == "github.com"
            && url.path.hasPrefix("/\(ProductIdentity.releaseRepository)/releases")
    }

    static func isApprovedAssetURL(_ url: URL) -> Bool {
        guard isApprovedGitHubURL(url) else { return false }
        if url.host?.lowercased() == "objects.githubusercontent.com" { return true }
        return url.host?.lowercased() == "github.com"
            && url.path.hasPrefix("/\(ProductIdentity.releaseRepository)/releases/download/")
    }

    static func shouldAutomaticallyCheck(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= automaticCheckInterval
    }
}

enum GitHubReleaseSelector {
    static func candidate(
        from release: GitHubRelease,
        currentVersion: SemanticVersion,
        architecture: String
    ) throws -> UpdateCandidate? {
        guard !release.draft, !release.prerelease else { return nil }
        guard let version = SemanticVersion(tag: release.tagName) else {
            throw UpdateFailure.invalidRelease("tag \(release.tagName) is not semantic versioning")
        }
        guard version > currentVersion else { return nil }
        guard let normalizedArchitecture = normalizedArchitecture(architecture) else {
            throw UpdateFailure.invalidRelease("unsupported Mac architecture \(architecture)")
        }
        guard UpdateSourcePolicy.isApprovedReleasePageURL(release.htmlURL) else {
            throw UpdateFailure.invalidAssetURL(release.htmlURL.absoluteString)
        }

        let artifactName = "\(ProductIdentity.name)-v\(version)-macos-\(normalizedArchitecture).zip"
        let checksumName = "\(artifactName).sha256"
        guard let artifact = release.assets.first(where: { $0.name == artifactName }) else {
            throw UpdateFailure.missingAsset(artifactName)
        }
        guard let checksum = release.assets.first(where: { $0.name == checksumName }) else {
            throw UpdateFailure.missingAsset(checksumName)
        }
        guard UpdateSourcePolicy.isApprovedAssetURL(artifact.browserDownloadURL) else {
            throw UpdateFailure.invalidAssetURL(artifact.browserDownloadURL.absoluteString)
        }
        guard UpdateSourcePolicy.isApprovedAssetURL(checksum.browserDownloadURL) else {
            throw UpdateFailure.invalidAssetURL(checksum.browserDownloadURL.absoluteString)
        }

        return UpdateCandidate(
            version: version,
            releaseURL: release.htmlURL,
            artifactName: artifactName,
            artifactURL: artifact.browserDownloadURL,
            checksumName: checksumName,
            checksumURL: checksum.browserDownloadURL
        )
    }

    static func normalizedArchitecture(_ architecture: String) -> String? {
        switch architecture {
        case "arm64", "x86_64": return architecture
        default: return nil
        }
    }
}

enum UpdateArtifactVerifier {
    static func verify(data: Data, checksumFile: Data, expectedFileName: String) -> Bool {
        guard let text = String(data: checksumFile, encoding: .utf8) else { return false }
        let matchingLines = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2 else { return nil }
            let fileName = String(fields[1]).hasPrefix("*")
                ? String(String(fields[1]).dropFirst())
                : String(fields[1])
            guard fileName == expectedFileName else { return nil }
            return String(fields[0])
        }
        guard matchingLines.count == 1,
              matchingLines[0].count == 64,
              matchingLines[0].allSatisfy({ $0.isHexDigit }) else {
            return false
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest.caseInsensitiveCompare(matchingLines[0]) == .orderedSame
    }
}

protocol UpdateTransport {
    func data(for request: URLRequest, maxBytes: Int) async throws -> Data
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url else {
            completionHandler(nil)
            return
        }
        let originalURL = task.currentRequest?.url
        let isAPIRequest = originalURL?.host?.lowercased() == "api.github.com"
        let approved = isAPIRequest
            ? url.host?.lowercased() == "api.github.com" && UpdateSourcePolicy.isApprovedGitHubURL(url)
            : UpdateSourcePolicy.isApprovedAssetURL(url)
        completionHandler(approved ? request : nil)
    }
}

final class URLSessionUpdateTransport: NSObject, UpdateTransport {
    private let session: URLSession

    override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = UpdateSourcePolicy.requestTimeout
        configuration.timeoutIntervalForResource = UpdateSourcePolicy.requestTimeout
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
        super.init()
    }

    func data(for request: URLRequest, maxBytes: Int) async throws -> Data {
        guard let url = request.url, UpdateSourcePolicy.isApprovedGitHubURL(url) else {
            throw UpdateFailure.invalidSourceURL
        }
        var request = request
        request.timeoutInterval = UpdateSourcePolicy.requestTimeout
        do {
            let (data, response) = try await session.data(for: request)
            guard data.count <= maxBytes else { throw UpdateFailure.responseTooLarge }
            let finalURLIsApproved: (URL) -> Bool = url.host?.lowercased() == "api.github.com"
                ? { $0.host?.lowercased() == "api.github.com" && UpdateSourcePolicy.isApprovedGitHubURL($0) }
                : { UpdateSourcePolicy.isApprovedAssetURL($0) }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let finalURL = httpResponse.url,
                  finalURLIsApproved(finalURL) else {
                throw UpdateFailure.unexpectedResponse
            }
            return data
        } catch let failure as UpdateFailure {
            throw failure
        } catch {
            throw UpdateFailure.network(error.localizedDescription)
        }
    }
}

struct GitHubReleasesUpdateService {
    let transport: UpdateTransport
    let currentVersion: SemanticVersion
    let architecture: String

    init(
        transport: UpdateTransport = URLSessionUpdateTransport(),
        currentVersion: SemanticVersion = ProductIdentity.currentVersion,
        architecture: String = ProcessInfo.processInfo.machineArchitecture
    ) {
        self.transport = transport
        self.currentVersion = currentVersion
        self.architecture = architecture
    }

    func checkForUpdate() async -> UpdateCheckResult {
        var request = URLRequest(url: ProductIdentity.releaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(ProductIdentity.name)/\(ProductIdentity.currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let data = try await transport.data(for: request, maxBytes: UpdateSourcePolicy.maxReleaseResponseBytes)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            return try .availableOrCurrent(
                GitHubReleaseSelector.candidate(
                    from: release,
                    currentVersion: currentVersion,
                    architecture: architecture
                )
            )
        } catch let failure as UpdateFailure {
            return .failed(failure)
        } catch {
            return .failed(.invalidRelease(error.localizedDescription))
        }
    }

    func downloadAndVerify(_ candidate: UpdateCandidate) async throws -> DownloadedUpdate {
        guard candidate.version > currentVersion,
              UpdateSourcePolicy.isApprovedAssetURL(candidate.artifactURL),
              UpdateSourcePolicy.isApprovedAssetURL(candidate.checksumURL) else {
            throw UpdateFailure.invalidSourceURL
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(ProductIdentity.name)-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let artifactRequest: URLRequest = {
                var request = URLRequest(url: candidate.artifactURL)
                request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                return request
            }()
            let checksumRequest: URLRequest = {
                var request = URLRequest(url: candidate.checksumURL)
                request.setValue("text/plain", forHTTPHeaderField: "Accept")
                return request
            }()
            async let artifactData = transport.data(for: artifactRequest, maxBytes: UpdateSourcePolicy.maxArtifactBytes)
            async let checksumData = transport.data(for: checksumRequest, maxBytes: UpdateSourcePolicy.maxChecksumResponseBytes)
            let (artifact, checksum) = try await (artifactData, checksumData)
            guard UpdateArtifactVerifier.verify(
                data: artifact,
                checksumFile: checksum,
                expectedFileName: candidate.artifactName
            ) else {
                throw UpdateFailure.checksumMismatch
            }
            let artifactURL = directory.appendingPathComponent(candidate.artifactName)
            try artifact.write(to: artifactURL, options: .atomic)
            return DownloadedUpdate(candidate: candidate, artifactURL: artifactURL)
        } catch let failure as UpdateFailure {
            try? FileManager.default.removeItem(at: directory)
            throw failure
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw UpdateFailure.unableToSave
        }
    }
}

private extension UpdateCheckResult {
    static func availableOrCurrent(_ candidate: UpdateCandidate?) -> UpdateCheckResult {
        if let candidate { return .available(candidate) }
        return .current
    }
}

private extension ProcessInfo {
    var machineArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unsupported"
        #endif
    }
}
