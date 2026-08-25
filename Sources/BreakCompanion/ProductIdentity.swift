import Foundation

struct SemanticVersion: Hashable, Comparable, Codable, CustomStringConvertible, Sendable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [Identifier]
    let buildMetadata: [String]

    enum Identifier: Hashable, Codable, Sendable {
        case numeric(Int)
        case text(String)

        fileprivate var sortKey: (isNumeric: Bool, numeric: Int, text: String) {
            switch self {
            case .numeric(let value): return (true, value, "")
            case .text(let value): return (false, 0, value)
            }
        }
    }

    init(
        major: Int,
        minor: Int,
        patch: Int,
        prerelease: [Identifier] = [],
        buildMetadata: [String] = []
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.buildMetadata = buildMetadata
    }

    init?(tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.first == "v" || trimmed.first == "V"
            ? String(trimmed.dropFirst())
            : trimmed
        let buildParts = withoutPrefix.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard buildParts.count <= 2 else { return nil }
        let coreAndPrerelease = String(buildParts[0])
        let build = buildParts.count == 2 ? String(buildParts[1]).split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        guard build.allSatisfy(Self.isValidIdentifier) else { return nil }

        let prereleaseParts = coreAndPrerelease.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = prereleaseParts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3,
              core.allSatisfy(Self.isValidNumericComponent),
              let major = Int(core[0]),
              let minor = Int(core[1]),
              let patch = Int(core[2]) else { return nil }

        let prerelease = prereleaseParts.count == 2
            ? prereleaseParts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            : []
        guard prerelease.allSatisfy(Self.isValidIdentifier),
              !prerelease.contains(where: { $0.allSatisfy(\.isNumber) && $0.count > 1 && $0.first == "0" }) else {
            return nil
        }
        self.init(
            major: major,
            minor: minor,
            patch: patch,
            prerelease: prerelease.map(Self.identifier),
            buildMetadata: build
        )
    }

    var description: String {
        var result = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty {
            result += "-" + prerelease.map(Self.identifierDescription).joined(separator: ".")
        }
        if !buildMetadata.isEmpty {
            result += "+" + buildMetadata.joined(separator: ".")
        }
        return result
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty
        }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) {
            if left == right { continue }
            let leftKey = left.sortKey
            let rightKey = right.sortKey
            if leftKey.isNumeric != rightKey.isNumeric { return leftKey.isNumeric }
            if leftKey.isNumeric { return leftKey.numeric < rightKey.numeric }
            return leftKey.text < rightKey.text
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func identifier(_ value: String) -> Identifier {
        if let number = Int(value), !value.isEmpty, value.allSatisfy(\.isNumber) {
            return .numeric(number)
        }
        return .text(value)
    }

    private static func identifierDescription(_ identifier: Identifier) -> String {
        switch identifier {
        case .numeric(let value): return String(value)
        case .text(let value): return value
        }
    }

    private static func isValidNumericComponent(_ value: Substring) -> Bool {
        let text = String(value)
        return !text.isEmpty && text.allSatisfy(\.isNumber) && (text == "0" || text.first != "0")
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isNumber || $0.isLetter || $0 == "-" }
    }
}

enum ProductIdentity {
    static let name = "2m2better"

    // This is the sole semantic-version source of truth. The packaging script
    // reads this declaration when it materializes CFBundleShortVersionString
    // and release asset names; the app and updater use the same value directly.
    static let currentVersion = SemanticVersion(tag: "0.1.0")!
    static let buildNumber = "1"
    static let buildIdentity = "Developer Preview"

    static let configureAreasMenuTitle = "Choose body areas…"
    static let aboutMenuTitle = "About \(name)…"
    static let releaseRepository = "jonathanmv/2m2good"
    static let releaseAPIURL = URL(string: "https://api.github.com/repos/\(releaseRepository)/releases/latest")!
    static let releasesURL = URL(string: "https://github.com/\(releaseRepository)/releases")!

    static var versionDisplay: String { "Version \(currentVersion)" }
    static var buildDisplay: String { "Build \(buildNumber) · \(buildIdentity)" }
    static var diagnosticsIdentity: String { "\(name) \(currentVersion) (\(buildDisplay))" }
}
