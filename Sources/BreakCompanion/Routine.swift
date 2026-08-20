import Foundation

struct RoutineStep: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let instruction: String
    let duration: Int
    let motion: MotionCue
}

enum MotionCue: Equatable {
    case breathe
    case sideToSide
    case roll
    case blink
    case rise
    case still
}

struct BreakRoutine: Identifiable, Equatable {
    let id: String
    let title: String
    let invitation: String
    let steps: [RoutineStep]

    var duration: Int { steps.reduce(0) { $0 + $1.duration } }

    static let all: [BreakRoutine] = [
        BreakRoutine(
            id: "neck-shoulders",
            title: "Neck + shoulders",
            invitation: "A gentle reset for your neck and shoulders?",
            steps: [
                .init(title: "Arrive", instruction: "Sit comfortably. Let your hands rest. Move gently, and stop if anything hurts.", duration: 15, motion: .breathe),
                .init(title: "Shoulder circles", instruction: "Slowly circle your shoulders back. Keep the movement easy.", duration: 20, motion: .roll),
                .init(title: "Side release", instruction: "Let one ear drift toward one shoulder. Return to center, then change sides.", duration: 25, motion: .sideToSide),
                .init(title: "Open", instruction: "Draw your shoulder blades softly together, then release.", duration: 25, motion: .breathe),
                .init(title: "Soften", instruction: "Let your chin float slightly down. Keep the back of your neck long.", duration: 20, motion: .still),
                .init(title: "One breath", instruction: "Take one unhurried breath, and let your shoulders settle.", duration: 15, motion: .breathe)
            ]
        ),
        BreakRoutine(
            id: "eyes-posture",
            title: "Eyes + posture",
            invitation: "How about two quiet minutes for your eyes and posture?",
            steps: [
                .init(title: "Look away", instruction: "Let your eyes leave the screen. Move gently, and stop if anything hurts.", duration: 15, motion: .still),
                .init(title: "Far focus", instruction: "Rest your gaze on something far away. No need to stare.", duration: 30, motion: .sideToSide),
                .init(title: "Blink", instruction: "Blink slowly a few times, then let your eyes soften.", duration: 15, motion: .blink),
                .init(title: "Stack gently", instruction: "Let your head float over your ribs and your shoulders feel wide.", duration: 30, motion: .rise),
                .init(title: "Soft focus", instruction: "Notice the edges of your view without moving your head.", duration: 20, motion: .breathe),
                .init(title: "Return", instruction: "Take an easy breath before you return to the screen.", duration: 10, motion: .breathe)
            ]
        ),
        BreakRoutine(
            id: "standing-reset",
            title: "Standing reset",
            invitation: "Want a gentle two-minute standing reset?",
            steps: [
                .init(title: "Stand", instruction: "Stand up in your own time. Use support if helpful. Stop if anything hurts.", duration: 15, motion: .rise),
                .init(title: "Shift", instruction: "Shift your weight slowly from one foot to the other.", duration: 25, motion: .sideToSide),
                .init(title: "Unwind", instruction: "Make a few easy shoulder circles. Keep your knees soft.", duration: 20, motion: .roll),
                .init(title: "Lengthen", instruction: "Grow a little taller through the crown of your head, then soften.", duration: 25, motion: .rise),
                .init(title: "Breathe", instruction: "Let your arms hang and take two comfortable breaths.", duration: 25, motion: .breathe),
                .init(title: "Settle", instruction: "Notice the floor under your feet. You are done.", duration: 10, motion: .still)
            ]
        )
    ]
}
