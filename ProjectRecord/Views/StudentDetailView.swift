import SwiftUI

struct StudentDetailView: View {
    @Environment(\.appDatabase) private var db
    let studentID: Int64
    let groupName: String
    @State private var student: Student?
    @State private var sessions: [Session] = []
    @State private var recorder = AudioRecorder()
    @State private var activeSessionID: Int64?
    @State private var error: String?

    var body: some View {
        List {
            ForEach(sessions) { session in
                SessionCard(session: session) { rerun(session) }
            }
        }
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "waveform", description: Text("Press Record to start this week's session."))
            }
        }
        .navigationTitle(student?.fullName ?? "")
        .navigationSubtitle(student?.projectTitle ?? "")
        .toolbar {
            if recorder.isRecording {
                Button("Stop", systemImage: "stop.circle.fill", action: stop).tint(.red)
            } else {
                Button("Record", systemImage: "record.circle", action: record).disabled(student == nil)
            }
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .task {
            do { for try await value in db.observeStudent(id: studentID) { student = value } } catch {}
        }
        .task {
            do { for try await value in db.observeSessions(studentId: studentID) { sessions = value } } catch {}
        }
    }

    private func record() {
        guard let student else { return }
        let path = AppPaths.newAudioRelativePath(group: groupName, mssv: student.mssv)
        do {
            let session = try db.insertSession(Session(studentId: studentID, date: .now, audioPath: path, status: .recording))
            do {
                try recorder.start(to: AppPaths.absolute(path))
                activeSessionID = session.id
            } catch {
                try? db.deleteSession(id: session.id!)
                throw error
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func stop() {
        recorder.stop()
        guard let id = activeSessionID else { return }
        activeSessionID = nil
        try? db.updateSession(id: id) { $0.status = .recorded }
        let db = db
        Task.detached { await SessionProcessor.process(sessionId: id, db: db) }
    }

    private func rerun(_ session: Session) {
        guard let id = session.id else { return }
        let db = db
        Task.detached { await SessionProcessor.process(sessionId: id, db: db) }
    }
}

private struct SessionCard: View {
    let session: Session
    var onRerun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.date, format: .dateTime.weekday().day().month().hour().minute()).font(.headline)
                Spacer()
                Text(session.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                if session.status == .failed || session.status == .done {
                    Button("Re-run", systemImage: "arrow.clockwise", action: onRerun).labelStyle(.iconOnly)
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
