import Foundation

enum Cadence: String, CaseIterable, Codable, Hashable {
    case twentyMinutes = "twenty-minutes"
    case oneHour = "one-hour"
    case threeHours = "three-hours"

    static let defaultCadence: Cadence = .oneHour

    var interval: TimeInterval {
        switch self {
        case .twentyMinutes: return 20 * 60
        case .oneHour: return 60 * 60
        case .threeHours: return 3 * 60 * 60
        }
    }

    var label: String {
        switch self {
        case .twentyMinutes: return "Every 20 minutes"
        case .oneHour: return "Every hour"
        case .threeHours: return "Every 3 hours"
        }
    }
}

struct CadencePreferences {
    static let selectedCadenceKey = "reset.cadence"
    static let legacyIntervalKey = "reset.intervalSeconds"
    private static let migrationKey = "reset.cadencePreferencesMigrated"

    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        migrateLegacyCadenceIfNeeded()
    }

    var selectedCadence: Cadence {
        guard let rawValue = defaults.string(forKey: Self.selectedCadenceKey),
              let cadence = Cadence(rawValue: rawValue) else {
            // Repair an invalid value as well as handling an older install with no key.
            defaults.set(Cadence.defaultCadence.rawValue, forKey: Self.selectedCadenceKey)
            return .defaultCadence
        }
        return cadence
    }

    func save(cadence: Cadence) {
        defaults.set(cadence.rawValue, forKey: Self.selectedCadenceKey)
        defaults.set(true, forKey: Self.migrationKey)
    }

    private func migrateLegacyCadenceIfNeeded() {
        guard !defaults.bool(forKey: Self.migrationKey) else { return }

        if defaults.object(forKey: Self.selectedCadenceKey) == nil {
            let legacyInterval = defaults.double(forKey: Self.legacyIntervalKey)
            if let cadence = Cadence.allCases.first(where: { $0.interval == legacyInterval }) {
                defaults.set(cadence.rawValue, forKey: Self.selectedCadenceKey)
            } else {
                // The first release had a one-hour interval but no cadence preference.
                // Persisting that effective default makes the migration explicit and stable.
                defaults.set(Cadence.defaultCadence.rawValue, forKey: Self.selectedCadenceKey)
            }
        } else if Cadence(rawValue: defaults.string(forKey: Self.selectedCadenceKey) ?? "") == nil {
            defaults.set(Cadence.defaultCadence.rawValue, forKey: Self.selectedCadenceKey)
        }
        defaults.set(true, forKey: Self.migrationKey)
    }
}
