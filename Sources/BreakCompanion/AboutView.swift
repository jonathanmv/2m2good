import SwiftUI

struct AboutView: View {
    let onClose: () -> Void
    let onOpenReleases: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.52, green: 0.78, blue: 0.68),
                                Color(red: 0.29, green: 0.56, blue: 0.50)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.13), radius: 10, y: 5)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 29, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }

            VStack(spacing: 5) {
                Text(ProductIdentity.name)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("A small pause for returning to yourself.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text(ProductIdentity.versionDisplay)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Text(ProductIdentity.buildDisplay)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Private by design. Break timing and preferences stay on this Mac. There are no accounts, analytics, or usage telemetry. Update checks contact GitHub Releases only and send no activity data.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("GitHub Releases", action: onOpenReleases)
                    .buttonStyle(AboutSecondaryButtonStyle())
                Button("Done", action: onClose)
                    .buttonStyle(AboutPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 390, height: 430)
    }
}

private struct AboutPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 17)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.27, green: 0.55, blue: 0.49).opacity(configuration.isPressed ? 0.75 : 1))
            )
    }
}

private struct AboutSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary.opacity(0.76))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.055))
            )
    }
}
