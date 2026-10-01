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

`SessionProcessor.process(sessionId:db:)` runs the pipeline off the main actor. It writes status and results to the DB at each step, and the UI updates through observations. Errors are stored on the session so the user can retry.

## Layout

```
ProjectRecord/
  App/            App entry, AppPaths (storage folder), Settings
  Database/       AppDatabase (GRDB: schema/migrations, observations, writes) + Records (StudentGroup, GroupProgress, Student, Session, Utterance, StudentProgress)
  Engines/
    Transcription/  TranscriptionEngine protocol + providers
    Summarization/  SummarizationEngine protocol + ClaudeCLISummarizer
  Services/       AudioRecorder, SessionProcessor, StudentImporter (xlsx), Keychain, WeekCalendar
  Views/          SwiftUI views: ContentView (sidebar + SidebarItem routing), DashboardView (report calendar), ImportStudentsView, StudentDetailView (SessionCalendarView + SessionDetailView), CalendarView (shared Week/Month calendar), SettingsView (⌘, window)
ProjectRecordTests/
  Fixtures/       Sample files with fake data (never commit real student data)
```

## Database (GRDB / SQLite)

File: `~/Documents/ProjectRecord/ProjectRecord.sqlite`. Open it with any SQLite viewer.

| Table | Columns |
|---|---|
| `studentGroup` | `id`, `name`, `createdAt`, `archivedAt` (null = active) |
| `student` | `id`, `groupId` → studentGroup (cascade), `mssv`, `fullName`, `className`, `projectTitle`, `email`; unique (`groupId`, `mssv`) |
| `session` | `id`, `studentId` → student (cascade), `date`, `audioPath`, `status`, `errorMessage`, `transcriptEngine`, `utterances` (JSON), `teacherSpeaker`, `summaryMarkdown` |

Rules:
- **Only `AppDatabase` touches SQL.** Views read with `db.observeX()` inside `.task { for try await … }` and write with `AppDatabase` methods.
- Schema changes are made by **appending a migration** in `AppDatabase.migrator`. Never edit a shipped migration.
- Dates are stored as local time with offset (`2026-09-30 10:37:39.175+07:00`) through `DBTimestamp` / `LocalTimestampRecord`. A record with a `Date` must adopt `LocalTimestampRecord`, and raw SQL must parse dates with `DBTimestamp.date`. Utterance times are seconds.
- Tests use `AppDatabase.inMemory()`.
- `AppDatabase` is injected with `.environment(\.appDatabase, …)`.
- The week is always **derived** from `session.date` (ISO, Monday start, see `WeekCalendar`). It is never stored.

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
- `ProjectRecord.sqlite`: the GRDB/SQLite database
- `audio/<group>/<MSSV>/<yyyy-MM-dd_HHmm>.m4a`

API keys are in Keychain (service `ProjectRecord`).
