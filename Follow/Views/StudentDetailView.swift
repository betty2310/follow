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
    @State private var editing: Session?
    @State private var deleting: Session?
    @State private var error: String?
    @AppStorage("student.showNotes") private var showNotes = false

    private var selectedSession: Session? { sessions.first { $0.id == selectedSessionID } }

    var body: some View {
        VStack(spacing: 0) {
            ProjectTitleHeader(student: student)
                .padding([.horizontal, .top], 16)
            SessionCalendarView(sessions: sessions, selection: $selectedSessionID,
                                onEdit: { editing = $0 }, onDelete: { deleting = $0 })
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 8)
            Divider()
            if let session = selectedSession {
                SessionDetailView(session: session,
                                  onRerun: { rerun(session) },
                                  onEdit: { editing = session },
                                  onDelete: { deleting = session })
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
        .navigationSubtitle(student?.mssv ?? "")
        .inspector(isPresented: $showNotes) {
            SessionNotesView(sessions: sessions, selection: $selectedSessionID)
                .inspectorColumnWidth(min: 240, ideal: 300)
        }
        .sheet(item: $editing) { SessionEditView(session: $0) }
        .alert("Delete this session?", isPresented: .constant(deleting != nil), presenting: deleting) { session in
            Button("Delete", role: .destructive) { delete(session) }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { session in
            Text("The session of \(session.date.formatted(date: .abbreviated, time: .shortened)) is permanently deleted with its transcript, summary and note. The recording is moved to the Trash.")
        }
        .toolbar {
            ToolbarItem {
                Toggle("Notes", systemImage: "note.text", isOn: $showNotes)
                    .help("Show every session's note")
            }
            ToolbarSpacer(.fixed)
            // Recording is what this page is for: a labeled, accent-colored button on its own
            // (not red, which reads as destructive).
            ToolbarItem {
                Group {
                    if recorder.isRecording {
                        Button("Stop", systemImage: "stop.fill", action: stop)
                            .help("Stop recording and transcribe")
                    } else {
                        Button("Record", systemImage: "record.circle", action: record)
                            .disabled(student == nil)
                            .help("Record this week's session")
                    }
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
            }
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        // Runs before the first frame: the page appears complete instead of empty until the
        // observations below deliver, which flashed when switching students.
        .onAppear(perform: preload)
        .task {
            do {
                for try await value in db.observeStudent(id: studentID) { student = value }
            } catch {}
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

    private func preload() {
        student = try? db.student(id: studentID)
        sessions = (try? db.sessions(studentId: studentID)) ?? []
        selectedSessionID = sessions.first?.id
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
                _ = try? db.deleteSession(id: session.id!)
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

    private func delete(_ session: Session) {
        deleting = nil
        guard let id = session.id else { return }
        do {
            // The sessions observation then selects the newest remaining session.
            if let path = try db.deleteSession(id: id) { AppPaths.trashAudio([path]) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func rerun(_ session: Session) {
        guard let id = session.id else { return }
        let db = db
        Task.detached { await SessionProcessor.process(sessionId: id, db: db) }
    }
}

/// The student's project title as the page heading, with a small pencil to edit it in place (D29).
private struct ProjectTitleHeader: View {
    @Environment(\.appDatabase) private var db
    let student: Student?
    // A flag plus a plain String, not `String?` + `Binding($draft)`: that binding force-unwraps, and
    // SwiftUI reads it once more after Cancel sets nil, which crashes.
    @State private var isEditing = false
    @State private var draft = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if isEditing {
                TextField("Project title", text: $draft, prompt: Text("The student's project"))
                    .textFieldStyle(.roundedBorder)
                    .font(.title)
                    .focused($focused)
                    .onAppear { focused = true }
                    .onSubmit(save)
                    .onExitCommand { isEditing = false }
                Button("Cancel") { isEditing = false }
                Button("Save", action: save).buttonStyle(.borderedProminent)
            } else {
                let title = student?.projectTitle ?? ""
                Text(title.isEmpty ? "No title" : title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(title.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                Button("Edit Project Title", systemImage: "pencil") {
                    draft = title
                    isEditing = true
                }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(student == nil)
                    .help("Edit the project title")
                Spacer()
            }
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func save() {
        guard let id = student?.id else { return }
        do {
            try db.setProjectTitle(studentId: id, draft)
            isEditing = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}
