import Foundation

struct PauseScreenControl: Equatable {
    enum Action: Equatable {
        case collapse
        case restore
    }

    let action: Action
    let title: String
    let accessibilityLabel: String
    let accessibilityValue: String?
    let accessibilityHint: String

    static let collapse = PauseScreenControl(
        action: .collapse,
        title: "Hide pause screen",
        accessibilityLabel: "Collapse pause screen",
        accessibilityValue: nil,
        accessibilityHint: "Hide the pause choices and return to the floating orb without changing this pause decision"
    )

    static let restore = PauseScreenControl(
        action: .restore,
        title: "Show pause choices",
        accessibilityLabel: "Pause waiting. Show pause choices.",
        accessibilityValue: "Pause choices are hidden",
        accessibilityHint: "Click to restore the pause screen without changing your pause decision"
    )
}
