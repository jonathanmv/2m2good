import SwiftUI

struct UpdateDialogView: View {
    let model: UpdateDialogModel
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color(red: 0.27, green: 0.55, blue: 0.49))
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(model.title)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(model.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(model.accessibilityProgressLabel ?? "Working")
            }

            HStack(spacing: 10) {
                if let secondaryButtonTitle = model.secondaryButtonTitle {
                    Button(secondaryButtonTitle, action: onSecondaryAction)
                        .buttonStyle(UpdateSecondaryButtonStyle())
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel(secondaryButtonTitle)
                }
                if let primaryButtonTitle = model.primaryButtonTitle {
                    Button(primaryButtonTitle, action: onPrimaryAction)
                        .buttonStyle(UpdatePrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel(primaryButtonTitle)
                        .accessibilityHint(primaryHint)
                }
            }
        }
        .padding(28)
        .frame(width: 370, height: model.showsProgress ? 210 : 190)
        .accessibilityElement(children: .contain)
    }

    private var iconName: String {
        switch model.phase {
        case .checking, .downloading, .installing: return "arrow.down.circle"
        case .available, .downloaded: return "arrow.down.circle.fill"
        case .current, .success: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        }
    }

    private var primaryHint: String {
        switch model.phase {
        case .available, .downloaded: return "Downloads and verifies the update, then installs it and relaunches the app"
        case .failed: return "Retries the update"
        case .current, .success: return "Closes this window"
        default: return ""
        }
    }
}

private struct UpdatePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.27, green: 0.55, blue: 0.49).opacity(configuration.isPressed ? 0.75 : 1))
            )
    }
}

private struct UpdateSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary.opacity(0.76))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.055))
            )
    }
}
