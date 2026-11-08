# Architecture

## Pipeline

```
New Note ──────────────────────────────▶ Session (audioPath NULL, status: done, note)

Record (AVAudioRecorder, .m4a)  ─┐
Import audio file ───────────────┤
                                 ▼
                         Session (status: recorded)
                                 │  automatic: TranscriptionEngine (Soniox | Gemini | Deepgram)
                                 ▼
                 Transcript: [Utterance(speaker: "A"/"B", text, start, end)]   (status: done)
                                 ┆  on demand ("Summarize with AI"): SummarizationEngine (Anthropic | OpenAI-compatible)
                                 ▼
          SummaryResult: teacherSpeaker ("A"/"B") + Vietnamese markdown summary   (status: done)
```

A session is one **pin** on the day board (D36): a recording, or a text note (no audio). `SessionProcessor.transcribe(sessionId:db:)` runs after Stop; `SessionProcessor.summarize(sessionId:db:)` only when the teacher asks. Both run off the main actor, write status and results to the DB as they go, and the UI updates through observations. Errors are stored on the session so the user can retry.

## Layout

```
Follow/
  App/            App entry, AppPaths (storage folder), Settings
  Database/       AppDatabase (GRDB: schema/migrations, observations, writes) + Records (StudentGroup, GroupProgress, Student, Session, Utterance, StudentProgress)
  Engines/
    Transcription/  TranscriptionEngine protocol + providers
    Summarization/  SummarizationEngine protocol, SummaryPrompt, SummaryResult.parse + providers (Anthropic, OpenAI-compatible)
  Services/       AudioRecorder, AudioPlayer (session dialog), SessionProcessor, StudentImporter (xlsx), APIKeys, WeekCalendar, AppUpdater (Sparkle), RenameMigration (one-time move from the old ProjectRecord name, D32)
  Views/          SwiftUI views: ContentView (sidebar + SidebarItem routing), DashboardView (stats + day board), StudentDetailView (title + day board, SessionNotesView inspector), SessionBoard (D36 day board: Days/Month, pins, context menu, SessionActions), SessionDetailSheet (pin dialog), NoteComposerView (new note), MonthGrid, ImportStudentsView, StudentFormView (add / edit student), SettingsView (⌘, window)
FollowTests/
  Fixtures/       Sample files with fake data (never commit real student data)
```

## Database (GRDB / SQLite)

File: `~/Documents/Follow/Follow.sqlite`. Open it with any SQLite viewer.

| Table | Columns |
|---|---|
| `studentGroup` | `id`, `name`, `createdAt`, `archivedAt` (null = active) |
| `student` | `id`, `groupId` → studentGroup (cascade), `mssv`, `fullName`, `className`, `projectTitle`, `email`; unique (`groupId`, `mssv`) |
| `session` | `id`, `studentId` → student (cascade), `date`, `audioPath` (NULL = text note, D36), `status`, `errorMessage`, `transcriptEngine`, `utterances` (JSON), `teacherSpeaker`, `summaryMarkdown`, `note` (teacher's own note, D29) |

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
    func transcribe(audioURL: URL, language: String, student: StudentInfo) async throws -> [Utterance]
}

protocol SummarizationEngine: Sendable {
    var id: String { get }             // "anthropic", "openai"
    func summarize(utterances: [Utterance], student: StudentInfo) async throws -> SummaryResult
}
```

To add a provider:
1. Add a file in `Engines/Transcription/` or `Engines/Summarization/`.
2. Register it in `EngineRegistry`.
3. If it needs a key, add a case to `APIKey`.

## Summarizers (D39)

- `SummaryPrompt.build` makes one Vietnamese prompt that asks for a JSON object `{ "teacher_speaker": "A"|"B"|null, "summary_markdown": "..." }` and includes the template from `docs/DECISIONS.md`. It is sent as the only user message.
- `AnthropicSummarizer`: `POST https://api.anthropic.com/v1/messages` with `Authorization: Bearer <key>` and `anthropic-version: 2026-10-21`. `parse(response:)` joins the `text` content blocks (skipping `thinking` blocks).
- `OpenAICompatibleSummarizer`: `POST <base URL>/chat/completions`, `Authorization: Bearer <key>` only when a key is set. Sends just `model` and `messages`. `parse(response:)` takes `choices[0].message.content`.
- Both hand the model text to `SummaryResult.parse(modelText:)`, which takes the outermost `{…}` (the model may wrap it in ```json fences). Errors show the provider's `error.message`.
- Settings: `summarizationEngineID`, `anthropicModel`, `openAIBaseURL`, `openAIModel` in UserDefaults (`AppSettings`, an empty field means the default); keys in `APIKeys`.

## Storage

`~/Documents/Follow/`
- `Follow.sqlite`: the GRDB/SQLite database
- `audio/<group>/<MSSV>/<yyyy-MM-dd_HHmm>.m4a`

API keys are in UserDefaults (`APIKeys`, D31).

Before the rename to Follow (D32) this was `~/Documents/ProjectRecord/ProjectRecord.sqlite`; `RenameMigration` moves it at launch. Unit tests run inside the app and use an in-memory database, so they never touch this folder.

## Updates (Sparkle)

```
git tag v1.2.0 && git push origin v1.2.0
  → release.yml: import certificate (D30) → make release VERSION=1.2.0 (signed) → generate_appcast (EdDSA, secret SPARKLE_PRIVATE_KEY)
  → GitHub Release assets: Follow-1.2.0.zip + appcast.xml
App (SUFeedURL = releases/latest/download/appcast.xml)
  → AppUpdater: check at launch + daily → UpdateStatus → sidebar version label / bubble
  → Sparkle window: download, verify EdDSA, replace the app, relaunch
```

- `AppUpdater` (`@Observable`, injected with `.environment(updater)`) wraps `SPUStandardUpdaterController` and is the Sparkle delegate. It does nothing under unit tests, and Debug builds only check when asked.
- Feed URL, public key and the daily interval are Info.plist keys in `project.yml`. Never change `SUPublicEDKey` without keeping the private key: installed apps would reject every later update.
- The Sparkle tools (`generate_keys`, `sign_update`, `generate_appcast`) are in `build/SourcePackages/artifacts/sparkle/Sparkle/bin/` after a build.
- Two keys, two jobs: the **EdDSA key** proves an update came from us (Sparkle checks it); the **code signing certificate** (D30) keeps the app's identity stable, so macOS keeps its permissions after an update.
