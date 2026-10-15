import SwiftUI

/// The day board's Month mode (D24, D36): a Mon–Sun day grid for one month whose cells the caller fills;
/// days outside the month are dimmed. Clicking a day calls `onSelect` (the board then shows that day).
struct MonthGrid<Content: View>: View {
    let month: Date
    var onSelect: (Date) -> Void = { _ in }
    @ViewBuilder let content: (Date) -> Content

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
                            .contentShape(.rect)
                            .onTapGesture { onSelect(day) }
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
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: .infinity, alignment: .topLeading)
        .background(isToday ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(inMonth ? 0.08 : 0.03))
        .opacity(inMonth ? 1 : 0.6)
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
