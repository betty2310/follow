import SwiftUI

/// Progress overview (docs/DECISIONS.md D13, D26): this week's count, who hasn't reported,
/// and a calendar with how many students reported each day.
struct DashboardView: View {
    let progress: [StudentProgress]
    var onSelect: (Int64) -> Void

    var body: some View {
        let current = WeekCalendar.week(of: .now)
        let missing = progress.filter { !$0.hasReported(in: current) }

        if progress.isEmpty {
            ContentUnavailableView("No students yet", systemImage: "person.3",
                                   description: Text("Import a student list (.xlsx) into a group from the toolbar."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 16) {
                        StatTile(title: "Reported this week", value: "\(progress.count - missing.count)/\(progress.count)")
                        StatTile(title: "Not reported yet", value: "\(missing.count)")
                    }

                    if !missing.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Not reported this week").font(.headline)
                            FlowList(students: missing, onSelect: onSelect)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reports per day").font(.headline)
                        ReportCalendar(progress: progress)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The group's calendar: each day shows how many students reported that day.
private struct ReportCalendar: View {
    let progress: [StudentProgress]

    var body: some View {
        let counts = WeekCalendar.studentsPerDay(progress)
        CalendarView(dates: Array(counts.keys)) { start in
            ForEach(0..<7, id: \.self) { offset in
                let day = WeekCalendar.calendar.date(byAdding: .day, value: offset, to: start)!
                if let n = counts[day] {
                    HStack {
                        Text(day, format: .dateTime.weekday(.abbreviated).day()).font(.caption)
                        Spacer()
                        Text("\(n)").font(.caption.bold().monospacedDigit())
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: .capsule)
                    .help(Self.help(n))
                }
            }
        } day: { day in
            if let n = counts[day] {
                Text("\(n)")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .help(Self.help(n))
            }
        }
    }

    private static func help(_ n: Int) -> String { n == 1 ? "1 student reported" : "\(n) students reported" }
}

private struct StatTile: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.largeTitle.monospacedDigit().bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 160, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }
}

private struct FlowList: View {
    let students: [StudentProgress]
    var onSelect: (Int64) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(students) { s in
                Button(s.student.fullName) { onSelect(s.id) }.buttonStyle(.link)
            }
        }
    }
}
