import AppKit
import SwiftUI

/// Everything about one recording: status and actions, the teacher's note, the Vietnamese summary, and the labeled transcript.
/// Each section is a card; when the pane is wide enough, the summary and the transcript sit side by side
/// under the note and scroll separately, so the summary can be checked against what was said.
struct SessionDetailView: View {
    @Environment(\.appDatabase) private var db
    let session: Session
    var onRerun: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    @State private var isWide = false

    var body: some View {
        Group {
            if isWide {
                VStack(alignment: .leading, spacing: 16) {
                    top
                    note
                    HStack(alignment: .top, spacing: 16) {
                        ScrollView { summary }
                            .frame(maxWidth: .infinity)
                        ScrollView { transcript }
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        top
                        note
                        summary
                        transcript
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: Bool.self) { $0.size.width >= 760 } action: { isWide = $0 }
    }

    @ViewBuilder private var top: some View {
        header
        if let err = session.errorMessage, session.status == .failed {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red).textSelection(.enabled)
        }
    }

    private var note: some View {
        NoteSection(session: session).id(session.id)
    }

    private var summary: some View {
        SectionCard("Summary", systemImage: "sparkles") {
            if let md = session.summaryMarkdown, !md.isEmpty {
                MarkdownText(markdown: md)
            } else {
                placeholder
            }
        }
    }

    private var transcript: some View {
        SectionCard("Transcript", systemImage: "text.bubble") {
            if let swapped = session.swappedTeacherSpeaker, session.teacherSpeaker != nil {
                Button("Swap Teacher / Student", systemImage: "arrow.left.arrow.right") { setTeacher(swapped) }
                    .controlSize(.small)
            }
        } content: {
            if session.utterances.isEmpty {
                placeholder
            } else {
                utterances
            }
        }
    }

    /// Date and status, with the actions on the right; the actions drop below when they don't fit beside it.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                headerInfo
                Spacer()
                actions
            }
            VStack(alignment: .leading, spacing: 10) {
                headerInfo
                HStack { actions }
            }
        }
    }

    private var headerInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.date, format: .dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
                .font(.title2.bold())
            HStack(spacing: 6) {
                Circle().fill(session.status.color).frame(width: 8, height: 8)
                Text(session.status.label)
                if let duration = session.utterances.last?.end {
                    Text("· \(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))")
                }
                if let engine = session.transcriptEngine {
                    Text("· \(EngineRegistry.transcription(id: engine).displayName)")
                }
            }
            .font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var actions: some View {
        Button("Show in Finder", systemImage: "folder", action: revealAudio)
            .disabled(session.status == .recording)
        if [.recorded, .failed, .done].contains(session.status) {
            Button("Re-run", systemImage: "arrow.clockwise", action: onRerun)
                .help("Transcribe and summarize again")
        }
        Button("Edit…", systemImage: "pencil", action: onEdit)
            .help("Edit the date and summary")
        Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
            .disabled(session.status == .recording)
            .help("Delete this session")
    }

    private var utterances: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(session.utterances.enumerated()), id: \.offset) { _, u in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Duration.seconds(u.start).formatted(.time(pattern: .minuteSecond)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                        .frame(width: 40, alignment: .trailing)
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

    @ViewBuilder private var placeholder: some View {
        Text(session.status.isBusy || session.status == .recording ? session.status.label : "Not available yet.")
            .foregroundStyle(.secondary)
    }

    private func setTeacher(_ speaker: String) {
        guard let id = session.id else { return }
        try? db.updateSession(id: id) { $0.teacherSpeaker = speaker }
    }

    private func revealAudio() {
        let url = AppPaths.absolute(session.audioPath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}

/// The teacher's note for this session (D29): *Add Note* when empty; otherwise the text with Edit and Delete.
private struct NoteSection: View {
    @Environment(\.appDatabase) private var db
    let session: Session
    // A flag plus a plain String rather than `Binding($draft)`, which crashes when Cancel sets nil.
    @State private var isEditing = false
    @State private var draft = ""
    @State private var confirmingDelete = false
    @FocusState private var focused: Bool

    var body: some View {
        SectionCard("Note", systemImage: "note.text") {
            if !isEditing && !session.note.isEmpty {
                Group {
                    Button("Edit Note", systemImage: "pencil") { startEditing(session.note) }
                    Button("Delete Note", systemImage: "trash") { confirmingDelete = true }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        } content: {
            if isEditing {
                TextEditor(text: $draft)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 100)
                    .background(.background, in: .rect(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary) }
                    .focused($focused)
                    .onAppear { focused = true }
                    .onExitCommand { isEditing = false }
                HStack {
                    Spacer()
                    Button("Cancel") { isEditing = false }
                    Button("Save") { save(draft) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("Save (⌘↩)")
                }
            } else if session.note.isEmpty {
                Button("Add Note", systemImage: "plus") { startEditing("") }
            } else {
                Text(session.note).textSelection(.enabled)
            }
        }
        .confirmationDialog("Delete this note?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { save("") }
        }
    }

    private func save(_ text: String) {
        guard let id = session.id else { return }
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        try? db.updateSession(id: id) { $0.note = note }
        isEditing = false
    }

    private func startEditing(_ text: String) {
        draft = text
        isEditing = true
    }
}

/// A titled, rounded panel for one part of the session, so the parts read as separate blocks.
/// `accessory` sits right after the title (small buttons).
private struct SectionCard<Accessory: View, Content: View>: View {
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
