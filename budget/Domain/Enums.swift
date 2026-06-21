import Foundation

enum Frequency: String, Codable, CaseIterable {
    case monthly
    case punctual

    var label: String {
        switch self {
        case .monthly:  return NSLocalizedString("Mensuelle", comment: "")
        case .punctual: return NSLocalizedString("Ponctuelle", comment: "")
        }
    }
}

enum SyncStatus: String, Codable {
    case local
    case synced
    case pendingUpload
    case pendingDelete
}

enum ExpenseStatus: String, Codable, CaseIterable {
    case real
    case planned

    var label: String {
        switch self {
        case .real:    return NSLocalizedString("Réel", comment: "")
        case .planned: return NSLocalizedString("Prévu", comment: "")
        }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date))!
    }
}
