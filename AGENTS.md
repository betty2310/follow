# AGENTS.md

Guide for AI agents (and humans) working on **ProjectRecord**. Read this first, then `docs/DECISIONS.md`.

## What this is
A personal native macOS app for a teacher who mentors ~30 students on their own projects. Each week every student has a 5–10 min in-person 1:1 session **in Vietnamese**. The app:
1. imports the term's student list from `.xlsx`,
2. records each session (Mac mic → `.m4a`),
3. transcribes it with a **cloud STT with speaker diarization**,
4. summarizes it in Vietnamese with **`claude -p`**, inferring which speaker is the teacher,
5. shows who has reported each week, plus a per-student timeline of summaries.

## Must-read docs
- `docs/DECISIONS.md`: settled product/tech decisions (D1–D16), summary template, STT research. **Don't re-open these without asking the owner.**
- `docs/ARCHITECTURE.md`: pipeline, layout, models, engine protocols, storage.
- `docs/ROADMAP.md`: milestones and status. **Update checkboxes when you finish work.**

## Commands
```bash
make gen     # regenerate ProjectRecord.xcodeproj from project.yml (XcodeGen)
make build   # generate + build
make test    # generate + run unit tests (Swift Testing)
make run     # build + open the app
```
- `ProjectRecord.xcodeproj` is **generated and git-ignored**. Change `project.yml`, never the `.xcodeproj`. Adding a Swift file under `ProjectRecord/` needs no project change; just run `make gen`.
- Requirements: macOS 26+, Xcode 26+, `brew install xcodegen`.

## Conventions
- Swift 6 (strict concurrency), SwiftUI, SwiftData, `@Observable`. Swift Testing (`import Testing`) for tests.
- **UI text in English.** Generated content (summaries, prompts) in **Vietnamese**.
- Engines are pluggable: add providers behind `TranscriptionEngine` / `SummarizationEngine` and register them in `EngineRegistry`. Views and models must not know about specific providers.
- Put logic in `Services/` or `Engines/` as pure, testable functions (see `StudentImporter.rows(from:)`, `ClaudeCLISummarizer.parse`). Keep views thin.
- Weeks are **derived** from `Session.date` via `WeekCalendar` (ISO Mon–Sun). Never store a week number.
- Secrets live in Keychain (`Keychain`, `KeychainKey`). Never commit API keys or put them in `UserDefaults`.
- Data lives in `~/Documents/ProjectRecord/` (`AppPaths`). Audio paths are stored **relative** to that root.
- Not sandboxed, not for the App Store: the app spawns the `claude` CLI via `Process` using an absolute path (GUI apps don't get the shell `PATH`).
- Before implementing a cloud STT provider, **read its current API docs** (links in `Providers.swift`). APIs in this area change often.
- Keep it simple. The owner explicitly rejected over-engineering (e.g. no structured action-item tracking, no export in v1).

## Gotchas
- `claude -p --output-format json` returns an envelope; the model text is in `result` and may be wrapped in ```json fences. `ClaudeCLISummarizer.parse` handles this, so keep its test green.
- Microphone permission comes from `NSMicrophoneUsageDescription` in `project.yml`. Ad-hoc signing may re-prompt after rebuilds.
- Diarization labels (A/B) are anonymous. `Session.teacherSpeaker` records which one is the teacher. The UI must allow swapping it.

## Definition of done
`make test` passes, new logic has tests, `docs/ROADMAP.md` is updated, and decisions that change are recorded in `docs/DECISIONS.md` with a date.
