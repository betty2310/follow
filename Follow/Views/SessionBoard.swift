import AppKit
import SwiftUI

enum BoardMode: String, CaseIterable {
    case days = "Days", month = "Month"
}

/// What the session dialog shows: an existing session, or a new note being written.
enum SessionSheet: Identifiable, Hashable {
    case open(Int64)
    case newNote(date: Date, studentID: Int64?)

    var id: String {
        switch self {
        case .open(let id): "open-\(id)"
        case .newNote(let date, let studentID): "new-\(date)-\(studentID ?? -1)"
        }
    }

    /// A new note on `day`: now when it's today, midday otherwise (the time can be changed in the dialog).
    static func newNote(on day: Date, studentID: Int64?, now: Date = .now) -> SessionSheet {
        let cal = WeekCalendar.calendar
        let date = cal.isDate(day, inSameDayAs: now) ? now : cal.date(byAdding: .hour, value: 12, to: cal.startOfDay(for: day))!
        return .newNote(date: date, studentID: studentID)
    }
}

/// The day board (docs/DECISIONS.md D36), on the student page and the group dashboard.
/// **Days**: every day from the oldest session (or two weeks back) to today, oldest on top, opening at today
/// at the bottom. Each day is a row of pins (recordings and text notes) in time order, wrapping when full;
/// hovering a day shows + to add a note to it. Click a pin to open it; right-click for its actions.
/// **Month**: a month grid to see at a glance on which days students reported; click a day to jump to it.
struct SessionBoard: View {
    @Environment(\.appDatabase) private var db
    let sessions: [StudentSession]
    /// Students a new note can be for: the one on a student page, the group's on its dashboard.
    let students: [Student]
    /// The group dashboard shows whose pin it is, and counts students per day in Month mode.
    var showsStudent = false
    @Binding var sheet: SessionSheet?
    var onOpenStudent: ((Int64) -> Void)?

    @AppStorage("boardMode") private var mode: BoardMode = .days
    @State private var month = WeekCalendar.startOfMonth(.now)
    /// A day to bring into view in Days mode (picked in Month mode, or Today).
    @State private var scrollTarget: Date?
    @State private var deleting: Session?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("View", selection: $mode) {
                    ForEach(BoardMode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                switch mode {
                case .days:
                    Button("Today") { scrollTarget = WeekCalendar.calendar.startOfDay(for: .now) }
                        .controlSize(.small)
                case .month: monthNavigation
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            switch mode {
            case .days: dayList
            case .month: monthView
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .open(let id):
                SessionDetailSheet(sessionID: id, isNote: sessions.first { $0.id == id }?.session.hasAudio == false)
            case .newNote(let date, let studentID):
                NoteComposerView(students: students, date: date, studentID: studentID)
            }
        }
        .alert(deleting?.hasAudio == false ? "Delete this note?" : "Delete this session?",
               isPresented: .constant(deleting != nil), presenting: deleting) { session in
            Button("Delete", role: .destructive) { delete(session) }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { session in
            Text(SessionActions.deleteMessage(for: session))
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    // MARK: Days

    private var dayList: some View {
        let cal = WeekCalendar.calendar
        let byDay = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.session.date) }
        let days = WeekCalendar.days(covering: sessions.map(\.session.date))
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        let pins = (byDay[day] ?? []).sorted { $0.session.date < $1.session.date }
                        VStack(alignment: .leading, spacing: 0) {
                            if cal.component(.weekday, from: day) == 2 || day == days.first {
                                WeekHeader(day: day)
                            }
                            DayRow(day: day, isEmpty: pins.isEmpty,
                                   onAdd: students.isEmpty ? nil : { addNote(on: day) }) {
                                ForEach(pins) { pin($0) }
                            }
                        }
                        .id(day)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            // Open at today, the last row. The anchor alone stops short: the lazy rows' height is only estimated.
            .defaultScrollAnchor(.bottom)
            .task { proxy.scrollTo(days.last, anchor: .bottom) }
            // A task, not onChange: it runs after the rows are laid out, so the scroll isn't lost
            // when coming from Month mode.
            .task(id: scrollTarget) {
                guard let target = scrollTarget else { return }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
                scrollTarget = nil
            }
        }
    }

    private func pin(_ item: StudentSession) -> some View {
        Button { sheet = .open(item.id) } label: {
            PinCard(item: item, showsStudent: showsStudent)
        }
        .buttonStyle(.plain)
        .help(item.session.hasAudio ? item.session.statusLabel : "Note")
        .contextMenu { menu(for: item) }
    }

    @ViewBuilder private func menu(for item: StudentSession) -> some View {
        let session = item.session
        Button("Open") { sheet = .open(item.id) }
        if let onOpenStudent {
            Button("Go to \(item.student.fullName)") { onOpenStudent(session.studentId) }
        }
        if session.hasAudio {
            Divider()
            Button("Transcribe Again") { SessionActions.transcribe(item.id, db: db) }
                .disabled(!session.canTranscribe)
            // Replacing a summary asks first, so that lives in the dialog.
            if session.summaryMarkdown?.isEmpty ?? true {
                Button("Summarize with AI") { SessionActions.summarize(item.id, db: db) }
                    .disabled(!session.canSummarize)
            }
            Button("Show in Finder") { SessionActions.revealAudio(of: session) }
                .disabled(session.status == .recording)
        }
        Divider()
        Button("Delete…", role: .destructive) { deleting = session }
            .disabled(session.status == .recording)
    }

    private func addNote(on day: Date) {
        sheet = .newNote(on: day, studentID: students.count == 1 ? students[0].id : nil)
    }

    private func delete(_ session: Session) {
        deleting = nil
        do { try SessionActions.delete(session, db: db) } catch { self.error = error.localizedDescription }
    }

    // MARK: Month

    private var monthView: some View {
        let cal = WeekCalendar.calendar
        let byDay = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.session.date) }
        let counts = WeekCalendar.studentsPerDay(sessions)
        return ScrollView {
            MonthGrid(month: month, onSelect: show) { day in
                if showsStudent {
                    if let n = counts[day] {
                        Text("\(n)")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity)
                            .help(n == 1 ? "1 student reported" : "\(n) students reported")
                    }
                } else {
                    ForEach((byDay[day] ?? []).sorted { $0.session.date < $1.session.date }) { item in
                        MonthChip(session: item.session) { sheet = .open(item.id) }
                    }
                }
            }
            .padding(16)
        }
    }

    private var monthNavigation: some View {
        let cal = WeekCalendar.calendar
        let reportedDays = Set(sessions.map { cal.startOfDay(for: $0.session.date) })
            .filter { cal.isDate($0, equalTo: month, toGranularity: .month) }.count
        return HStack(spacing: 4) {
            Text(reportedDays == 1 ? "1 day with reports" : "\(reportedDays) days with reports")
                .font(.callout).foregroundStyle(.secondary).padding(.trailing, 10)
            Text(month, format: .dateTime.month(.wide).year()).font(.headline).padding(.trailing, 6)
            Group {
                Button("Previous Month", systemImage: "chevron.left") { shiftMonth(-1) }
                Button("Today") { month = WeekCalendar.startOfMonth(.now) }
                Button("Next Month", systemImage: "chevron.right") { shiftMonth(1) }
            }
            .labelStyle(.iconOnly)
        }
        .controlSize(.small)
    }

    private func shiftMonth(_ delta: Int) {
        month = WeekCalendar.calendar.date(byAdding: .month, value: delta, to: month)!
    }

    /// Month → Days, scrolled to the clicked day.
    private func show(_ day: Date) {
        mode = .days
        scrollTarget = day
    }
}

/// "Week 42" above each Monday (and the first day shown): sessions are weekly, so weeks help find one.
private struct WeekHeader: View {
    let day: Date

    var body: some View {
        let isCurrent = WeekCalendar.week(of: day) == WeekCalendar.week(of: .now)
        Text("Week \(WeekCalendar.week(of: day).week)")
            .font(.caption.bold())
            .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }
}

/// One day of the board: the date on the left, its pins wrapping to the right, + on hover.
private struct DayRow<Pins: View>: View {
    let day: Date
    let isEmpty: Bool
    var onAdd: (() -> Void)?
    @ViewBuilder var pins: Pins
    @State private var hovering = false

    var body: some View {
        let cal = WeekCalendar.calendar
        let isToday = cal.isDateInToday(day)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.wide)))
                    .font(.subheadline.bold())
                Text(day, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(isToday ? Color.accentColor : cal.isDateInWeekend(day) ? .secondary : .primary)
            .frame(width: 110, alignment: .leading)

            FlowLayout(spacing: 8) { pins }
                .frame(maxWidth: .infinity, alignment: .leading)

            if let onAdd {
                Button("Add Note", systemImage: "plus", action: onAdd)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Add a note to this day")
                    .opacity(hovering ? 1 : 0)
            }
        }
        .padding(.vertical, isEmpty ? 6 : 10)
        .padding(.horizontal, 8)
        .background(isToday ? Color.accentColor.opacity(0.06) : hovering ? Color.secondary.opacity(0.05) : .clear,
                    in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onHover { hovering = $0 }
    }
}

/// A session as a pin: yellow for a text note, accent-tinted for a recording, with a few lines of its content.
private struct PinCard: View {
    let item: StudentSession
    let showsStudent: Bool

    var body: some View {
        let session = item.session
        let tint = session.hasAudio ? Color.accentColor : .yellow
        let preview = session.preview
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: session.hasAudio ? "waveform" : "note.text")
                Text(session.date, format: .dateTime.hour().minute()).monospacedDigit()
                if let duration = session.utterances.last?.end {
                    Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))).monospacedDigit()
                }
                Spacer(minLength: 0)
                if session.summaryMarkdown?.isEmpty == false {
                    Image(systemName: "sparkles").help("Summarized")
                }
                if session.hasAudio && session.status != .done {
                    Circle().fill(session.status.color).frame(width: 7, height: 7)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if showsStudent {
                Text("\(item.student.emoji) \(item.student.fullName)")
                    .font(.caption.bold())
                    .lineLimit(1)
            }

            Text(preview.isEmpty ? session.statusLabel : preview)
                .font(.callout)
                .foregroundStyle(preview.isEmpty ? .secondary : .primary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(width: 200, alignment: .topLeading)
        .background(tint.opacity(0.14), in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.35)) }
        .contentShape(.rect(cornerRadius: 8))
    }
}

/// A pin in a Month cell: kind icon and time.
private struct MonthChip: View {
    let session: Session
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: session.hasAudio ? "waveform" : "note.text")
                Text(session.date, format: .dateTime.hour().minute()).monospacedDigit()
            }
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((session.hasAudio ? Color.accentColor : .yellow).opacity(0.18), in: .capsule)
        }
        .buttonStyle(.plain)
        .help(session.hasAudio ? session.statusLabel : session.note)
    }
}

/// Lays children out left to right, wrapping to a new line when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(subviews, width: bounds.width).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (frames, CGSize(width: maxX, height: frames.isEmpty ? 0 : y + lineHeight))
    }
}

/// Session actions shared by the board's context menu and the session dialog.
@MainActor
enum SessionActions {
    static func transcribe(_ id: Int64, db: AppDatabase) {
        Task.detached { await SessionProcessor.transcribe(sessionId: id, db: db) }
    }

    static func summarize(_ id: Int64, db: AppDatabase) {
        Task.detached { await SessionProcessor.summarize(sessionId: id, db: db) }
    }

    /// Deletes the session and moves its recording, if any, to the Trash.
    static func delete(_ session: Session, db: AppDatabase) throws {
        guard let id = session.id else { return }
        if let path = try db.deleteSession(id: id) { AppPaths.trashAudio([path]) }
    }

    static func deleteMessage(for session: Session) -> String {
        let when = session.date.formatted(date: .abbreviated, time: .shortened)
        return session.hasAudio
            ? "The session of \(when) is permanently deleted with its transcript, summary and note. The recording is moved to the Trash."
            : "The note of \(when) is permanently deleted."
    }

    static func revealAudio(of session: Session) {
        guard let path = session.audioPath else { return }
        let url = AppPaths.absolute(path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
