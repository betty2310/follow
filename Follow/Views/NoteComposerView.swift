import SwiftUI

/// Writes a new text note (D36): a session without audio. The student is fixed on a student page and
/// picked on the group dashboard. Nothing is saved until **Add**.
struct NoteComposerView: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let students: [Student]
    @State private var studentID: Int64?
    @State private var date: Date
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    init(students: [Student], date: Date, studentID: Int64?) {
        self.students = students.sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
        _date = State(initialValue: date)
        _studentID = State(initialValue: studentID)
    }

    private var canAdd: Bool {
        studentID != nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "note.text").foregroundStyle(.yellow)
                Text("New Note")
                if students.count == 1, let student = students.first {
                    Text("· \(student.emoji) \(student.fullName)").foregroundStyle(.secondary)
                }
            }
            .font(.title2.bold())

            HStack(spacing: 16) {
                if students.count > 1 {
                    Picker("Student", selection: $studentID) {
                        Text("Choose…").tag(Int64?.none)
                        ForEach(students) { s in
                            Text("\(s.emoji) \(s.fullName)").tag(s.id)
                        }
                    }
                    .fixedSize()
                }
                DatePicker("Date", selection: $date)
                    .datePickerStyle(.compact)
                    .fixedSize()
            }

            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 200, maxHeight: .infinity)
                .background(.background, in: .rect(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary) }
                .focused($focused)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canAdd)
                    .help("Add the note (⌘↩)")
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 380, idealHeight: 440)
        .onAppear { focused = true }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func add() {
        guard let studentID, canAdd else { return }
        do {
            try db.addNote(studentId: studentID, date: date, text: text)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Every session of a student with its note, newest first (D29). Clicking one opens it.
struct SessionNotesView: View {
    let sessions: [Session]
    var onOpen: (Int64) -> Void

    var body: some View {
        let sorted = sessions.sorted { $0.date > $1.date }
        List {
            ForEach(sorted) { session in
                Button { session.id.map(onOpen) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: session.hasAudio ? "waveform" : "note.text")
                                .foregroundStyle(session.hasAudio ? Color.accentColor : .yellow)
                            Text(session.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                                .font(.subheadline.bold())
                            Spacer()
                            Text("Week \(WeekCalendar.week(of: session.date).week)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if session.note.isEmpty {
                            Text("No note").font(.callout).foregroundStyle(.tertiary)
                        } else {
                            Text(session.note).font(.callout)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "note.text")
            }
        }
    }
}
