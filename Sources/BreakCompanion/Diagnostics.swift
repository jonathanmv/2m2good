import Foundation

enum ActiveUsePath: Equatable {
    case accumulating
    case waitingForActivity
    case scheduled
    case otherwisePaused

    var label: String {
        switch self {
        case .accumulating: return "accumulating"
        case .waitingForActivity: return "waiting for activity"
        case .scheduled: return "scheduled"
        case .otherwisePaused: return "otherwise paused"
        }
    }
}

extension CompanionStore.Mode {
    var diagnosticLabel: String {
        switch self {
        case .idle: return "idle"
        case .setup: return "setup"
        case .configuration: return "settings"
        case .checkIn: return "check-in"
        case .routine: return "routine"
        case .complete: return "complete"
        }
    }
}

struct CompanionDiagnosticSnapshot: Equatable {
    let cadence: Cadence
    let selectedAreas: [BodyArea]
    let mode: String
    let activeUsePath: ActiveUsePath

    var report: String {
        let areaDescription = selectedAreas.isEmpty
            ? "balanced mix"
            : selectedAreas.map(\.label).joined(separator: ", ")
        return [
            ProductIdentity.diagnosticsIdentity,
            "cadence: \(cadence.label)",
            "body areas: \(areaDescription)",
            "mode: \(mode)",
            "active-use path: \(activeUsePath.label)"
        ].joined(separator: "\n")
    }
}
