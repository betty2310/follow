import SwiftData
import SwiftUI

struct StudentDetailView: View {
    @Environment(\.modelContext) private var context
    let student: Student
    @State private var recorder = AudioRecorder()
    @State private var activeSession: Session?
    @State private var error: String?

    private var sessions: [Session] { student.sessions.sorted { $0.date > $1.date } }

    var body: some View {
        List {
            ForEach(sessions) { session in
                SessionCard(session: session)
            }
        }
        .navigationTitle(student.fullName)
        .navigationSubtitle(student.projectTitle)
        .toolbar {
            if recorder.isRecording {
                Button("Stop", systemImage: "stop.circle.fill", action: stop).tint(.red)
            } else {
                Button("Record", systemImage: "record.circle", action: record)
            }
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func record() {
        let path = AppPaths.newAudioRelativePath(term: student.term?.name ?? "term", mssv: student.mssv)
        let session = Session(audioFileName: path)
        session.status = .recording
        session.student = student
        context.insert(session)
        do {
            try recorder.start(to: AppPaths.absolute(path))
            activeSession = session
        } catch {
            context.delete(session)
            self.error = error.localizedDescription
        }
    }

    private func stop() {
        recorder.stop()
        guard let session = activeSession else { return }
        activeSession = nil
        session.status = .recorded
        Task { await SessionProcessor.process(session) }
    }
}

private struct SessionCard: View {
    let session: Session
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.date, format: .dateTime.weekday().day().month().hour().minute()).font(.headline)
                Spacer()
                Text(session.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                if session.status == .failed || session.status == .done {
                    Button("Re-run", systemImage: "arrow.clockwise") {
                        Task { await SessionProcessor.process(session) }
                    }
                    .labelStyle(.iconOnly)
                }
            }
            if let err = session.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            if let md = session.summaryMarkdown {
                Text(LocalizedStringKey(md)).textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }
}
