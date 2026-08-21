import Foundation

enum CompletionKey: Equatable {
    case enter
    case other

    static func classify(characters: String?, keyCode: UInt16) -> CompletionKey {
        if keyCode == 36 || keyCode == 76 || characters == "\r" || characters == "\n" {
            return .enter
        }
        return .other
    }
}

struct CompletionDismissalState {
    static let delaySeconds: TimeInterval = 10

    private(set) var generation = 0

    mutating func begin() -> Int {
        generation += 1
        return generation
    }

    mutating func cancel() {
        generation += 1
    }

    func isCurrent(_ token: Int) -> Bool {
        token == generation
    }
}

enum CompletionDismissalPolicy {
    static func shouldDismiss(
        isCompletionVisible: Bool,
        characters: String?,
        keyCode: UInt16
    ) -> Bool {
        isCompletionVisible
            && CompletionKey.classify(characters: characters, keyCode: keyCode) == .enter
    }
}
