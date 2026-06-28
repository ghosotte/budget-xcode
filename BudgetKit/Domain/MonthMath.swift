import Foundation

/// Centralized month/day arithmetic that uses a fixed gregorian calendar in UTC,
/// so that month boundaries are stable across timezones and DST shifts.
/// All server payloads use Y-m-d / Y-m strings in UTC convention.
public enum MonthMath {
    public static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return cal
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    public static func parseMonth(_ raw: String) -> Date? {
        monthFormatter.date(from: raw)
    }

    public static func parseDate(_ raw: String) -> Date? {
        dayFormatter.date(from: raw)
    }

    public static func monthString(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }

    public static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
