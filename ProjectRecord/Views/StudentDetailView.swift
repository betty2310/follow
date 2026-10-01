import SwiftUI

struct StudentDetailView: View {
    @Environment(\.appDatabase) private var db
    let studentID: Int64
    let groupName: String
    @State private var student: Student?
    @State private var sessions: [Session] = []
    @State private var selectedSessionID: Int64?
    @State private var recorder = AudioRecorder()
    @State private var activeSessionID: Int64?
    @State private var error: String?

    private var selectedSession: Session? { sessions.first { $0.id == selectedSessionID } }

    var body: some View {
        VStack(spacing: 0) {
            SessionCalendarView(sessions: sessions, selection: $selectedSessionID)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 8)
            Divider()
            if let session = selectedSession {
                SessionDetailView(session: session) { rerun(session) }
            } else {
                ContentUnavailableView(
                    sessions.isEmpty ? "No sessions yet" : "No session selected",
                    systemImage: "waveform",
                    description: Text(sessions.isEmpty ? "Press Record to start this week's session." : "Pick a session in the calendar above.")
                )
                .frame(maxHeight: .infinity)
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
            do {
                for try await value in db.observeSessions(studentId: studentID) {
                    sessions = value
                    // Default to the newest session; keep the user's pick while it still exists.
                    if selectedSession == nil { selectedSessionID = value.first?.id }
                }
            } catch {}
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
                selectedSessionID = session.id
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
