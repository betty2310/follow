import AppKit
import SwiftUI

/// Everything about one recording: status and actions, the teacher's note, the Vietnamese summary, and the labeled transcript.
struct SessionDetailView: View {
    @Environment(\.appDatabase) private var db
    let session: Session
    var onRerun: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let err = session.errorMessage, session.status == .failed {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).textSelection(.enabled)
                }
                NoteSection(session: session).id(session.id)
                section("Summary") {
                    if let md = session.summaryMarkdown, !md.isEmpty {
                        MarkdownText(markdown: md)
                    } else {
                        placeholder
                    }
                }
                section("Transcript") {
                    if session.utterances.isEmpty {
                        placeholder
                    } else {
                        transcript
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
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
            Spacer()
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
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let swapped = session.swappedTeacherSpeaker, session.teacherSpeaker != nil {
                Button("Swap Teacher / Student", systemImage: "arrow.left.arrow.right") { setTeacher(swapped) }
                    .controlSize(.small)
            }
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

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold())
            content()
        }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Note").font(.title3.bold())
                if !isEditing && !session.note.isEmpty {
                    Group {
                        Button("Edit Note", systemImage: "pencil") { startEditing(session.note) }
                        Button("Delete Note", systemImage: "trash") { confirmingDelete = true }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
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
