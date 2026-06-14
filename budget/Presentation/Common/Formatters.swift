import Foundation

enum AmountFormatter {

    static var currencySymbol: String {
        UserDefaults.standard.string(forKey: "currencySymbol") ?? "€"
    }

    private static let kpiFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private static let fullFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static func kpi(_ amount: Decimal, signed: Bool = false) -> String {
        let number = NSDecimalNumber(decimal: amount)
        let text = kpiFormatter.string(from: number) ?? "0"
        let sign = signed && amount > 0 ? "+" : ""
        return "\(sign)\(text) \(currencySymbol)"
    }

    static func full(_ amount: Decimal, signed: Bool = false) -> String {
        let number = NSDecimalNumber(decimal: amount)
        let text = fullFormatter.string(from: number) ?? "0,00"
        let sign = signed && amount > 0 ? "+" : ""
        return "\(sign)\(text) \(currencySymbol)"
    }
}

enum AppDateFormatter {

    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "dd/MM"
        return f
    }()

    private static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private static let daySection: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    static func dayMonth(_ date: Date) -> String {
        dayMonth.string(from: date)
    }

    static func monthYear(_ date: Date) -> String {
        monthYear.string(from: date).capitalized
    }

    static func daySection(_ date: Date) -> String {
        daySection.string(from: date).capitalized
    }
}
