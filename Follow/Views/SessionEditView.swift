import SwiftUI

/// Edit sheet for one session (docs/DECISIONS.md D29): its date and the summary.
struct SessionEditView: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let session: Session
    @State private var date: Date
    @State private var summary: String
    @State private var error: String?

    init(session: Session) {
        self.session = session
        _date = State(initialValue: session.date)
        _summary = State(initialValue: session.summaryMarkdown ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                DatePicker("Date", selection: $date)
                LabeledContent("Summary") {
                    // While a summary is being generated, saving would race with the pipeline.
                    editor($summary, minHeight: 240)
                        .disabled(session.status.isBusy)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 420)
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func editor(_ text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.body.monospaced())
            .scrollContentBackground(.hidden)
            .padding(4)
            .frame(minHeight: minHeight)
            .background(.background, in: .rect(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary) }
    }

    private func save() {
        guard let id = session.id else { return }
        let date = date
        let summary: String? = session.status.isBusy ? nil : summary.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try db.updateSession(id: id) {
                $0.date = date
                if let summary { $0.summaryMarkdown = summary.isEmpty ? nil : summary }
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Every session of a student with its note, newest first (D29). Clicking one selects it.
struct SessionNotesView: View {
    let sessions: [Session]
    @Binding var selection: Int64?

    var body: some View {
        let sorted = sessions.sorted { $0.date > $1.date }
        List(selection: $selection) {
            ForEach(sorted) { session in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(session.status.color).frame(width: 7, height: 7)
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
                .tag(session.id)
            }
        }
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "note.text")
            }
        }
    }
}
