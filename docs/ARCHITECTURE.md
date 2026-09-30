# Architecture

## Pipeline

```
Record (AVAudioRecorder, .m4a)  ─┐
Import audio file ───────────────┤
                                 ▼
                         Session (status: recorded)
                                 │  TranscriptionEngine (Soniox | Gemini | Deepgram)
                                 ▼
                 Transcript: [Utterance(speaker: "A"/"B", text, start, end)]
                                 │  SummarizationEngine (ClaudeCLISummarizer → `claude -p`)
                                 ▼
          SummaryResult: teacherSpeaker ("A"/"B") + Vietnamese markdown summary
                                 │
                                 ▼
                         Session (status: done)
```

`SessionProcessor` runs the pipeline for a session. It is an actor, so multiple sessions can process in the background. It updates `Session.status` and stores errors on the session so the user can retry.

## Layout

```
ProjectRecord/
  App/            App entry, AppPaths (storage folder), Settings
  Models/         SwiftData models: Term, Student, Session (+ Utterance Codable)
  Engines/
    Transcription/  TranscriptionEngine protocol + providers
    Summarization/  SummarizationEngine protocol + ClaudeCLISummarizer
  Services/       AudioRecorder, SessionProcessor, StudentImporter (xlsx), Keychain, WeekCalendar
  Views/          SwiftUI views: ContentView (sidebar + SidebarItem routing), DashboardView, StudentDetailView, SettingsView
ProjectRecordTests/
```

## Models (SwiftData)

- **Term**: `name`, `createdAt`, `students`
- **Student**: `mssv`, `fullName`, `className`, `projectTitle`, `email`, `term`, `sessions`
- **Session**: `date`, `audioFileName` (relative to the storage root), `status`, `errorMessage`, `transcriptEngine`, `utterancesData` (JSON `[Utterance]`), `teacherSpeaker`, `summaryMarkdown`, `student`

The week is always **derived** from `Session.date` using an ISO-8601 calendar (Monday start). See `WeekCalendar`. It is never stored.

## Engines

```swift
protocol TranscriptionEngine: Sendable {
    var id: String { get }             // "soniox", "gemini", "deepgram"
    func transcribe(audioURL: URL, language: String) async throws -> [Utterance]
}

protocol SummarizationEngine: Sendable {
    func summarize(utterances: [Utterance], student: StudentInfo) async throws -> SummaryResult
}
```

To add a provider:
1. Add a file in `Engines/Transcription/`.
2. Register it in `EngineRegistry`.
3. If it needs a key, add it to Keychain via `KeychainKey`.

## Summarizer (`claude -p`)

- Runs `claude -p --model sonnet --output-format json` with `Process`. The prompt goes to stdin.
- The prompt asks for a JSON object `{ "teacher_speaker": "A"|"B", "summary_markdown": "..." }` and includes the Vietnamese template from `docs/DECISIONS.md`.
- The CLI's JSON envelope contains the model's text in the `result` field. Parse the inner JSON from that text.
- GUI apps don't inherit the shell `PATH`, so the CLI path must be **absolute** (default `~/.local/bin/claude`) and can be changed in Settings.

## Storage

`~/Documents/ProjectRecord/`
- `ProjectRecord.store`: the SwiftData store
- `audio/<term>/<MSSV>/<yyyy-MM-dd_HHmm>.m4a`

API keys are in Keychain (service `ProjectRecord`).
