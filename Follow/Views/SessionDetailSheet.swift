import SwiftUI

/// The dialog a pin opens (D36). A text note is just its date and text. A recording adds a player,
/// the note, the summary (made on demand with **Summarize with AI**, editable) and the labeled transcript;
/// when the dialog is wide enough, the summary and the transcript sit side by side and scroll separately.
/// Changes save as you go; closing the dialog with a text note emptied deletes it.
struct SessionDetailSheet: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let sessionID: Int64
    /// Sizes the dialog before the session loads: a note needs far less room than a recording.
    var isNote = false
    @State private var session: Session?
    @State private var student: Student?
    @State private var note = ""
    @State private var player = AudioPlayer()
    @State private var isWide = false
    @State private var confirmingDelete = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                content(session)
            } else {
                ContentUnavailableView("This session was deleted", systemImage: "trash")
                    .frame(maxHeight: .infinity)
            }
            Divider()
            HStack {
                if let session {
                    Button("Delete…", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        .disabled(session.status == .recording)
                }
                Spacer()
                // Everything saves as you go, so closing (also with Esc) is all there is to do.
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(minWidth: isNote ? 560 : 860, minHeight: isNote ? 400 : 640)
        .onGeometryChange(for: Bool.self) { $0.size.width >= 800 } action: { isWide = $0 }
        .onAppear(perform: preload)
        .onDisappear(perform: close)
        .task {
            do {
                for try await value in db.observeSession(id: sessionID) {
                    session = value
                    loadAudioIfReady()
                }
            } catch {}
        }
        // Save the note shortly after typing stops, not only on close.
        .task(id: note) {
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { saveNote() }
        }
        .alert(session?.hasAudio == false ? "Delete this note?" : "Delete this session?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            if let session { Text(SessionActions.deleteMessage(for: session)) }
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    @ViewBuilder private func content(_ session: Session) -> some View {
        if session.hasAudio && isWide {
            VStack(alignment: .leading, spacing: 16) {
                top(session)
                HStack(alignment: .top, spacing: 16) {
                    ScrollView { SummarySection(session: session) }
                        .frame(maxWidth: .infinity)
                    ScrollView { transcript(session) }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
        } else if session.hasAudio {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    top(session)
                    SummarySection(session: session)
                    transcript(session)
                }
                .padding(20)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                header(session)
                noteEditor(minHeight: 200)
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// A recording's header, error, player and note.
    @ViewBuilder private func top(_ session: Session) -> some View {
        header(session)
        if let err = session.errorMessage, session.status == .failed {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red).textSelection(.enabled)
        }
        if session.status == .recording {
            Label("Recording… Close this dialog and press Stop in the toolbar to finish.", systemImage: "record.circle")
                .foregroundStyle(.red)
        } else {
            PlayerBar(player: player)
        }
        SectionCard("Note", systemImage: "note.text") {
            noteEditor(minHeight: 90)
        }
    }

    // MARK: Header

    /// Kind and student, the date (editable), status, and the recording's actions.
    private func header(_ session: Session) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                headerInfo(session)
                Spacer()
                actions(session)
            }
            VStack(alignment: .leading, spacing: 10) {
                headerInfo(session)
                HStack { actions(session) }
            }
        }
    }

    private func headerInfo(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: session.hasAudio ? "waveform" : "note.text")
                    .foregroundStyle(session.hasAudio ? Color.accentColor : .yellow)
                Text(session.hasAudio ? "Recording" : "Note")
                if let student {
                    Text("· \(student.emoji) \(student.fullName)").foregroundStyle(.secondary)
                }
            }
            .font(.title2.bold())
            .lineLimit(1)
            HStack(spacing: 6) {
                DatePicker("Date", selection: dateBinding(session))
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .fixedSize()
                if session.hasAudio {
                    Circle().fill(session.status.color).frame(width: 8, height: 8)
                    Text(session.statusLabel)
                    if let duration = session.utterances.last?.end {
                        Text("· \(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))")
                    }
                    if let engine = session.transcriptEngine {
                        Text("· \(EngineRegistry.transcription(id: engine).displayName)")
                    }
                }
            }
            .font(.callout).foregroundStyle(.secondary)
            .lineLimit(1)
        }
        // At its natural width, so the header stacks its actions below instead of wrapping words.
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private func actions(_ session: Session) -> some View {
        if session.hasAudio {
            Button("Show in Finder", systemImage: "folder") { SessionActions.revealAudio(of: session) }
                .disabled(session.status == .recording)
            Button("Transcribe Again", systemImage: "arrow.clockwise") { SessionActions.transcribe(sessionID, db: db) }
                .disabled(!session.canTranscribe)
                .help("Run speech-to-text again (keeps the summary)")
        }
    }

    private func dateBinding(_ session: Session) -> Binding<Date> {
        Binding(get: { self.session?.date ?? session.date }) { date in
            try? db.updateSession(id: sessionID) { $0.date = date }
        }
    }

    // MARK: Note

    private func noteEditor(minHeight: CGFloat) -> some View {
        TextEditor(text: $note)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(minHeight: minHeight, maxHeight: session?.hasAudio == true ? minHeight : .infinity)
            .background(.background, in: .rect(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary) }
            .overlay(alignment: .topLeading) {
                if note.isEmpty {
                    Text(session?.hasAudio == true ? "Add a note…" : "Write a note…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: Transcript

    private func transcript(_ session: Session) -> some View {
        SectionCard("Transcript", systemImage: "text.bubble") {
            // Without a summary nobody guessed the teacher yet, so let the teacher pick.
            if let next = session.swappedTeacherSpeaker {
                Button(session.teacherSpeaker == nil ? "Set Teacher" : "Swap Teacher / Student",
                       systemImage: "arrow.left.arrow.right") { setTeacher(next) }
                    .controlSize(.small)
                    .help(session.teacherSpeaker == nil ? "Mark Speaker \(next) as the teacher" : "Swap who is the teacher")
            }
        } content: {
            if session.utterances.isEmpty {
                Text(session.status.isBusy || session.status == .recording ? session.status.label : "Not available yet.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(session.utterances.enumerated()), id: \.offset) { _, u in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Button(Duration.seconds(u.start).formatted(.time(pattern: .minuteSecond))) {
                                player.seek(to: u.start)
                                player.play()
                            }
                            .buttonStyle(.plain)
                            .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                            .frame(width: 40, alignment: .trailing)
                            .help("Play from here")
                            .disabled(!player.isLoaded)
                            let isTeacher = session.teacherSpeaker == u.speaker
                            Text(session.roleName(of: u.speaker))
                                .font(.caption.bold())
                                .foregroundStyle(isTeacher ? Color.accentColor : .secondary)
                                .frame(width: 70, alignment: .leading)
                            Text(u.text).textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func setTeacher(_ speaker: String) {
        try? db.updateSession(id: sessionID) { $0.teacherSpeaker = speaker }
    }

    // MARK: Lifecycle

    private func preload() {
        session = try? db.session(id: sessionID)
        student = session.flatMap { try? db.student(id: $0.studentId) }
        note = session?.note ?? ""
        loadAudioIfReady()
    }

    /// Loads the recording once it's on disk (right away, or when recording stops while the dialog is open).
    private func loadAudioIfReady() {
        guard !player.isLoaded, let session, let path = session.audioPath, session.status != .recording else { return }
        player.load(AppPaths.absolute(path))
    }

    private func saveNote() {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session, text != session.note else { return }
        try? db.updateSession(id: sessionID) { $0.note = text }
    }

    private func close() {
        player.stop()
        guard let current = try? db.session(id: sessionID) else { return }
        // An emptied text note has nothing left to show.
        if !current.hasAudio && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? SessionActions.delete(current, db: db)
        } else {
            saveNote()
        }
    }

    private func delete() {
        guard let session else { return }
        do {
            try SessionActions.delete(session, db: db)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The recording's summary: made only on request (D36), then shown as markdown and editable.
private struct SummarySection: View {
    @Environment(\.appDatabase) private var db
    let session: Session
    @State private var isEditing = false
    @State private var draft = ""
    @State private var confirmingReplace = false

    private var summary: String { session.summaryMarkdown ?? "" }

    var body: some View {
        SectionCard("Summary", systemImage: "sparkles") {
            if !isEditing && !summary.isEmpty && session.status != .summarizing {
                Group {
                    Button("Edit Summary", systemImage: "pencil") {
                        draft = summary
                        isEditing = true
                    }
                    Button("Summarize Again", systemImage: "arrow.clockwise") { confirmingReplace = true }
                        .disabled(!session.canSummarize)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        } content: {
            if session.status == .summarizing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Summarizing…").foregroundStyle(.secondary)
                }
            } else if isEditing {
                TextEditor(text: $draft)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 240)
                    .background(.background, in: .rect(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary) }
                HStack {
                    Spacer()
                    Button("Cancel") { isEditing = false }
                    Button("Save", action: save)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("Save (⌘↩)")
                }
            } else if !summary.isEmpty {
                MarkdownText(markdown: summary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(session.utterances.isEmpty
                         ? "Once the recording is transcribed, you can summarize it with AI."
                         : "No summary yet. The transcript is often enough; summarize it when you need one.")
                        .foregroundStyle(.secondary)
                    Button("Summarize with AI", systemImage: "sparkles") {
                        SessionActions.summarize(session.id!, db: db)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.canSummarize)
                }
            }
        }
        .confirmationDialog("Replace the summary?", isPresented: $confirmingReplace) {
            Button("Summarize Again") { SessionActions.summarize(session.id!, db: db) }
        } message: {
            Text("A new summary replaces the current one, including your edits.")
        }
    }

    private func save() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        try? db.updateSession(id: session.id!) { $0.summaryMarkdown = text.isEmpty ? nil : text }
        isEditing = false
    }
}

/// Play/pause, elapsed time, a scrubber and the length of the recording.
private struct PlayerBar: View {
    let player: AudioPlayer

    var body: some View {
        if player.isLoaded {
            HStack(spacing: 10) {
                Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                       action: player.toggle)
                    .labelStyle(.iconOnly)
                    .help(player.isPlaying ? "Pause" : "Play")
                Text(Self.time(player.currentTime)).monospacedDigit()
                Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                       in: 0...max(player.duration, 0.1))
                Text(Self.time(player.duration)).monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        } else {
            Label("The recording file is missing.", systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private static func time(_ t: TimeInterval) -> String {
        Duration.seconds(t).formatted(.time(pattern: .minuteSecond))
    }
}

/// A titled, rounded panel for one part of the session, so the parts read as separate blocks.
/// `accessory` sits right after the title (small buttons).
struct SectionCard<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(_ title: String, systemImage: String,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage).foregroundStyle(Color.accentColor)
                    Text(title)
                }
                .font(.headline)
                accessory
                Spacer(minLength: 0)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.15)) }
    }
}

extension SectionCard where Accessory == EmptyView {
    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(title, systemImage: systemImage, accessory: { EmptyView() }, content: content)
    }
}

/// Renders the summary template: `## ` headings, `- ` bullets, and inline markdown in other lines.
/// (`Text(LocalizedStringKey:)` alone ignores block syntax like headings.)
private struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#") {
                    Text(inline(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
                        .font(.headline).padding(.top, 6)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(inline(String(line.dropFirst(2))))
                    }
                } else if !line.isEmpty {
                    Text(inline(line))
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
