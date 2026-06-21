import Foundation

/// Recherche globale de transactions côté serveur (FULLTEXT + filtres), scope foyer connecté.
/// Contrat : `GET /budget/transactions/search` — même envelope que les autres routes mobiles
/// (currency ISO, locale, montants en chaînes décimales). Assertion App Attest non requise (GET).
@MainActor
enum SearchService {

    enum TypeFilter: String, CaseIterable {
        case all, expenses, incomes

        var label: String {
            switch self {
            case .all:      return NSLocalizedString("Toutes", comment: "")
            case .expenses: return NSLocalizedString("Dépenses", comment: "")
            case .incomes:  return NSLocalizedString("Entrées", comment: "")
            }
        }
    }

    enum StatusFilter: String, CaseIterable {
        case all, real, planned

        var label: String {
            switch self {
            case .all:     return NSLocalizedString("Toutes", comment: "")
            case .real:    return NSLocalizedString("Réelles", comment: "")
            case .planned: return NSLocalizedString("Planifiées", comment: "")
            }
        }
    }

    // MARK: — DTO

    struct Response: Decodable {
        let success: Bool
        let currency: String
        let locale: String
        let total: Int
        let hasMore: Bool
        let summary: Summary
        let items: [Item]

        enum CodingKeys: String, CodingKey {
            case success, currency, locale, total, summary, items
            case hasMore = "has_more"
        }
    }

    struct Summary: Decodable {
        let expensesCount: Int
        let incomesCount: Int
        let expensesSum: String
        let incomesSum: String

        enum CodingKeys: String, CodingKey {
            case expensesCount = "expenses_count"
            case incomesCount = "incomes_count"
            case expensesSum = "expenses_sum"
            case incomesSum = "incomes_sum"
        }

        var expensesTotal: Decimal { Decimal(string: expensesSum) ?? 0 }
        var incomesTotal: Decimal { Decimal(string: incomesSum) ?? 0 }
    }

    struct Item: Decodable, Identifiable {
        let serverId: Int
        let type: String
        let label: String
        let amount: String
        let date: String
        let status: String
        let categoryName: String?
        let categoryEmoji: String?

        enum CodingKeys: String, CodingKey {
            case serverId = "id"
            case type, label, amount, date, status
            case categoryName = "category_name"
            case categoryEmoji = "category_emoji"
        }

        // id expense/income vivent dans des espaces séparés → combiner pour unicité dans la liste.
        var id: String { "\(type)-\(serverId)" }

        var isIncome: Bool { type == "income" }

        /// Montant signé pour affichage : dépense négative, entrée positive.
        var signedAmount: Decimal {
            let value = Decimal(string: amount) ?? 0
            return isIncome ? value : -value
        }

        var statusEnum: ExpenseStatus { ExpenseStatus(rawValue: status) ?? .real }

        var parsedDate: Date? { Self.dateParser.date(from: date) }

        private static let dateParser: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()
    }

    // MARK: — Appel

    static func search(
        q: String,
        type: TypeFilter,
        status: StatusFilter,
        amountMin: Decimal?,
        amountMax: Decimal?,
        dateFrom: Date?,
        dateTo: Date?,
        limit: Int,
        offset: Int
    ) async throws -> Response {
        var query: [String: String] = [
            "limit": String(limit),
            "offset": String(offset),
        ]
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { query["q"] = trimmed }
        if type != .all { query["type"] = type.rawValue }
        if status != .all { query["status"] = status.rawValue }
        if let amountMin { query["amount_min"] = decimalParam(amountMin) }
        if let amountMax { query["amount_max"] = decimalParam(amountMax) }
        if let dateFrom { query["date_from"] = dateParam(dateFrom) }
        if let dateTo { query["date_to"] = dateParam(dateTo) }

        return try await APIClient.shared.send(
            Response.self,
            method: "GET",
            path: "/budget/transactions/search",
            query: query
        )
    }

    // MARK: — Helpers

    // Decimal.description utilise toujours "." sans séparateur de milliers → compatible is_numeric côté PHP.
    private static func decimalParam(_ value: Decimal) -> String { "\(value)" }

    private static func dateParam(_ date: Date) -> String { dateParamFormatter.string(from: date) }

    private static let dateParamFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
