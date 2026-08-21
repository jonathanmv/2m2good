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

enum BodyFocus: String, CaseIterable, Hashable {
    case neckShoulders
    case upperBackPosture
    case chestSideBody
    case trunkMobility
    case handsWristsForearms
    case lowerLegsFeetAnkles
    case breathRelaxation
    case eyesFace
}

struct BreakRoutine: Identifiable, Equatable {
    let id: String
    let title: String
    let invitation: String
    let focuses: Set<BodyFocus>
    let steps: [RoutineStep]

    var duration: Int { steps.reduce(0) { $0 + $1.duration } }

    static let all: [BreakRoutine] = [
        BreakRoutine(
            id: "neck-shoulders",
            title: "Neck + shoulders",
            invitation: "A gentle reset for your neck and shoulders?",
            focuses: [.neckShoulders, .upperBackPosture, .breathRelaxation],
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
            focuses: [.eyesFace, .upperBackPosture, .neckShoulders],
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
            focuses: [.lowerLegsFeetAnkles, .upperBackPosture, .breathRelaxation],
            steps: [
                .init(title: "Stand", instruction: "Stand up in your own time. Use support if helpful. Stop if anything hurts.", duration: 15, motion: .rise),
                .init(title: "Shift", instruction: "Shift your weight slowly from one foot to the other.", duration: 25, motion: .sideToSide),
                .init(title: "Unwind", instruction: "Make a few easy shoulder circles. Keep your knees soft.", duration: 20, motion: .roll),
                .init(title: "Lengthen", instruction: "Grow a little taller through the crown of your head, then soften.", duration: 25, motion: .rise),
                .init(title: "Breathe", instruction: "Let your arms hang and take two comfortable breaths.", duration: 25, motion: .breathe),
                .init(title: "Settle", instruction: "Notice the floor under your feet. You are done.", duration: 10, motion: .still)
            ]
        ),
        BreakRoutine(
            id: "hands-wrists",
            title: "Hands + wrists",
            invitation: "A gentle reset for your hands and wrists?",
            focuses: [.handsWristsForearms],
            steps: [
                .init(title: "Unclench", instruction: "Let your hands rest loosely. Move gently, and stop if anything hurts.", duration: 15, motion: .breathe),
                .init(title: "Open and close", instruction: "Slowly open your hands wide, then let your fingers curl in.", duration: 20, motion: .blink),
                .init(title: "Wrist circles", instruction: "Make small, easy circles with both wrists.", duration: 20, motion: .roll),
                .init(title: "Change direction", instruction: "Circle the other way, keeping your forearms soft.", duration: 20, motion: .roll),
                .init(title: "Finger fan", instruction: "Spread your fingers comfortably, then release all effort.", duration: 25, motion: .breathe),
                .init(title: "Settle", instruction: "Let your hands feel heavy and take one easy breath.", duration: 20, motion: .still)
            ]
        ),
        BreakRoutine(
            id: "seated-twist",
            title: "Seated twist",
            invitation: "Want a slow seated twist and reset?",
            focuses: [.trunkMobility, .upperBackPosture],
            steps: [
                .init(title: "Sit tall", instruction: "Place both feet down. Move gently, and stop if anything hurts.", duration: 15, motion: .rise),
                .init(title: "Turn right", instruction: "Slowly turn your ribs to the right. Keep your hips facing forward.", duration: 25, motion: .sideToSide),
                .init(title: "Turn left", instruction: "Return through center, then slowly turn to the left.", duration: 25, motion: .sideToSide),
                .init(title: "Center", instruction: "Come back to center and let your shoulders soften.", duration: 20, motion: .breathe),
                .init(title: "Lengthen", instruction: "Let the crown of your head float upward without stiffening.", duration: 20, motion: .rise),
                .init(title: "Breathe", instruction: "Take one comfortable breath and release the twist.", duration: 15, motion: .breathe)
            ]
        ),
        BreakRoutine(
            id: "breathing-reset",
            title: "Breathing reset",
            invitation: "How about two quiet minutes to breathe and settle?",
            focuses: [.breathRelaxation],
            steps: [
                .init(title: "Arrive", instruction: "Settle into an easy position. Breathe gently, and stop if anything hurts or feels uncomfortable.", duration: 15, motion: .still),
                .init(title: "Easy inhale", instruction: "Let a comfortable breath come in without trying to make it bigger.", duration: 25, motion: .breathe),
                .init(title: "Easy exhale", instruction: "Let the breath leave slowly and allow your shoulders to drop.", duration: 25, motion: .breathe),
                .init(title: "Find a rhythm", instruction: "Continue at your own pace. Nothing to count or achieve.", duration: 25, motion: .breathe),
                .init(title: "Soften", instruction: "Unclench your jaw and notice the support beneath you.", duration: 20, motion: .still),
                .init(title: "Return", instruction: "Take one final natural breath, then return when ready.", duration: 10, motion: .breathe)
            ]
        ),
        BreakRoutine(
            id: "feet-ankles",
            title: "Feet + ankles",
            invitation: "A small seated reset for your feet and ankles?",
            focuses: [.lowerLegsFeetAnkles],
            steps: [
                .init(title: "Find the floor", instruction: "Sit securely with both feet supported. Move gently, and stop if anything hurts.", duration: 15, motion: .still),
                .init(title: "Heel and toe", instruction: "Slowly lift your heels, lower them, then lift your toes.", duration: 20, motion: .rise),
                .init(title: "Right ankle", instruction: "Lift one foot slightly and make small circles at the ankle.", duration: 20, motion: .roll),
                .init(title: "Left ankle", instruction: "Set it down, then make easy circles with the other ankle.", duration: 20, motion: .roll),
                .init(title: "Press and release", instruction: "Press both feet lightly into the floor, then let the effort go.", duration: 25, motion: .breathe),
                .init(title: "Settle", instruction: "Notice the support under both feet and take one breath.", duration: 20, motion: .still)
            ]
        ),
        BreakRoutine(
            id: "jaw-face",
            title: "Jaw + face",
            invitation: "Want a gentle reset for your jaw and face?",
            focuses: [.eyesFace, .breathRelaxation],
            steps: [
                .init(title: "Unclench", instruction: "Let your teeth part slightly. Move gently, and stop if anything hurts.", duration: 15, motion: .breathe),
                .init(title: "Soften the jaw", instruction: "Let your lower jaw feel heavy without forcing it open.", duration: 20, motion: .still),
                .init(title: "Small motion", instruction: "Move your jaw slowly a little from side to side.", duration: 20, motion: .sideToSide),
                .init(title: "Relax the eyes", instruction: "Blink softly and smooth the space around your eyes.", duration: 20, motion: .blink),
                .init(title: "Release the brow", instruction: "Let your forehead widen and your tongue rest easily.", duration: 25, motion: .breathe),
                .init(title: "Return", instruction: "Take a comfortable breath and keep a little softness in your face.", duration: 20, motion: .breathe)
            ]
        ),
        BreakRoutine(
            id: "upper-back",
            title: "Upper back",
            invitation: "A gentle upper-back reset?",
            focuses: [.upperBackPosture, .chestSideBody, .neckShoulders],
            steps: [
                .init(title: "Settle", instruction: "Sit or stand comfortably. Move gently, and stop if anything hurts.", duration: 15, motion: .breathe),
                .init(title: "Self-hug", instruction: "Wrap your arms loosely around yourself and let your upper back widen.", duration: 25, motion: .breathe),
                .init(title: "Reach forward", instruction: "Release the hug and reach both hands forward without straining.", duration: 20, motion: .rise),
                .init(title: "Open", instruction: "Let your arms open comfortably and keep your ribs quiet.", duration: 20, motion: .breathe),
                .init(title: "Shoulder circles", instruction: "Make a few slow shoulder circles and let the movement shrink.", duration: 25, motion: .roll),
                .init(title: "Return", instruction: "Rest your arms and take one easy breath.", duration: 15, motion: .still)
            ]
        ),
        BreakRoutine(
            id: "side-stretch",
            title: "Seated side stretch",
            invitation: "Want a quiet seated side stretch?",
            focuses: [.chestSideBody, .trunkMobility],
            steps: [
                .init(title: "Ground", instruction: "Sit securely with both feet down. Move gently, and stop if anything hurts.", duration: 15, motion: .still),
                .init(title: "Reach right", instruction: "Let one arm reach up and lean slightly to the right.", duration: 25, motion: .sideToSide),
                .init(title: "Reach left", instruction: "Return through center, change arms, and lean slightly left.", duration: 25, motion: .sideToSide),
                .init(title: "Low reach", instruction: "Lower both arms and let your fingertips reach gently toward the floor.", duration: 20, motion: .rise),
                .init(title: "Come back", instruction: "Slowly return upright and let your shoulders settle.", duration: 20, motion: .rise),
                .init(title: "Breathe", instruction: "Take one comfortable breath in the center.", duration: 15, motion: .breathe)
            ]
        )
    ]
}

enum RandomRoutineSelector {
    static func next(
        from routines: [BreakRoutine],
        currentRoutineID: String,
        chooseIndex: (Range<Int>) -> Int = { Int.random(in: $0) }
    ) -> BreakRoutine? {
        let alternatives = routines.filter { $0.id != currentRoutineID }
        guard !alternatives.isEmpty else { return nil }
        let index = chooseIndex(alternatives.indices)
        guard alternatives.indices.contains(index) else { return nil }
        return alternatives[index]
    }
}

enum BalancedRoutineSelector {
    static let completionWindowSize = 6

    static func suggestion(
        from routines: [BreakRoutine],
        completionHistory: [String]
    ) -> BreakRoutine? {
        guard !routines.isEmpty else { return nil }

        let recentRoutines = completionHistory
            .suffix(completionWindowSize)
            .compactMap { id in routines.first(where: { $0.id == id }) }
        let lastCompletedID = recentRoutines.last?.id
        let candidates = routines.count > 1
            ? routines.filter { $0.id != lastCompletedID }
            : routines
        let taggedCandidates = candidates.filter { !$0.focuses.isEmpty }

        guard !taggedCandidates.isEmpty else {
            return RoutineSelectionPolicy.suggestion(
                from: routines,
                pendingRoutineID: nil,
                lastCompletedRoutineID: lastCompletedID
            )
        }

        var counts = Dictionary(uniqueKeysWithValues: BodyFocus.allCases.map { ($0, 0) })
        for routine in recentRoutines {
            for focus in routine.focuses {
                counts[focus, default: 0] += 1
            }
        }

        return taggedCandidates.enumerated().min { left, right in
            score(for: left.element, counts: counts, libraryIndex: left.offset)
                < score(for: right.element, counts: counts, libraryIndex: right.offset)
        }?.element
    }

    private static func score(
        for routine: BreakRoutine,
        counts: [BodyFocus: Int],
        libraryIndex: Int
    ) -> SelectionScore {
        let focusCounts = routine.focuses.map { counts[$0, default: 0] }
        return SelectionScore(
            leastRecentAttention: focusCounts.min() ?? Int.max,
            averageRecentAttention: Double(focusCounts.reduce(0, +)) / Double(focusCounts.count),
            libraryIndex: libraryIndex
        )
    }

    private struct SelectionScore: Comparable {
        let leastRecentAttention: Int
        let averageRecentAttention: Double
        let libraryIndex: Int

        static func < (left: SelectionScore, right: SelectionScore) -> Bool {
            if left.leastRecentAttention != right.leastRecentAttention {
                return left.leastRecentAttention < right.leastRecentAttention
            }
            if left.averageRecentAttention != right.averageRecentAttention {
                return left.averageRecentAttention < right.averageRecentAttention
            }
            return left.libraryIndex < right.libraryIndex
        }
    }
}

enum RoutineSelectionPolicy {
    static func suggestion(
        from routines: [BreakRoutine],
        pendingRoutineID: String?,
        lastCompletedRoutineID: String?
    ) -> BreakRoutine? {
        guard !routines.isEmpty else { return nil }

        if let pendingRoutineID,
           let pending = routines.first(where: { $0.id == pendingRoutineID }) {
            return pending
        }

        if let lastCompletedRoutineID,
           let completedIndex = routines.firstIndex(where: { $0.id == lastCompletedRoutineID }) {
            return routines[(completedIndex + 1) % routines.count]
        }

        return routines[0]
    }
}

struct RoutineSelectionStore {
    private enum Key {
        static let pendingRoutineID = "routine.pendingID"
        static let lastCompletedRoutineID = "routine.lastCompletedID"
        static let recentCompletionHistory = "routine.recentCompletionHistory"
    }

    let defaults: UserDefaults

    func suggestion(from routines: [BreakRoutine]) -> BreakRoutine? {
        let history = completionHistory(from: routines)
        let pendingRoutineID = defaults.string(forKey: Key.pendingRoutineID)
        let pending = routines.first(where: {
            $0.id == pendingRoutineID && $0.id != history.last
        })
        let suggestion = pending ?? BalancedRoutineSelector.suggestion(
            from: routines,
            completionHistory: history
        )
        if let suggestion {
            defaults.set(suggestion.id, forKey: Key.pendingRoutineID)
        }
        return suggestion
    }

    func markCompleted(_ routine: BreakRoutine, among routines: [BreakRoutine] = BreakRoutine.all) {
        var history = completionHistory(from: routines)
        history.append(routine.id)
        history = Array(history.suffix(BalancedRoutineSelector.completionWindowSize))
        defaults.set(history, forKey: Key.recentCompletionHistory)
        defaults.set(routine.id, forKey: Key.lastCompletedRoutineID)
        defaults.removeObject(forKey: Key.pendingRoutineID)
    }

    private func completionHistory(from routines: [BreakRoutine]) -> [String] {
        let validIDs = Set(routines.map(\.id))
        let stored = defaults.stringArray(forKey: Key.recentCompletionHistory) ?? []
        let validStored = stored.filter { validIDs.contains($0) }
        if !validStored.isEmpty {
            return Array(validStored.suffix(BalancedRoutineSelector.completionWindowSize))
        }

        if let legacyLastCompleted = defaults.string(forKey: Key.lastCompletedRoutineID),
           validIDs.contains(legacyLastCompleted) {
            return [legacyLastCompleted]
        }
        return []
    }
}
