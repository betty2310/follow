import SwiftUI

/// A student's page: the project title, then the day board of their recordings and notes (D36).
struct StudentDetailView: View {
    @Environment(\.appDatabase) private var db
    @Environment(AudioRecorder.self) private var recorder
    let studentID: Int64
    let groupName: String
    let group: StudentGroup?
    var onOpenStudent: (Int64) -> Void
    @State private var student: Student?
    /// The student being recorded when it isn't this one, shown as a chip that opens their page.
    @State private var recordingStudent: Student?
    @State private var sessions: [Session] = []
    @State private var sheet: SessionSheet?
    @State private var error: String?
    @AppStorage("student.showNotes") private var showNotes = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the student's animal is (D44): in the title until it runs into the deadline pill.
    @State private var runner = RunnerPlace.title
    @State private var titleAnchor = ScreenAnchor()
    @State private var runnerAnchor = ScreenAnchor()
    @AppStorage(RunnerStyle.key) private var runnerStyle = RunnerStyle.hop
    @AppStorage(RunnerStyle.speedKey) private var runnerSpeed = 1.0

    private enum RunnerPlace { case title, flying, pill }
    private var hasDeadline: Bool { group?.deadline != nil }

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
        // Recording here stops the other student's recording, which hides their chip.
        .onChange(of: recorder.session?.studentId) { loadRecordingStudent() }
        // Grouped by job (D43): the three ways to log progress together, Record last and the only
        // colored button (D33), then the Notes panel toggle at the trailing edge.
        .toolbar {
            // The student's animal sits just before the name in the title bar (D35).
            // With a deadline it runs to the pill when the page opens, and the title keeps only the name (D44).
            ToolbarItem(placement: .navigation) {
                if runner != .pill || !hasDeadline {
                    StudentEmojiButton(student: student, size: 22)
                        .opacity(runner == .flying ? 0 : 1)
                        .background(ScreenAnchorView(anchor: titleAnchor))
                }
            }
            .sharedBackgroundVisibility(.hidden)
            if let other = recordingStudent, let id = other.id {
                ToolbarItem {
                    Button { onOpenStudent(id) } label: {
                        RecordingTimer(recorder: recorder) { time in
                            Label("\(other.fullName)  \(time)", systemImage: "circle.fill")
                        }
                        .imageScale(.small)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.red)
                    }
                    .help("Recording \(other.fullName). Click to open their page.")
                }
                ToolbarSpacer(.fixed)
            }
            if let group, group.deadline != nil, let student {
                ToolbarItem {
                    DeadlinePill(group: group, runner: .animal(student.emoji),
                                 runnerVisible: runner == .pill, runnerAnchor: runnerAnchor)
                }
            }
            ToolbarItemGroup {
                // Pressed while the student is checked in today; a second click undoes it (D41).
                Toggle("Check In", systemImage: "checkmark.circle", isOn: checkedInToday)
                    .disabled(student == nil)
                    .help("Mark that this student reported today, without a note or recording")
                Button("New Note", systemImage: "square.and.pencil") {
                    sheet = .newNote(on: .now, studentID: studentID)
                }
                .disabled(student == nil)
                .help("Write a note about this student's progress")
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Group {
                    if recorder.session?.studentId == studentID {
                        // Red with a running timer while live, like other macOS recorders.
                        Button(action: stop) {
                            RecordingTimer(recorder: recorder) { time in
                                Label("\(time)  Stop", systemImage: "stop.fill")
                            }
                        }
                        .tint(.red)
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
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Toggle("Notes", systemImage: "sidebar.trailing", isOn: $showNotes)
                    .help(showNotes ? "Hide the notes panel" : "Show every session's note")
            }
        }
        .task(id: group?.deadline) { await runToPill() }
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
        loadRecordingStudent()
    }

    /// Read in `preload`, not in a `.task`: a toolbar item that appears after the first frame never shows.
    private func loadRecordingStudent() {
        recordingStudent = recorder.session.flatMap { $0.studentId == studentID ? nil : try? db.student(id: $0.studentId) }
    }

    /// The student's animal hops from the title to today's spot on the deadline track (D44).
    private func runToPill() async {
        guard hasDeadline else {
            runner = .title
            return
        }
        guard runner == .title else { return }
        if reduceMotion {
            runner = .pill
            return
        }
        // The toolbar lays its items out a moment after the page appears.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled, let emoji = student?.emoji else { return }
        let started = RunnerFlight.run(emoji, style: runnerStyle, speed: runnerSpeed, from: titleAnchor, to: runnerAnchor,
                                       fromSize: 22, toSize: 16, clear: titleClearance) {
            runner = .pill
        }
        runner = started ? .flying : .pill
    }

    /// From the middle of the title's animal to just past the name and student ID next to it: the first leap's length.
    private var titleClearance: CGFloat {
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            NSAttributedString(string: text, attributes: [.font: font]).size().width
        }
        let text = max(width(student?.fullName ?? "", .boldSystemFont(ofSize: 13)),
                       width(student?.mssv ?? "", .systemFont(ofSize: 11)))
        // 30 pt from the animal's middle to the text, and room to land after it.
        return 30 + text + 18
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

/// The running recording's elapsed time as m:ss, refreshed every second.
private struct RecordingTimer<Content: View>: View {
    let recorder: AudioRecorder
    @ViewBuilder var content: (String) -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            content(Duration.seconds(Int(recorder.currentTime)).formatted(.time(pattern: .minuteSecond)))
                .monospacedDigit()
        }
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
