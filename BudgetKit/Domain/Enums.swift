import Foundation

public enum Frequency: String, Codable, CaseIterable {
    case monthly
    case punctual

    public var label: String {
        switch self {
        case .monthly:  return NSLocalizedString("Mensuelle", comment: "")
        case .punctual: return NSLocalizedString("Ponctuelle", comment: "")
        }
    }
}

public enum SyncStatus: String, Codable {
    case local
    case synced
    case pendingUpload
    case pendingDelete
}

public enum ExpenseStatus: String, Codable, CaseIterable {
    case real
    case planned

    public var label: String {
        switch self {
        case .real:    return NSLocalizedString("Réel", comment: "")
        case .planned: return NSLocalizedString("Prévu", comment: "")
        }
    }
}

extension Calendar {
    public func startOfMonth(for date: Date) -> Date {
        // Repli sûr : `date(from:)` peut renvoyer nil (dates extrêmes, payload serveur malformé).
        // Un crash ici serait atteignable depuis la sync → on retombe sur le début du jour.
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}
