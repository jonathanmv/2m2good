import SwiftUI

struct CompanionView: View {
    @ObservedObject var store: CompanionStore
    @State private var hovered = false
    @State private var draftAreas: Set<BodyArea> = []

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: store.mode == .idle ? 28 : 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: store.mode == .idle ? 28 : 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.7)
                }

            switch store.mode {
            case .idle:
                idleView
            case .setup, .configuration:
                areaConfigurationView
            case .checkIn:
                checkInView
            case .routine:
                routineView
            case .complete:
                completionView
            }
        }
        .padding(8)
        .background(Color.clear)
        .animation(.spring(response: 0.45, dampingFraction: 0.84), value: store.mode)
    }

    private var idleView: some View {
        CompanionOrb(
            motion: .breathe,
            warmth: 0.28,
            active: hovered,
            progressColor: BreakProgress.color(at: store.checkInProgress)
        )
            .frame(width: 58, height: 58)
            .padding(10)
            .overlay {
                OrbPointerInteraction(onTap: store.offerBreakNow)
            }
        .onHover { hovered = $0 }
        .help("\(ProductIdentity.name) — click for a pause")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ProductIdentity.name). Offer a wellbeing break now.")
        .accessibilityValue(store.checkInAccessibilityValue)
        .accessibilityHint("Click to offer a two-minute standing reset")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.offerBreakNow() }
    }

    private var areaConfigurationView: some View {
        ScrollView {
            areaConfigurationContent
                .padding(23)
        }
        .onAppear { draftAreas = store.selectedAreas }
    }

    private var areaConfigurationContent: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                CompanionOrb(motion: .breathe, warmth: 0.72, active: true)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.mode == .setup ? "A small setup first" : "Body areas")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("Choose one or more areas for your standing reset. You can change this from the menu bar.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 7) {
                ForEach(Array(BodyArea.allCases.enumerated()), id: \.element) { index, area in
                    Button {
                        toggle(area)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(area.label)
                                    .font(.system(size: 14, weight: .medium))
                                Text(area.setupDescription)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: draftAreas.contains(area) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(draftAreas.contains(area) ? Color(red: 0.27, green: 0.55, blue: 0.49) : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(AreaOptionButtonStyle(selected: draftAreas.contains(area)))
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                    .accessibilityValue(draftAreas.contains(area) ? "Selected" : "Not selected")
                    .accessibilityHint("Press \(index + 1) to turn this area on or off")
                }
            }

            Text("Move gently, stay in a comfortable range, and stop if anything hurts or you feel unwell. This is a standing reset.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Save areas") {
                store.saveSelectedAreas(draftAreas)
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(draftAreas.isEmpty)
            .opacity(draftAreas.isEmpty ? 0.5 : 1)

            if store.offersBalancedChoice {
                Button(store.mode == .setup ? "Use balanced for now" : "Use balanced instead", action: store.continueWithBalancedDefaults)
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut("b", modifiers: .command)
                    .accessibilityHint("Press Command B to use the existing balanced movement selection without choosing an area")
            }

            if store.mode == .configuration {
                Button("Cancel", action: store.cancelAreaConfiguration)
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func toggle(_ area: BodyArea) {
        if draftAreas.contains(area) {
            draftAreas.remove(area)
        } else {
            draftAreas.insert(area)
        }
    }

    private var checkInView: some View {
        VStack(spacing: 17) {
            HStack(spacing: 14) {
                CompanionOrb(motion: .breathe, warmth: 0.9, active: true)
                    .frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 5) {
                    Text("A small pause?")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text(store.routine.invitation)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if let explanation = store.activityRecoveryExplanation {
                Text(explanation)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 0.24, green: 0.42, blue: 0.38))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                checkInControls
            } else if let status = store.statusText {
                Text(status)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 0.24, green: 0.42, blue: 0.38))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                checkInControls
            }
        }
        .padding(25)
    }

    private var checkInControls: some View {
        VStack(spacing: 10) {
            Button("Start  ·  2 min", action: store.startRoutine)
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            HStack(spacing: 9) {
                Button("Later", action: { store.postpone(minutes: 60) })
                Button("Tomorrow", action: store.postponeUntilTomorrow)
            }
            .buttonStyle(QuietButtonStyle())

        }
    }

    private var routineView: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.routine.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(store.currentStep.title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                }
                Spacer()
                Text(timeString(store.remainingSeconds))
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            CompanionOrb(motion: store.currentStep.motion, warmth: 0.84, active: !store.isPaused)
                .frame(width: 92, height: 92)

            Text(store.currentStep.instruction)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 39)

            ProgressView(value: store.progress)
                .tint(Color(red: 0.46, green: 0.67, blue: 0.60))

            HStack(spacing: 10) {
                Button(store.isPaused ? "Resume" : "Pause", action: store.togglePause)
                    .onHover { if $0 { store.noteCompanionInteraction() } }
                Button("Next", action: store.nextRoutine)
                    .onHover { if $0 { store.noteCompanionInteraction() } }
                Button("End", action: store.endRoutine)
                    .onHover { if $0 { store.noteCompanionInteraction() } }
            }
            .buttonStyle(QuietButtonStyle())
        }
        .padding(25)
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            CompanionOrb(motion: .breathe, warmth: 0.68, active: true)
                .frame(width: 76, height: 76)
            Text("That’s it.")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
            Text("Welcome back.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Button("Done", action: store.dismissCompletion)
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(25)
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct CompanionOrb: View {
    let motion: MotionCue
    let warmth: Double
    let active: Bool
    var progressColor: OrbProgressColor? = nil
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 11, y: 5)

            HStack(spacing: 9) {
                Capsule().fill(Color.white.opacity(0.83)).frame(width: 5, height: animate && motion == .blink ? 2 : 9)
                Capsule().fill(Color.white.opacity(0.83)).frame(width: 5, height: animate && motion == .blink ? 2 : 9)
            }
            .offset(y: -2)
        }
        .scaleEffect(scale)
        .rotationEffect(rotation)
        .offset(x: horizontalOffset, y: verticalOffset)
        .onAppear { beginAnimation() }
        .onChange(of: motion) { _, _ in beginAnimation() }
        .onChange(of: active) { _, _ in beginAnimation() }
        .animation(.linear(duration: 1), value: progressColor)
    }

    private var gradientColors: [Color] {
        guard let progressColor else {
            return [
                Color(red: 0.48 + 0.22 * warmth, green: 0.72, blue: 0.66 - 0.16 * warmth),
                Color(red: 0.32 + 0.30 * warmth, green: 0.56 + 0.12 * warmth, blue: 0.65)
            ]
        }

        return [
            Color(
                red: min(1, progressColor.red + 0.08),
                green: min(1, progressColor.green + 0.07),
                blue: min(1, progressColor.blue + 0.06)
            ),
            Color(
                red: progressColor.red * 0.82,
                green: progressColor.green * 0.82,
                blue: progressColor.blue * 0.82
            )
        ]
    }

    private var scale: CGFloat {
        guard active else { return 1 }
        switch motion {
        case .breathe: return animate ? 1.08 : 0.94
        case .rise: return animate ? 1.06 : 0.97
        default: return 1
        }
    }

    private var rotation: Angle {
        guard active else { return .zero }
        switch motion {
        case .roll: return .degrees(animate ? 7 : -7)
        default: return .zero
        }
    }

    private var horizontalOffset: CGFloat {
        guard active, motion == .sideToSide else { return 0 }
        return animate ? 9 : -9
    }

    private var verticalOffset: CGFloat {
        guard active, motion == .rise else { return 0 }
        return animate ? -5 : 5
    }

    private func beginAnimation() {
        animate = false
        guard active else { return }
        let duration = motion == .blink ? 1.8 : 2.5
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            animate = true
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.27, green: 0.55, blue: 0.49).opacity(configuration.isPressed ? 0.75 : 1))
            )
    }
}

private struct AreaOptionButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : selected ? 0.08 : 0.045))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(selected ? 0.16 : 0.06), lineWidth: 0.7)
            }
    }
}

private struct QuietButtonStyle: ButtonStyle {
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
