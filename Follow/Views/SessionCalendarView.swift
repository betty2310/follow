import SwiftUI

enum CalendarMode: String, CaseIterable {
    case week = "Week", month = "Month"
}

/// A calendar (docs/DECISIONS.md D23, D24, D26) whose cells the caller fills, switchable between:
/// - **Week**: a horizontal strip, one Mon–Sun column per week, scrolled to the current week;
/// - **Month**: a Mon–Sun day grid for one month with ‹ › navigation.
/// Shows a student's sessions (`SessionCalendarView`) and a group's reports per day (`DashboardView`).
struct CalendarView<WeekContent: View, DayContent: View>: View {
    /// Dates of what the calendar shows: the week strip reaches back to the oldest one.
    let dates: [Date]
    /// When this changes, month mode moves to its month (e.g. the selected session, or a new recording).
    var focus: Date?
    /// A week column's content under its header, given the week's Monday.
    @ViewBuilder var week: (Date) -> WeekContent
    /// A day cell's content under its day number, given the day's 00:00.
    @ViewBuilder var day: (Date) -> DayContent

    @AppStorage("calendarMode") private var mode: CalendarMode = .week
    @State private var month = WeekCalendar.startOfMonth(.now)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("View", selection: $mode) {
                    ForEach(CalendarMode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                if mode == .month { monthNavigation }
            }
            switch mode {
            case .week: WeekStrip(dates: dates, content: week)
            case .month:
                // Take the grid's full height so busy days aren't squeezed by the pane below.
                MonthGrid(month: month, content: day)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: focus) {
            if let focus { month = WeekCalendar.startOfMonth(focus) }
        }
    }

    private var monthNavigation: some View {
        HStack(spacing: 4) {
            Text(month, format: .dateTime.month(.wide).year()).font(.headline).padding(.trailing, 6)
            Button("Previous Month", systemImage: "chevron.left") { shiftMonth(-1) }
            Button("Today") { month = WeekCalendar.startOfMonth(.now) }
            Button("Next Month", systemImage: "chevron.right") { shiftMonth(1) }
        }
        .labelStyle(.iconOnly)
        .controlSize(.small)
    }

    private func shiftMonth(_ delta: Int) {
        month = WeekCalendar.calendar.date(byAdding: .month, value: delta, to: month)!
    }
}

/// A student's sessions on the calendar, one chip per session; clicking a chip selects it.
struct SessionCalendarView: View {
    let sessions: [Session]
    @Binding var selection: Int64?
    var onEdit: (Session) -> Void = { _ in }
    var onDelete: (Session) -> Void = { _ in }

    var body: some View {
        let sorted = sessions.sorted { $0.date < $1.date }
        let byWeek = Dictionary(grouping: sorted) { WeekCalendar.week(of: $0.date) }
        let byDay = Dictionary(grouping: sorted) { WeekCalendar.calendar.startOfDay(for: $0.date) }
        CalendarView(dates: sessions.map(\.date), focus: sessions.first { $0.id == selection }?.date) { start in
            ForEach(byWeek[WeekCalendar.week(of: start)] ?? []) { session in
                SessionChip(session: session, isSelected: session.id == selection) { selection = session.id }
                    .contextMenu { menu(for: session) }
            }
        } day: { day in
            ForEach(byDay[day] ?? []) { session in
                SessionChip(session: session, isSelected: session.id == selection, showsWeekday: false) {
                    selection = session.id
                }
                .contextMenu { menu(for: session) }
            }
        }
    }

    @ViewBuilder private func menu(for session: Session) -> some View {
        Button("Edit…") { onEdit(session) }
        Button("Delete…", role: .destructive) { onDelete(session) }
            .disabled(session.status == .recording)
    }
}

/// Week mode: one column per week, from the oldest date (or 8 weeks back) through this week.
private struct WeekStrip<Content: View>: View {
    let dates: [Date]
    let content: (Date) -> Content

    var body: some View {
        let current = WeekCalendar.week(of: .now)
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(WeekCalendar.weekStarts(covering: dates), id: \.self) { start in
                        let id = WeekCalendar.week(of: start)
                        WeekColumn(start: start, isCurrent: id == current) { content(start) }
                            .id(id)
                        Divider()
                    }
                }
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.visible)
            .onAppear { proxy.scrollTo(current, anchor: .trailing) }
        }
        .frame(height: 150)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
    }
}

/// Month mode: Mon–Sun rows covering the month; days outside it are dimmed.
private struct MonthGrid<Content: View>: View {
    let month: Date
    let content: (Date) -> Content

    private static var weekdays: [String] {
        let symbols = WeekCalendar.calendar.shortStandaloneWeekdaySymbols // Sunday first
        return Array(symbols[1...] + symbols[..<1])
    }

    var body: some View {
        let cal = WeekCalendar.calendar
        let days = WeekCalendar.monthGridDays(containing: month)
        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        // Grid (not LazyVGrid) so every cell stretches to its row's tallest cell.
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                ForEach(Self.weekdays, id: \.self) {
                    Text($0).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 3)
            ForEach(weeks, id: \.first) { week in
                GridRow {
                    ForEach(week, id: \.self) { day in
                        DayCell(day: day, inMonth: cal.isDate(day, equalTo: month, toGranularity: .month)) { content(day) }
                    }
                }
            }
        }
    }
}

private struct DayCell<Content: View>: View {
    let day: Date
    let inMonth: Bool
    @ViewBuilder let content: Content

    var body: some View {
        let isToday = WeekCalendar.calendar.isDateInToday(day)
        VStack(alignment: .leading, spacing: 3) {
            Text(day, format: .dateTime.day())
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(isToday ? Color.accentColor : inMonth ? .primary : .secondary)
            content
        }
        .padding(5)
        // Grow with the content; the Grid sizes each row to its tallest cell.
        .frame(maxWidth: .infinity, minHeight: 62, maxHeight: .infinity, alignment: .topLeading)
        .background(isToday ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(inMonth ? 0.08 : 0.03))
        .opacity(inMonth ? 1 : 0.6)
    }
}

private struct WeekColumn<Content: View>: View {
    let start: Date
    let isCurrent: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Week \(WeekCalendar.week(of: start).week)").font(.caption.bold())
                Text(start, format: .dateTime.day().month(.abbreviated)).font(.caption2).foregroundStyle(.secondary)
            }
            .foregroundStyle(isCurrent ? Color.accentColor : .primary)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) { content }
            }
            .scrollIndicators(.never)
        }
        .padding(8)
        .frame(width: 118, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(isCurrent ? Color.accentColor.opacity(0.06) : .clear)
    }
}

private struct SessionChip: View {
    let session: Session
    let isSelected: Bool
    var showsWeekday = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(session.status.color).frame(width: 8, height: 8)
                Text(session.date, format: showsWeekday ? .dateTime.weekday(.abbreviated).hour().minute() : .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12), in: .capsule)
            .overlay { Capsule().strokeBorder(isSelected ? Color.accentColor : .clear) }
        }
        .buttonStyle(.plain)
        .help(session.status.label)
    }
}

extension SessionStatus {
    var label: String {
        switch self {
        case .recording: "Recording…"
        case .recorded: "Waiting to transcribe"
        case .transcribing: "Transcribing…"
        case .summarizing: "Summarizing…"
        case .done: "Done"
        case .failed: "Failed"
        }
    }

    var color: Color {
        switch self {
        case .recording: .red
        case .recorded, .transcribing, .summarizing: .orange
        case .done: .green
        case .failed: .red.opacity(0.6)
        }
    }

    var isBusy: Bool { self == .transcribing || self == .summarizing }
}
