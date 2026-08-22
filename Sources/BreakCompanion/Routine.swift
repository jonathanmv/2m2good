import Foundation

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
    case lowerBack
    case handsWristsForearms
    case lowerLegsFeetAnkles
    case breathRelaxation
    case eyesFace
}

enum BodyArea: String, CaseIterable, Codable, Hashable {
    case lowerBack
    case neck
    case shoulders
    case handsWrists

    var label: String {
        switch self {
        case .lowerBack: return "Lower back"
        case .neck: return "Neck"
        case .shoulders: return "Shoulders"
        case .handsWrists: return "Hands + wrists"
        }
    }

    var invitationNoun: String {
        switch self {
        case .lowerBack: return "lower-back"
        case .neck: return "neck"
        case .shoulders: return "shoulder"
        case .handsWrists: return "hands-and-wrists"
        }
    }

    var setupDescription: String {
        switch self {
        case .lowerBack: return "Gentle changes of position"
        case .neck: return "Small, comfortable turns"
        case .shoulders: return "Easy rolls and opening"
        case .handsWrists: return "Open and soften your hands"
        }
    }
}

struct BreakMove: Identifiable, Equatable {
    let id: String
    let title: String
    let instruction: String
    let focuses: Set<BodyFocus>
    let bodyAreas: Set<BodyArea>
    let motion: MotionCue
    let supportsStanding: Bool
    let supportsSeated: Bool

    init(
        id: String,
        title: String,
        instruction: String,
        focuses: Set<BodyFocus>,
        bodyAreas: Set<BodyArea> = [],
        motion: MotionCue,
        supportsStanding: Bool,
        supportsSeated: Bool = false
    ) {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.focuses = focuses
        self.bodyAreas = bodyAreas
        self.motion = motion
        self.supportsStanding = supportsStanding
        self.supportsSeated = supportsSeated
    }
}

enum MoveLibrary {
    static let all: [BreakMove] = [
        .init(
            id: "shoulder-rolls",
            title: "Shoulder rolls",
            instruction: "Circle your shoulders slowly back, then let the circles become smaller.",
            focuses: [.neckShoulders, .upperBackPosture],
            bodyAreas: [.neck, .shoulders],
            motion: .roll,
            supportsStanding: true
        ),
        .init(
            id: "neck-turns",
            title: "Easy neck turns",
            instruction: "Turn your head a little right, return to center, then a little left. Keep it comfortable.",
            focuses: [.neckShoulders],
            bodyAreas: [.neck],
            motion: .sideToSide,
            supportsStanding: true
        ),
        .init(
            id: "overhead-reach",
            title: "Overhead reach",
            instruction: "If comfortable, float both arms upward. Lower them before your shoulders work hard.",
            focuses: [.chestSideBody, .upperBackPosture],
            bodyAreas: [.shoulders],
            motion: .rise,
            supportsStanding: true
        ),
        .init(
            id: "side-reach",
            title: "Side reach",
            instruction: "Reach one arm gently to the side at a low height, keeping your hips easy. Return through center and change sides.",
            focuses: [.chestSideBody, .trunkMobility, .lowerBack],
            bodyAreas: [.lowerBack],
            motion: .sideToSide,
            supportsStanding: true
        ),
        .init(
            id: "weight-shifts",
            title: "Weight shifts",
            instruction: "With support nearby if useful, shift your weight slowly from one foot to the other. Stay in a comfortable range.",
            focuses: [.lowerLegsFeetAnkles, .breathRelaxation, .lowerBack],
            bodyAreas: [.lowerBack],
            motion: .sideToSide,
            supportsStanding: true
        ),
        .init(
            id: "calf-raises",
            title: "Calf raises",
            instruction: "Holding support if helpful, lift your heels a little, lower slowly, and repeat easily.",
            focuses: [.lowerLegsFeetAnkles],
            motion: .rise,
            supportsStanding: true
        ),
        .init(
            id: "light-march",
            title: "Light march",
            instruction: "March gently in place with low steps. Keep the pace easy and the floor quiet.",
            focuses: [.lowerLegsFeetAnkles, .breathRelaxation],
            motion: .rise,
            supportsStanding: true
        ),
        .init(
            id: "ankle-circles",
            title: "Ankle circles",
            instruction: "Use support, lighten one foot, and draw small ankle circles. Change feet halfway.",
            focuses: [.lowerLegsFeetAnkles],
            motion: .roll,
            supportsStanding: true
        ),
        .init(
            id: "upper-back-open",
            title: "Upper-back opening",
            instruction: "Reach your hands forward and let your upper back widen, then release the reach.",
            focuses: [.upperBackPosture, .neckShoulders],
            bodyAreas: [.neck, .shoulders],
            motion: .breathe,
            supportsStanding: true
        ),
        .init(
            id: "hand-shake",
            title: "Hand shake",
            instruction: "Let your arms hang and gently shake out your hands. Keep your shoulders loose.",
            focuses: [.handsWristsForearms, .neckShoulders],
            bodyAreas: [.handsWrists, .shoulders],
            motion: .sideToSide,
            supportsStanding: true
        ),
        .init(
            id: "easy-breath",
            title: "Easy breath",
            instruction: "Let one comfortable breath arrive and leave without making it bigger.",
            focuses: [.breathRelaxation],
            motion: .breathe,
            supportsStanding: true
        ),
        .init(
            id: "far-gaze",
            title: "Far gaze",
            instruction: "Let your eyes leave the screen and rest softly on something farther away.",
            focuses: [.eyesFace, .upperBackPosture],
            motion: .still,
            supportsStanding: true
        ),
        .init(
            id: "heel-toe-rock",
            title: "Heel-to-toe rock",
            instruction: "With support if useful, rock gently toward your toes and back toward your heels.",
            focuses: [.lowerLegsFeetAnkles],
            motion: .sideToSide,
            supportsStanding: true
        ),
        .init(
            id: "chest-open",
            title: "Chest opening",
            instruction: "Let your arms open comfortably to the sides, then bring them forward again.",
            focuses: [.chestSideBody, .upperBackPosture],
            bodyAreas: [.shoulders],
            motion: .breathe,
            supportsStanding: true
        ),
        .init(
            id: "standing-twist",
            title: "Standing turn",
            instruction: "Keep your hips easy and turn your ribs a little right, then a little left. No need to go far.",
            focuses: [.trunkMobility, .upperBackPosture, .lowerBack],
            bodyAreas: [.lowerBack],
            motion: .sideToSide,
            supportsStanding: true
        ),
        .init(
            id: "elbow-circles",
            title: "Elbow circles",
            instruction: "Touch your fingertips lightly to your shoulders and draw small elbow circles.",
            focuses: [.neckShoulders, .upperBackPosture],
            bodyAreas: [.shoulders],
            motion: .roll,
            supportsStanding: true
        ),
        .init(
            id: "wrist-circles",
            title: "Wrist circles",
            instruction: "Make small easy circles with both wrists, then change direction.",
            focuses: [.handsWristsForearms],
            bodyAreas: [.handsWrists],
            motion: .roll,
            supportsStanding: true
        ),
        .init(
            id: "finger-fan",
            title: "Finger fan",
            instruction: "Open your fingers comfortably, soften them, and repeat without forcing the stretch.",
            focuses: [.handsWristsForearms],
            bodyAreas: [.handsWrists],
            motion: .blink,
            supportsStanding: true
        ),
        .init(
            id: "thumb-taps",
            title: "Thumb-to-finger taps",
            instruction: "Touch your thumb lightly to each fingertip, then change hands. Keep the touch easy.",
            focuses: [.handsWristsForearms],
            bodyAreas: [.handsWrists],
            motion: .blink,
            supportsStanding: true
        ),
        .init(
            id: "palm-turns",
            title: "Gentle palm turns",
            instruction: "Turn your palms slowly up and down. Keep your wrists loose and use a small range.",
            focuses: [.handsWristsForearms],
            bodyAreas: [.handsWrists],
            motion: .roll,
            supportsStanding: true
        ),
        .init(
            id: "jaw-soften",
            title: "Jaw soften",
            instruction: "Let your teeth part slightly and allow your jaw and tongue to feel unforced.",
            focuses: [.eyesFace, .breathRelaxation],
            motion: .still,
            supportsStanding: true
        ),
        .init(
            id: "slow-blinks",
            title: "Slow blinks",
            instruction: "Blink slowly a few times, then let your gaze stay wide and soft.",
            focuses: [.eyesFace, .breathRelaxation],
            motion: .blink,
            supportsStanding: true
        ),
        .init(
            id: "soft-knees",
            title: "Soften the knees",
            instruction: "Unlock your knees slightly, shift your weight gently, then soften again. Keep the range comfortable.",
            focuses: [.lowerLegsFeetAnkles, .upperBackPosture, .lowerBack],
            bodyAreas: [.lowerBack],
            motion: .rise,
            supportsStanding: true
        ),
        .init(
            id: "hip-shifts",
            title: "Easy hip shifts",
            instruction: "Shift your hips a small amount right and left while your feet stay grounded. Stay comfortable.",
            focuses: [.trunkMobility, .lowerLegsFeetAnkles, .lowerBack],
            bodyAreas: [.lowerBack],
            motion: .sideToSide,
            supportsStanding: true
        ),
        .init(
            id: "gentle-forward-back-shifts",
            title: "Gentle forward-and-back shifts",
            instruction: "Shift your weight a little forward and back while both feet stay grounded. Keep it comfortable.",
            focuses: [.trunkMobility, .lowerBack],
            bodyAreas: [.lowerBack],
            motion: .sideToSide,
            supportsStanding: true
        ),
        .init(
            id: "pelvic-shifts",
            title: "Small pelvic shifts",
            instruction: "Keep your feet easy and shift your pelvis a little right and left. Stay in a comfortable range.",
            focuses: [.trunkMobility, .lowerBack],
            bodyAreas: [.lowerBack],
            motion: .sideToSide,
            supportsStanding: true
        ),
        .init(
            id: "arm-sweep",
            title: "Arm sweep",
            instruction: "Sweep your arms forward and gently out to the sides, staying below any strain.",
            focuses: [.chestSideBody, .upperBackPosture],
            bodyAreas: [.shoulders],
            motion: .breathe,
            supportsStanding: true
        ),
        .init(
            id: "reach-and-release",
            title: "Reach and release",
            instruction: "Reach both hands forward without rounding hard, then let your arms fall loose.",
            focuses: [.upperBackPosture, .handsWristsForearms],
            bodyAreas: [.handsWrists, .shoulders],
            motion: .rise,
            supportsStanding: true
        )
    ]
}

struct RoutineStep: Identifiable, Equatable {
    let id: String
    let title: String
    let instruction: String
    let duration: Int
    let motion: MotionCue
}

struct BreakRoutine: Identifiable, Equatable {
    let id: String
    let title: String
    let invitation: String
    let focuses: Set<BodyFocus>
    let steps: [RoutineStep]

    var duration: Int { steps.reduce(0) { $0 + $1.duration } }
    var moveIDs: [String] { steps.map(\.id) }

    static func composed(
        from moves: [BreakMove],
        selectedAreas: Set<BodyArea> = []
    ) -> BreakRoutine? {
        guard moves.count == SessionComposer.sessionMoveCount,
              Set(moves.map(\.id)).count == moves.count,
              moves.allSatisfy(\.supportsStanding) else {
            return nil
        }

        let steps = moves.enumerated().map { index, move in
            let standingLead = index == 0
                ? "This is a standing reset. Stand when you’re ready, with support nearby if useful. Move gently, stay in a comfortable range, and stop if anything hurts or you feel unwell. "
                : ""
            return RoutineStep(
                id: move.id,
                title: move.title,
                instruction: standingLead + move.instruction,
                duration: SessionComposer.moveDuration,
                motion: move.motion
            )
        }
        return BreakRoutine(
            id: moves.map(\.id).joined(separator: "+"),
            title: title(for: selectedAreas),
            invitation: invitation(for: selectedAreas),
            focuses: Set(moves.flatMap(\.focuses)),
            steps: steps
        )
    }

    private static func title(for selectedAreas: Set<BodyArea>) -> String {
        guard selectedAreas.count == 1,
              let area = BodyArea.allCases.first(where: { selectedAreas.contains($0) }) else {
            return "Standing reset"
        }
        return "\(area.label) reset"
    }

    private static func invitation(for selectedAreas: Set<BodyArea>) -> String {
        let areas = BodyArea.allCases.filter { selectedAreas.contains($0) }
        guard !areas.isEmpty else { return "Ready to stand for a gentle two-minute reset?" }
        let nouns = areas.map(\.invitationNoun)
        if nouns.count == 1 {
            return "Want a gentle \(nouns[0]) reset?"
        }
        let list = nouns.dropLast().joined(separator: ", ") + " and " + nouns.last!
        return "Want a gentle reset for \(list)?"
    }

    static let fallback = composed(from: Array(MoveLibrary.all.prefix(SessionComposer.sessionMoveCount)))!
}

enum SessionComposer {
    static let sessionMoveCount = 6
    static let moveDuration = 20

    static func compose(
        from library: [BreakMove],
        recentShownMoveIDs: [String],
        recentCompletedMoveIDs: [String],
        excluding currentMoveIDs: Set<String> = [],
        selectedAreas: Set<BodyArea> = []
    ) -> BreakRoutine? {
        let uniqueLibrary = library.reduce(into: [BreakMove]()) { result, move in
            if !result.contains(where: { $0.id == move.id }) {
                result.append(move)
            }
        }
        guard uniqueLibrary.count >= sessionMoveCount else { return nil }

        let recentShown = Set(recentShownMoveIDs)
        var attention = Dictionary(uniqueKeysWithValues: BodyFocus.allCases.map { ($0, 0) })
        let movesByID = Dictionary(uniqueKeysWithValues: uniqueLibrary.map { ($0.id, $0) })
        for id in recentCompletedMoveIDs {
            for focus in movesByID[id]?.focuses ?? [] {
                attention[focus, default: 0] += 1
            }
        }

        let areaMatches = uniqueLibrary.filter {
            !$0.bodyAreas.isDisjoint(with: selectedAreas)
        }
        let targetAreaMatches = min(3, areaMatches.count)
        var selected: [BreakMove] = []
        var selectedAreaMatchCount = 0
        while selected.count < sessionMoveCount {
            let selectedIDs = Set(selected.map(\.id))
            let remaining = uniqueLibrary.enumerated().filter { !selectedIDs.contains($0.element.id) }
            let quotaCandidates = remaining.filter {
                !$0.element.bodyAreas.isDisjoint(with: selectedAreas)
                    && !currentMoveIDs.contains($0.element.id)
            }
            let candidates: [(offset: Int, element: BreakMove)]
            if selectedAreaMatchCount < targetAreaMatches, !quotaCandidates.isEmpty {
                candidates = quotaCandidates
            } else {
                candidates = remaining
            }
            guard let choice = candidates.min(by: { left, right in
                score(
                    for: left.element,
                    libraryIndex: left.offset,
                    attention: attention,
                    recentShown: recentShown,
                    currentMoveIDs: currentMoveIDs
                ) < score(
                    for: right.element,
                    libraryIndex: right.offset,
                    attention: attention,
                    recentShown: recentShown,
                    currentMoveIDs: currentMoveIDs
                )
            })?.element else {
                return nil
            }
            selected.append(choice)
            if !choice.bodyAreas.isDisjoint(with: selectedAreas) {
                selectedAreaMatchCount += 1
            }
            for focus in choice.focuses {
                attention[focus, default: 0] += 1
            }
        }

        return BreakRoutine.composed(from: selected, selectedAreas: selectedAreas)
    }

    private static func score(
        for move: BreakMove,
        libraryIndex: Int,
        attention: [BodyFocus: Int],
        recentShown: Set<String>,
        currentMoveIDs: Set<String>
    ) -> SelectionScore {
        let exclusionTier: Int
        if !recentShown.contains(move.id) && !currentMoveIDs.contains(move.id) {
            exclusionTier = 0
        } else if !currentMoveIDs.contains(move.id) {
            exclusionTier = 1
        } else {
            exclusionTier = 2
        }
        let counts = move.focuses.map { attention[$0, default: 0] }
        return SelectionScore(
            exclusionTier: exclusionTier,
            leastAttention: counts.min() ?? Int.max,
            averageAttention: counts.isEmpty
                ? Double.greatestFiniteMagnitude
                : Double(counts.reduce(0, +)) / Double(counts.count),
            libraryIndex: libraryIndex
        )
    }

    private struct SelectionScore: Comparable {
        let exclusionTier: Int
        let leastAttention: Int
        let averageAttention: Double
        let libraryIndex: Int

        static func < (left: SelectionScore, right: SelectionScore) -> Bool {
            if left.exclusionTier != right.exclusionTier {
                return left.exclusionTier < right.exclusionTier
            }
            if left.leastAttention != right.leastAttention {
                return left.leastAttention < right.leastAttention
            }
            if left.averageAttention != right.averageAttention {
                return left.averageAttention < right.averageAttention
            }
            return left.libraryIndex < right.libraryIndex
        }
    }
}

struct BodyAreaPreferences {
    static let selectedAreasKey = "reset.selectedBodyAreas"
    static let onboardingCompletedKey = "reset.bodyAreaOnboardingCompleted"
    static let legacyPreferredAreaKey = "reset.preferredBodyArea"
    private static let migrationKey = "reset.bodyAreaPreferencesMigrated"

    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        migrateLegacySelectionIfNeeded()
    }

    var selectedAreas: Set<BodyArea> {
        Set((defaults.stringArray(forKey: Self.selectedAreasKey) ?? []).compactMap(BodyArea.init(rawValue:)))
    }

    var onboardingCompleted: Bool {
        defaults.bool(forKey: Self.onboardingCompletedKey)
    }

    var shouldPresentFirstRunSetup: Bool {
        !onboardingCompleted && !hasExistingRoutineState
    }

    func save(selectedAreas: Set<BodyArea>) {
        let values = BodyArea.allCases
            .filter { selectedAreas.contains($0) }
            .map(\.rawValue)
        defaults.set(values, forKey: Self.selectedAreasKey)
        defaults.set(true, forKey: Self.onboardingCompletedKey)
    }

    func continueWithBalancedDefaults() {
        defaults.set([], forKey: Self.selectedAreasKey)
        defaults.set(true, forKey: Self.onboardingCompletedKey)
    }

    private var hasExistingRoutineState: Bool {
        [
            "session.pendingMoveIDs",
            "session.recentShownMoveIDs",
            "session.recentCompletedMoveIDs",
            "routine.pendingID",
            "routine.lastCompletedID",
            "routine.recentCompletionHistory"
        ].contains { defaults.object(forKey: $0) != nil }
    }

    private func migrateLegacySelectionIfNeeded() {
        guard !defaults.bool(forKey: Self.migrationKey) else { return }
        if defaults.object(forKey: Self.selectedAreasKey) == nil,
           let legacy = defaults.string(forKey: Self.legacyPreferredAreaKey),
           let area = BodyArea(rawValue: legacy) {
            defaults.set([area.rawValue], forKey: Self.selectedAreasKey)
            defaults.set(true, forKey: Self.onboardingCompletedKey)
        }
        defaults.set(true, forKey: Self.migrationKey)
    }
}

struct SessionSelectionStore {
    static let shownHistoryLimit = 18
    static let completedHistoryLimit = 24

    private enum Key {
        static let pendingMoveIDs = "session.pendingMoveIDs"
        static let pendingBodyAreas = "session.pendingBodyAreas"
        static let recentShownMoveIDs = "session.recentShownMoveIDs"
        static let recentCompletedMoveIDs = "session.recentCompletedMoveIDs"
        static let migratedLegacyState = "session.migratedLegacyRoutineState"
        static let legacyPendingRoutineID = "routine.pendingID"
        static let legacyLastCompletedRoutineID = "routine.lastCompletedID"
        static let legacyCompletionHistory = "routine.recentCompletionHistory"
    }

    let defaults: UserDefaults

    func suggestion(
        from moves: [BreakMove],
        selectedAreas: Set<BodyArea> = []
    ) -> BreakRoutine? {
        migrateLegacyStateIfNeeded()
        if let pending = pendingRoutine(from: moves, selectedAreas: selectedAreas) {
            return pending
        }
        guard let suggestion = SessionComposer.compose(
            from: moves,
            recentShownMoveIDs: recentShownMoveIDs(from: moves),
            recentCompletedMoveIDs: recentCompletedMoveIDs(from: moves),
            selectedAreas: selectedAreas
        ) else {
            return nil
        }
        persistAsShown(suggestion, selectedAreas: selectedAreas)
        return suggestion
    }

    func nextSession(
        after current: BreakRoutine,
        from moves: [BreakMove],
        selectedAreas: Set<BodyArea> = []
    ) -> BreakRoutine? {
        migrateLegacyStateIfNeeded()
        guard let suggestion = SessionComposer.compose(
            from: moves,
            recentShownMoveIDs: recentShownMoveIDs(from: moves),
            recentCompletedMoveIDs: recentCompletedMoveIDs(from: moves),
            excluding: Set(current.moveIDs),
            selectedAreas: selectedAreas
        ) else {
            return nil
        }
        persistAsShown(suggestion, selectedAreas: selectedAreas)
        return suggestion
    }

    func markCompleted(_ routine: BreakRoutine, among moves: [BreakMove] = MoveLibrary.all) {
        migrateLegacyStateIfNeeded()
        let validIDs = Set(moves.map(\.id))
        var history = recentCompletedMoveIDs(from: moves)
        history.append(contentsOf: routine.moveIDs.filter { validIDs.contains($0) })
        defaults.set(Array(history.suffix(Self.completedHistoryLimit)), forKey: Key.recentCompletedMoveIDs)
        defaults.removeObject(forKey: Key.pendingMoveIDs)
        defaults.removeObject(forKey: Key.pendingBodyAreas)
    }

    func clearPendingSession() {
        defaults.removeObject(forKey: Key.pendingMoveIDs)
        defaults.removeObject(forKey: Key.pendingBodyAreas)
    }

    private func pendingRoutine(
        from moves: [BreakMove],
        selectedAreas: Set<BodyArea>
    ) -> BreakRoutine? {
        let pendingIDs = defaults.stringArray(forKey: Key.pendingMoveIDs) ?? []
        guard pendingIDs.count == SessionComposer.sessionMoveCount,
              Set(pendingIDs).count == pendingIDs.count else {
            clearPendingSession()
            return nil
        }
        let storedAreas = Set(
            (defaults.stringArray(forKey: Key.pendingBodyAreas) ?? []).compactMap(BodyArea.init(rawValue:))
        )
        guard storedAreas == selectedAreas else {
            clearPendingSession()
            return nil
        }
        let movesByID = Dictionary(uniqueKeysWithValues: moves.map { ($0.id, $0) })
        let pendingMoves = pendingIDs.compactMap { movesByID[$0] }
        guard pendingMoves.count == pendingIDs.count else {
            clearPendingSession()
            return nil
        }
        return BreakRoutine.composed(from: pendingMoves, selectedAreas: selectedAreas)
    }

    private func persistAsShown(_ routine: BreakRoutine, selectedAreas: Set<BodyArea> = []) {
        var history = defaults.stringArray(forKey: Key.recentShownMoveIDs) ?? []
        history.append(contentsOf: routine.moveIDs)
        defaults.set(Array(history.suffix(Self.shownHistoryLimit)), forKey: Key.recentShownMoveIDs)
        defaults.set(routine.moveIDs, forKey: Key.pendingMoveIDs)
        defaults.set(
            BodyArea.allCases.filter { selectedAreas.contains($0) }.map(\.rawValue),
            forKey: Key.pendingBodyAreas
        )
    }

    private func recentShownMoveIDs(from moves: [BreakMove]) -> [String] {
        validHistory(for: Key.recentShownMoveIDs, from: moves, limit: Self.shownHistoryLimit)
    }

    private func recentCompletedMoveIDs(from moves: [BreakMove]) -> [String] {
        validHistory(for: Key.recentCompletedMoveIDs, from: moves, limit: Self.completedHistoryLimit)
    }

    private func validHistory(for key: String, from moves: [BreakMove], limit: Int) -> [String] {
        let validIDs = Set(moves.map(\.id))
        let stored = defaults.stringArray(forKey: key) ?? []
        return Array(stored.filter { validIDs.contains($0) }.suffix(limit))
    }

    private func migrateLegacyStateIfNeeded() {
        guard !defaults.bool(forKey: Key.migratedLegacyState) else { return }

        let legacyRoutineMoves: [String: [String]] = [
            "neck-shoulders": ["shoulder-rolls", "neck-turns", "upper-back-open"],
            "eyes-posture": ["far-gaze", "slow-blinks", "shoulder-rolls"],
            "standing-reset": ["weight-shifts", "calf-raises", "easy-breath"],
            "hands-wrists": ["hand-shake", "wrist-circles", "finger-fan"],
            "seated-twist": ["standing-twist", "upper-back-open", "easy-breath"],
            "breathing-reset": ["easy-breath", "jaw-soften", "slow-blinks"],
            "feet-ankles": ["heel-toe-rock", "ankle-circles", "calf-raises"],
            "jaw-face": ["jaw-soften", "slow-blinks", "easy-breath"],
            "upper-back": ["upper-back-open", "chest-open", "shoulder-rolls"],
            "side-stretch": ["side-reach", "overhead-reach", "arm-sweep"]
        ]
        var legacyIDs = defaults.stringArray(forKey: Key.legacyCompletionHistory) ?? []
        if legacyIDs.isEmpty,
           let last = defaults.string(forKey: Key.legacyLastCompletedRoutineID) {
            legacyIDs = [last]
        }
        let migrated = legacyIDs.flatMap { legacyRoutineMoves[$0] ?? [] }
        if !migrated.isEmpty {
            defaults.set(
                Array(migrated.suffix(Self.completedHistoryLimit)),
                forKey: Key.recentCompletedMoveIDs
            )
        }

        defaults.removeObject(forKey: Key.legacyPendingRoutineID)
        defaults.removeObject(forKey: Key.legacyLastCompletedRoutineID)
        defaults.removeObject(forKey: Key.legacyCompletionHistory)
        defaults.set(true, forKey: Key.migratedLegacyState)
    }
}
