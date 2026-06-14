import Foundation

@MainActor
enum HistoryService {

    struct Overview: Decodable, Equatable {
        let success: Bool
        let tab: String
        let from: String
        let to: String
        let autoFromDate: String?
        let firstTransactionDate: String?
        let monthsCount: Int
        let monthly: [MonthRow]
        let max: MonthRow?
        let min: MonthRow?
        let avg: String
        let categories: [CategoryRow]

        enum CodingKeys: String, CodingKey {
            case success, tab, from, to, monthly, max, min, avg, categories
            case autoFromDate = "auto_from_date"
            case firstTransactionDate = "first_transaction_date"
            case monthsCount = "months_count"
        }
    }

    struct MonthRow: Decodable, Equatable, Identifiable {
        let year: Int
        let month: Int
        let label: String
        let total: String

        var id: String { "\(year)-\(month)" }
        var decimalTotal: Decimal { Decimal(string: total) ?? 0 }
        var date: Date {
            Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
        }
    }

    struct CategoryRow: Decodable, Equatable, Identifiable {
        let id: Int?
        let name: String
        let emoji: String
        let total: String
        let avg: String
        let pct: Double
        let subcategories: [SubRow]

        var decimalTotal: Decimal { Decimal(string: total) ?? 0 }
        var decimalAvg: Decimal { Decimal(string: avg) ?? 0 }
    }

    struct SubRow: Decodable, Equatable, Identifiable {
        let id: Int?
        let name: String
        let emoji: String
        let total: String
        let avg: String

        var decimalTotal: Decimal { Decimal(string: total) ?? 0 }
        var decimalAvg: Decimal { Decimal(string: avg) ?? 0 }
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    static func fetchOverview(
        tab: String,
        from: Date?,
        to: Date? = nil,
        categories: [Int] = []
    ) async throws -> Overview {
        var query: [String: String] = ["tab": tab]
        if let from { query["from"] = dateFormatter.string(from: from) }
        if let to { query["to"] = dateFormatter.string(from: to) }
        if !categories.isEmpty {
            query["category_ids"] = categories.map(String.init).joined(separator: ",")
        }

        return try await APIClient.shared.send(
            Overview.self,
            method: "GET",
            path: "/budget/history/overview",
            query: query
        )
    }
}
