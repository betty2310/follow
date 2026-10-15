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

extension WeekCalendar {
    /// Every day (00:00) of the day board (D36), oldest first: from the earliest of `dates`
    /// (or `minimumCount - 1` days before `now`, whichever is earlier) through today or the latest date.
    static func days(covering dates: [Date], now: Date = .now, minimumCount: Int = 14) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let floor = calendar.date(byAdding: .day, value: -(max(minimumCount, 1) - 1), to: today)!
        let first = min(dates.min().map(calendar.startOfDay) ?? floor, floor)
        let last = max(dates.max().map(calendar.startOfDay) ?? today, today)
        var result: [Date] = []
        var day = first
        while day <= last {
            result.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }
}

extension WeekCalendar {
    /// First day (00:00) of the month containing `date`.
    static func startOfMonth(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)!.start
    }

    /// Days to show in a month grid, oldest first: whole Mon–Sun weeks covering the month of `date`
    /// (so 28–42 days, including trailing/leading days of the neighbouring months).
    static func monthGridDays(containing date: Date) -> [Date] {
        let month = calendar.dateInterval(of: .month, for: date)!
        let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end)!
        let first = startOfWeek(month.start)
        let end = calendar.date(byAdding: .weekOfYear, value: 1, to: startOfWeek(lastDay))!
        var days: [Date] = []
        var day = first
        while day < end {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return days
    }
}

extension WeekCalendar {
    /// How many students reported on each day (keyed by the day's 00:00), by a recording or a note.
    /// A student with several sessions on one day counts once; days without reports are absent.
    static func studentsPerDay(_ sessions: [StudentSession]) -> [Date: Int] {
        Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.session.date) }
            .mapValues { Set($0.map(\.session.studentId)).count }
    }
}
