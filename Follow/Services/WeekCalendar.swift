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
    /// Mondays of the weeks to show in a calendar strip, oldest first: from the earliest of `dates`
    /// (or `minimumCount - 1` weeks before `now`, whichever is earlier) through the week of `now` or the latest date.
    static func weekStarts(covering dates: [Date], now: Date = .now, minimumCount: Int = 8) -> [Date] {
        let thisMonday = startOfWeek(now)
        let floor = calendar.date(byAdding: .weekOfYear, value: -(max(minimumCount, 1) - 1), to: thisMonday)!
        let first = min(dates.min().map(startOfWeek) ?? floor, floor)
        let last = max(dates.max().map(startOfWeek) ?? thisMonday, thisMonday)
        var result: [Date] = []
        var week = first
        while week <= last {
            result.append(week)
            week = calendar.date(byAdding: .weekOfYear, value: 1, to: week)!
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
    /// How many students reported on each day (keyed by the day's 00:00). A student with several sessions
    /// on one day counts once; days without reports are absent.
    static func studentsPerDay(_ progress: [StudentProgress]) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for p in progress {
            for day in Set(p.sessionDates.map(calendar.startOfDay)) { counts[day, default: 0] += 1 }
        }
        return counts
    }
}
