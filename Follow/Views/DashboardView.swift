import SwiftUI

/// A group's page (docs/DECISIONS.md D13, D26, D36): this week's count and who hasn't reported on top,
/// then the day board with every student's recordings and notes.
struct DashboardView: View {
    @Environment(\.appDatabase) private var db
    let groupID: Int64
    let progress: [StudentProgress]
    var onAdd: () -> Void
    var onSelect: (Int64) -> Void
    @State private var sessions: [StudentSession] = []
    @State private var sheet: SessionSheet?

    var body: some View {
        let current = WeekCalendar.week(of: .now)
        let missing = progress.filter { !$0.hasReported(in: current) }

        Group {
            if progress.isEmpty {
                ContentUnavailableView {
                    Label("No students yet", systemImage: "person.3")
                } description: {
                    Text("Add students one by one, or import a student list (.xlsx) from the toolbar.")
                } actions: {
                    Button("Add Student…", action: onAdd)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 12) {
                        StatTile(title: "Reported this week", value: "\(progress.count - missing.count)/\(progress.count)")
                        StatTile(title: "Not reported yet", value: "\(missing.count)")
                        if !missing.isEmpty {
                            MissingList(students: missing, onSelect: onSelect)
                        }
                    }
                    .padding(16)
                    SessionBoard(sessions: sessions, students: progress.map(\.student), showsStudent: true,
                                 sheet: $sheet, onOpenStudent: onSelect)
                }
            }
        }
        .toolbar {
            Button("New Note", systemImage: "square.and.pencil") { sheet = .newNote(on: .now, studentID: nil) }
                .disabled(progress.isEmpty)
                .help("Write a note about a student's progress")
        }
        .onAppear { sessions = (try? db.sessions(groupId: groupID)) ?? [] }
        .task {
            do {
                for try await value in db.observeSessions(groupId: groupID) { sessions = value }
            } catch {}
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title.monospacedDigit().bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 140, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }
}

/// Students who haven't reported this week, on one line that scrolls sideways.
private struct MissingList: View {
    let students: [StudentProgress]
    var onSelect: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not reported this week").font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(students) { s in
                        Button("\(s.student.emoji) \(s.student.fullName)") { onSelect(s.id) }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
