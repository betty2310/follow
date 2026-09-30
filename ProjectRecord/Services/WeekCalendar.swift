import Foundation

/// Calendar weeks, Monday–Sunday (docs/DECISIONS.md D11). Weeks are always derived from dates, never stored.
struct WeekID: Hashable, Comparable, Sendable {
    var year: Int   // ISO year-for-week-of-year
    var week: Int

    static func < (l: WeekID, r: WeekID) -> Bool { (l.year, l.week) < (r.year, r.week) }
}

enum WeekCalendar {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }()

    static func week(of date: Date) -> WeekID {
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return WeekID(year: c.yearForWeekOfYear!, week: c.weekOfYear!)
    }

    /// Monday 00:00 of the week containing `date`.
    static func startOfWeek(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)!.start
    }
}
