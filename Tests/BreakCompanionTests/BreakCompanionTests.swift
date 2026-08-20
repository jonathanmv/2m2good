import XCTest
@testable import BreakCompanion

final class BreakCompanionTests: XCTestCase {
    func testEveryRoutineIsExactlyTwoMinutes() {
        XCTAssertEqual(BreakRoutine.all.count, 3)
        for routine in BreakRoutine.all {
            XCTAssertEqual(routine.duration, 120, "\(routine.title) should last two minutes")
            XCTAssertFalse(routine.steps.isEmpty)
        }
    }

    func testVoiceCommands() {
        XCTAssertEqual(VoiceCommandParser.parse("yes, let's start"), .start)
        XCTAssertEqual(VoiceCommandParser.parse("maybe in 20 minutes"), .later(minutes: 20))
        XCTAssertEqual(VoiceCommandParser.parse("maybe in twenty minutes"), .later(minutes: 20))
        XCTAssertEqual(VoiceCommandParser.parse("try again in an hour"), .later(minutes: 60))
        XCTAssertEqual(VoiceCommandParser.parse("two hours"), .later(minutes: 120))
        XCTAssertEqual(VoiceCommandParser.parse("tomorrow please"), .tomorrow)
    }

    func testRoutineSafetyLanguage() {
        for routine in BreakRoutine.all {
            let script = routine.steps.map(\.instruction).joined(separator: " ").lowercased()
            XCTAssertTrue(script.contains("stop if anything hurts"))
            XCTAssertTrue(script.contains("gentl") || script.contains("slow"))
        }
    }
}
