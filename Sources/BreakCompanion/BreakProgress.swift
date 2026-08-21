import Foundation

struct ScheduledCheckInWindow: Equatable {
    let startedAt: Date
    let dueAt: Date
}

struct OrbProgressColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
}

enum BreakProgress {
    private static let beginningColor = OrbProgressColor(red: 0.30, green: 0.68, blue: 0.52)
    private static let midpointColor = OrbProgressColor(red: 0.88, green: 0.58, blue: 0.28)
    private static let dueColor = OrbProgressColor(red: 0.78, green: 0.34, blue: 0.32)

    static func value(
        activeSeconds: TimeInterval,
        activeInterval: TimeInterval,
        scheduledWindow: ScheduledCheckInWindow?,
        now: Date
    ) -> Double {
        if let scheduledWindow {
            let duration = max(1, scheduledWindow.dueAt.timeIntervalSince(scheduledWindow.startedAt))
            return clamp(now.timeIntervalSince(scheduledWindow.startedAt) / duration)
        }

        return clamp(activeSeconds / max(1, activeInterval))
    }

    static func remainingSeconds(
        activeSeconds: TimeInterval,
        activeInterval: TimeInterval,
        scheduledWindow: ScheduledCheckInWindow?,
        now: Date
    ) -> TimeInterval {
        if let scheduledWindow {
            return max(0, scheduledWindow.dueAt.timeIntervalSince(now))
        }

        return max(0, activeInterval - activeSeconds)
    }

    static func color(at progress: Double) -> OrbProgressColor {
        let progress = clamp(progress)
        if progress == 0 { return beginningColor }
        if progress == 0.5 { return midpointColor }
        if progress == 1 { return dueColor }
        if progress <= 0.5 {
            return interpolate(from: beginningColor, to: midpointColor, fraction: progress * 2)
        }
        return interpolate(from: midpointColor, to: dueColor, fraction: (progress - 0.5) * 2)
    }

    static func accessibilityValue(progress: Double, remainingSeconds: TimeInterval) -> String {
        let percent = Int((clamp(progress) * 100).rounded())
        let remainingSeconds = max(0, remainingSeconds)

        if remainingSeconds == 0 {
            return "Next break is due now. \(percent) percent of the interval has elapsed."
        }
        if remainingSeconds < 120 {
            let seconds = Int(remainingSeconds.rounded(.up))
            return "Next break in about \(seconds) seconds. \(percent) percent of the interval has elapsed."
        }

        let minutes = Int((remainingSeconds / 60).rounded(.up))
        return "Next break in about \(minutes) minutes. \(percent) percent of the interval has elapsed."
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func interpolate(
        from start: OrbProgressColor,
        to end: OrbProgressColor,
        fraction: Double
    ) -> OrbProgressColor {
        OrbProgressColor(
            red: start.red + (end.red - start.red) * fraction,
            green: start.green + (end.green - start.green) * fraction,
            blue: start.blue + (end.blue - start.blue) * fraction
        )
    }
}
