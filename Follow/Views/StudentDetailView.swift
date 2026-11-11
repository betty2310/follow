import SwiftUI

/// A student's page: the project title, then the day board of their recordings and notes (D36).
struct StudentDetailView: View {
    @Environment(\.appDatabase) private var db
    @Environment(AudioRecorder.self) private var recorder
    let studentID: Int64
    let groupName: String
    @State private var student: Student?
    @State private var sessions: [Session] = []
    @State private var sheet: SessionSheet?
    @State private var error: String?
    @AppStorage("student.showNotes") private var showNotes = false

    var body: some View {
        VStack(spacing: 0) {
            ProjectTitleHeader(student: student)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 4)
            SessionBoard(sessions: student.map { s in sessions.map { StudentSession(session: $0, student: s) } } ?? [],
                         students: student.map { [$0] } ?? [],
                         sheet: $sheet)
        }
        .navigationTitle(student?.fullName ?? "")
        .navigationSubtitle(student?.mssv ?? "")
        .inspector(isPresented: $showNotes) {
            SessionNotesView(sessions: sessions) { sheet = .open($0) }
                .inspectorColumnWidth(min: 240, ideal: 300)
        }
        .toolbar {
            // The student's animal sits just before the name in the title bar (D35).
            ToolbarItem(placement: .navigation) {
                StudentEmojiButton(student: student, size: 22)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem {
                Toggle("Notes", systemImage: "list.bullet.rectangle", isOn: $showNotes)
                    .help("Show every session's note")
            }
            ToolbarItem {
                // Pressed while the student is checked in today; a second click undoes it (D41).
                Toggle("Check In", systemImage: "checkmark.circle", isOn: checkedInToday)
                    .disabled(student == nil)
                    .help("Mark that this student reported today, without a note or recording")
            }
            ToolbarItem {
                Button("New Note", systemImage: "square.and.pencil") {
                    sheet = .newNote(on: .now, studentID: studentID)
                }
                .disabled(student == nil)
                .help("Write a note about this student's progress")
            }
            ToolbarSpacer(.fixed)
            // Recording is what this page is for: a labeled, accent-colored button on its own
            // (not red, which reads as destructive).
            ToolbarItem {
                Group {
                    if recorder.session?.studentId == studentID {
                        Button("Stop", systemImage: "stop.fill", action: stop)
                            .help("Stop recording and transcribe")
                    } else {
                        Button("Record", systemImage: "record.circle", action: record)
                            .disabled(student == nil)
                            .help(recorder.isRecording
                                  ? "Stop the other student's recording, transcribe it, and record this student"
                                  : "Record this week's session")
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
                for try await value in db.observeSessions(studentId: studentID) { sessions = value }
            } catch {}
        }
    }

    private var checkedInToday: Binding<Bool> {
        Binding {
            sessions.contains { $0.isCheckIn && WeekCalendar.calendar.isDateInToday($0.date) }
        } set: { _ in
            do { try db.toggleCheckIn(studentId: studentID, on: .now) } catch { self.error = error.localizedDescription }
        }
    }

    private func preload() {
        student = try? db.student(id: studentID)
        sessions = (try? db.sessions(studentId: studentID)) ?? []
    }

    /// Recording another student stops theirs first, which is then transcribed like after Stop.
    private func record() {
        guard let student else { return }
        stop()
        let path = AppPaths.newAudioRelativePath(group: groupName, mssv: student.mssv)
        do {
            let session = try db.insertSession(Session(studentId: studentID, date: .now, audioPath: path, status: .recording))
            do {
                try recorder.start(to: AppPaths.absolute(path), session: session.id!, studentId: studentID)
            } catch {
                _ = try? db.deleteSession(id: session.id!)
                throw error
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Stops and transcribes right away; summarizing waits until the teacher asks for it (D36).
    private func stop() {
        guard let id = recorder.stop() else { return }
        try? db.updateSession(id: id) { $0.status = .recorded }
        SessionActions.transcribe(id, db: db)
    }
}

/// The student's project title as the page heading, with a button (or a double-click) to edit it in place (D29).
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
        HStack(alignment: .center, spacing: 10) {
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
                    .onTapGesture(count: 2) { startEditing(title) }
                    .help("Double-click to edit")
                if title.isEmpty {
                    Button("Add Title", systemImage: "plus") { startEditing(title) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .disabled(student == nil)
                        .help("Add the project title")
                } else {
                    Button("Edit Project Title", systemImage: "pencil") { startEditing(title) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .disabled(student == nil)
                        .help("Edit the project title")
                }
                Spacer()
            }
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func startEditing(_ title: String) {
        guard student != nil else { return }
        draft = title
        isEditing = true
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
