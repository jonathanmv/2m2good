import Foundation

struct PauseHistoryStore {
    static let completedPauseTimestampsKey = "pause.completedTimestamps"
    static let completedHistoryLimit = 24

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var completedPauseDates: [Date] {
        (defaults.array(forKey: Self.completedPauseTimestampsKey) as? [NSNumber])?
            .map(\.doubleValue)
            .filter(\.isFinite)
            .map(Date.init(timeIntervalSinceReferenceDate:)) ?? []
    }

    func recordCompletedPause(at date: Date) {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return }
        let timestamps = (completedPauseDates.map(\.timeIntervalSinceReferenceDate) + [date.timeIntervalSinceReferenceDate])
            .sorted()
            .suffix(Self.completedHistoryLimit)
            .map { NSNumber(value: $0) }
        defaults.set(Array(timestamps), forKey: Self.completedPauseTimestampsKey)
    }

    func lastCompletedPause(beforeOrAt date: Date) -> Date? {
        completedPauseDates
            .filter { $0 <= date }
            .max()
    }
}

enum PauseRelativeTimeFormatter {
    /// Uses fixed, compact English so the visible and VoiceOver strings are stable while
    /// the calendar day boundary still follows the user's local calendar and time zone.
    static func string(
        for completedAt: Date,
        relativeTo now: Date,
        calendar: Calendar = .current
    ) -> String? {
        guard completedAt <= now else { return nil }

        if calendar.isDate(completedAt, inSameDayAs: now) {
            let elapsed = max(0, now.timeIntervalSince(completedAt))
            if elapsed < 60 {
                return "just now"
            }
            if elapsed < 60 * 60 {
                return "\(max(1, Int(elapsed / 60)))m ago"
            }
            let fullHours = max(1, Int(elapsed / (60 * 60)))
            return "over \(fullHours)h ago"
        }

        let completedDay = calendar.startOfDay(for: completedAt)
        let currentDay = calendar.startOfDay(for: now)
        let dayDifference = calendar.dateComponents([.day], from: completedDay, to: currentDay).day ?? 0
        guard dayDifference > 0 else { return nil }

        switch dayDifference {
        case 1: return "yesterday"
        case 2: return "day before yesterday"
        default: return "\(dayDifference) days ago"
        }
    }
}
