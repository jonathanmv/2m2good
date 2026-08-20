import Foundation

enum SelfCheck {
    static func run() -> Bool {
        var failures: [String] = []

        if BreakRoutine.all.count != 3 {
            failures.append("expected three routines")
        }
        for routine in BreakRoutine.all {
            if routine.duration != 120 {
                failures.append("\(routine.title) lasts \(routine.duration), not 120 seconds")
            }
            let script = routine.steps.map(\.instruction).joined(separator: " ").lowercased()
            if !script.contains("stop if anything hurts") {
                failures.append("\(routine.title) is missing safety language")
            }
        }

        let voiceCases: [(String, VoiceCommand)] = [
            ("yes, let's start", .start),
            ("maybe in 20 minutes", .later(minutes: 20)),
            ("maybe in twenty minutes", .later(minutes: 20)),
            ("try again in an hour", .later(minutes: 60)),
            ("two hours", .later(minutes: 120)),
            ("tomorrow please", .tomorrow)
        ]
        for (phrase, expected) in voiceCases where VoiceCommandParser.parse(phrase) != expected {
            failures.append("voice phrase failed: \(phrase)")
        }

        if failures.isEmpty {
            print("Self-check passed: routines, timing, safety language, and voice commands.")
            return true
        }

        failures.forEach { print("Self-check failed: \($0)") }
        return false
    }
}
