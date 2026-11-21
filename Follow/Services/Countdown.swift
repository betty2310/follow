import Foundation

/// How far a group is from its deadline (D44), in whole calendar days, shown in weeks and days.
struct Countdown: Equatable {
    /// Days from today to the deadline: 0 on the day itself, negative after it.
    let days: Int
    /// Weekly 1:1s still to come: the weeks after this one that start before the deadline.
    let sessionsLeft: Int
    /// Where today sits between the group's start (0) and the deadline (1), for the track.
    let progress: Double

    init(deadline: Date, start: Date, now: Date = .now) {
        let calendar = WeekCalendar.calendar
        let today = calendar.startOfDay(for: now), due = calendar.startOfDay(for: deadline)
        days = calendar.dateComponents([.day], from: today, to: due).day!

        var monday = calendar.date(byAdding: .weekOfYear, value: 1, to: WeekCalendar.startOfWeek(now))!
        var sessions = 0
        while monday < due {
            sessions += 1
            monday = calendar.date(byAdding: .weekOfYear, value: 1, to: monday)!
        }
        sessionsLeft = sessions

        // Counted in days, not seconds, so a daylight saving change doesn't skew it.
        let first = calendar.startOfDay(for: start)
        let span = calendar.dateComponents([.day], from: first, to: due).day!
        let elapsed = calendar.dateComponents([.day], from: first, to: today).day!
        progress = span > 0 ? min(max(Double(elapsed) / Double(span), 0), 1) : 1
    }

    /// The last week before the deadline, when the pill turns orange.
    var isNear: Bool { (0...7).contains(days) }
    var isPast: Bool { days < 0 }

    /// The pill's label, such as "Demo day in 6w 2d".
    func label(_ title: String) -> String {
        switch days {
        case 0: "\(title) is today"
        case ..<0: "\(title) was \(Self.short(-days)) ago"
        default: "\(title) in \(Self.short(days))"
        }
    }

    /// The popover's headline, such as "6 weeks, 2 days left".
    var headline: String {
        switch days {
        case 0: "Today"
        case ..<0: "\(Self.long(-days)) ago"
        default: "\(Self.long(days)) left"
        }
    }

    /// "6w 2d", "1w", or "5 days" when it's less than a week.
    static func short(_ days: Int) -> String {
        let weeks = days / 7, rest = days % 7
        if weeks == 0 { return plural(rest, "day") }
        return rest == 0 ? "\(weeks)w" : "\(weeks)w \(rest)d"
    }

    /// "6 weeks, 2 days", "1 week", "5 days".
    static func long(_ days: Int) -> String {
        let weeks = days / 7, rest = days % 7
        if weeks == 0 { return plural(rest, "day") }
        return rest == 0 ? plural(weeks, "week") : "\(plural(weeks, "week")), \(plural(rest, "day"))"
    }

    private static func plural(_ n: Int, _ unit: String) -> String { n == 1 ? "1 \(unit)" : "\(n) \(unit)s" }
}
