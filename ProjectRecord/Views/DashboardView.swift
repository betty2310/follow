import SwiftUI

/// Progress overview (docs/DECISIONS.md D13): this week's count, who hasn't reported, and a students × weeks grid.
struct DashboardView: View {
    let students: [Student]
    var onSelect: (Student) -> Void
    var weeksShown = 8

    private var weeks: [(id: WeekID, start: Date)] {
        let thisMonday = WeekCalendar.startOfWeek(.now)
        return (0..<weeksShown).reversed().map { offset in
            let start = WeekCalendar.calendar.date(byAdding: .weekOfYear, value: -offset, to: thisMonday)!
            return (WeekCalendar.week(of: start), start)
        }
    }

    private var sorted: [Student] { students.sorted { $0.fullName < $1.fullName } }

    var body: some View {
        let current = WeekCalendar.week(of: .now)
        let missing = sorted.filter { !$0.hasReported(in: current) }

        if students.isEmpty {
            ContentUnavailableView("No students yet", systemImage: "person.3",
                                   description: Text("Import the term's student list (.xlsx) from the toolbar."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 16) {
                        StatTile(title: "Reported this week", value: "\(students.count - missing.count)/\(students.count)")
                        StatTile(title: "Not reported yet", value: "\(missing.count)")
                    }

                    if !missing.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Not reported this week").font(.headline)
                            FlowList(students: missing, onSelect: onSelect)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weekly reports").font(.headline)
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Student").font(.caption).foregroundStyle(.secondary)
                                ForEach(weeks, id: \.id) { w in
                                    Text(w.start, format: .dateTime.day().month(.defaultDigits))
                                        .font(.caption).foregroundStyle(.secondary)
                                        .gridColumnAlignment(.center)
                                }
                            }
                            Divider()
                            ForEach(sorted) { s in
                                GridRow {
                                    Button(s.fullName) { onSelect(s) }.buttonStyle(.link)
                                    ForEach(weeks, id: \.id) { w in
                                        let done = s.hasReported(in: w.id)
                                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(done ? .green : .secondary.opacity(0.4))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Dashboard")
        }
    }
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
    let students: [Student]
    var onSelect: (Student) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(students) { s in
                Button(s.fullName) { onSelect(s) }.buttonStyle(.link)
            }
        }
    }
}
