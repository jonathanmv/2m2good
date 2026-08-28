import SwiftUI

struct PauseScreenControl: Equatable {
    enum Action: Equatable {
        case collapse
        case restore
    }

    let action: Action
    let title: String
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityValue: String?
    let accessibilityHint: String
    let keyboardShortcut: KeyboardShortcut?

    static let collapse = PauseScreenControl(
        action: .collapse,
        title: "Collapse pause screen",
        systemImage: "chevron.up",
        accessibilityLabel: "Collapse pause screen",
        accessibilityValue: nil,
        accessibilityHint: "Collapse the pause choices and return to the floating orb without changing this pause decision",
        keyboardShortcut: KeyboardShortcut.cancelAction
    )

    static let restore = PauseScreenControl(
        action: .restore,
        title: "Show pause choices",
        systemImage: "pause.circle",
        accessibilityLabel: "Pause waiting. Show pause choices.",
        accessibilityValue: "Pause choices are hidden",
        accessibilityHint: "Click to restore the pause screen without changing your pause decision",
        keyboardShortcut: nil
    )
}
