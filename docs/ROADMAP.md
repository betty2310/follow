# Roadmap

Status: `[ ]` todo, `[~]` in progress / stubbed, `[x]` done. Update this file as you work.

## M0: Bootstrap
- [x] Design interview, decisions (`docs/DECISIONS.md`)
- [x] XcodeGen project, engine protocols, app shell that builds
- [x] GRDB/SQLite database layer with migrations (`AppDatabase`)
- [x] Penguin emoji app icon with standard macOS sizes and asset catalog configuration

## M1: Groups & students
- [x] Import sheet: instructions, column mapping (auto-guess + manual), target group (existing/new), new/updated preview, name normalization (`ImportStudentsView`, `StudentImporter`)
- [x] Sidebar: search, every group as a collapsible row with its students (folder icon, double-click toggles), group dashboard (D26)
- [x] Group management: new, rename, archive/unarchive, delete with confirmation (right-click menu), hide/show students (D25)
- [x] Add one student by hand: name + MSSV, optional email and project title (`StudentFormView`, D34)
- [x] Random animal emoji per student, click to change (`StudentEmojiButton`, D35)
- [x] Edit a student's details: right-click → Edit Student… (group, name, MSSV, email, project title; D37), plus the project title box on the student page (D29)

## M2: Recording
- [~] Record / stop with the Mac microphone → `.m4a` (`AudioRecorder`)
- [ ] Recording UI: timer and level meter; record the next student while others process
- [ ] Import an existing audio file into a session
- [x] Session card: Show in Finder button; Re-run also for sessions stuck in `recorded`

## M3: Transcription
- [x] `SonioxEngine` (default, `stt-async-v5`): upload → create transcription → poll → map tokens to utterances → delete remote file/transcription
- [ ] `GeminiTranscribeEngine`
- [ ] `DeepgramEngine`
- [x] Settings: API keys (UserDefaults, D31), default engine
- [ ] Comparison mode: run one session through all engines and show the transcripts side by side

## M4: Summarization
- [~] `ClaudeCLISummarizer` (`claude -p`), prompt + JSON parsing
- [x] Summarize on demand (**Summarize with AI**), transcription alone runs automatically; Set Teacher without a summary (D36)
- [x] Teacher/Student labels in the transcript view + swap button (`SessionDetailView`)
- [x] Editable summary (markdown) in the session edit sheet; re-run button (D29)

## M5: Progress
- [~] Dashboard: this-week stats, not-reported list, calendar with the number of students reported per day (`DashboardView`, D26)
- [x] ~~Student page: week calendar strip of sessions + detail of the selected session (D23)~~ replaced by the day board (D36)
- [x] Day board on the student page and group dashboard: every day oldest → today, pins per day, Days / Month switch (`SessionBoard`, D36)
- [x] Text notes as their own pins (session without audio), New Note composer, + on a day (`NoteComposerView`, D36)
- [x] Pin dialog: editable date, audio player (play from a transcript line), note, summary, transcript; right-click actions (`SessionDetailSheet`, D36)
- [x] Calendar follows the selected session; session sections as cards, summary and transcript side by side when wide; Record as the primary toolbar button; cross-fade between students (D33)
- [x] Week / Month switch on the student calendar (D24; Week became Days in D36)
- [ ] Previous week's summary shown while recording
- [x] Session edit (date, summary) / delete (recording to Trash), a note box per session, Notes inspector on the student page (`SessionNotesView`, D29; editing moved into the pin dialog, D36)

## Delivery
- [x] CI/CD: tests on PRs, build on `main`, GitHub Release on `v*` tags (D27)
- [x] In-app updates with Sparkle: check at launch + daily, version bubble in the sidebar, appcast published by the release workflow (D28)
- [x] Release builds signed with a self-signed certificate so permissions survive updates (D30)
- [x] Renamed ProjectRecord → Follow (app, bundle id, data folder, releases, repo); one-time move of the old data and settings at launch (`RenameMigration`, D32)

## Later / out of scope for v1
- Export (Markdown / PDF / Excel)
- Better speaker classification (voice enrollment of the teacher)
- Local/offline engines
