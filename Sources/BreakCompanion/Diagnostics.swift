import Foundation

enum ActiveUsePath: Equatable {
    case accumulating
    case waitingForActivity
    case scheduled
    case pendingOffer
    case settings
    case routine
    case complete

    var label: String {
        switch self {
        case .accumulating: return "accumulating active use"
        case .waitingForActivity: return "waiting for active use"
        case .scheduled: return "scheduled check-in"
        case .pendingOffer: return "pending offer"
        case .settings: return "settings open"
        case .routine: return "routine in progress"
        case .complete: return "completion screen"
        }
    }
}

enum PendingOfferPresentation: Equatable {
    case notPending
    case visibleChoices
    case collapsedOrb

    var label: String {
        switch self {
        case .notPending: return "no pending offer"
        case .visibleChoices: return "visible pause choices"
        case .collapsedOrb: return "collapsed pending orb"
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
    let pendingOfferPresentation: PendingOfferPresentation

    init(
        cadence: Cadence,
        selectedAreas: [BodyArea],
        mode: String,
        activeUsePath: ActiveUsePath,
        pendingOfferPresentation: PendingOfferPresentation = .notPending
    ) {
        self.cadence = cadence
        self.selectedAreas = selectedAreas
        self.mode = mode
        self.activeUsePath = activeUsePath
        self.pendingOfferPresentation = pendingOfferPresentation
    }

    var report: String {
        let areaDescription = selectedAreas.isEmpty
            ? "balanced mix"
            : selectedAreas.map(\.label).joined(separator: ", ")
        return [
            ProductIdentity.diagnosticsIdentity,
            "cadence: \(cadence.label)",
            "body areas: \(areaDescription)",
            "mode: \(mode)",
            "active-use path: \(activeUsePath.label)",
            "offer presentation: \(pendingOfferPresentation.label)"
        ].joined(separator: "\n")
    }
}
