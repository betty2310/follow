# Roadmap

Status: `[ ]` todo, `[~]` in progress / stubbed, `[x]` done. Update this file as you work.

## M0: Bootstrap
- [x] Design interview, decisions (`docs/DECISIONS.md`)
- [x] XcodeGen project, engine protocols, app shell that builds
- [x] GRDB/SQLite database layer with migrations (`AppDatabase`)
- [x] Penguin emoji app icon with standard macOS sizes and asset catalog configuration

## M1: Groups & students
- [x] Import sheet: instructions, column mapping (auto-guess + manual), target group (existing/new), new/updated preview, name normalization (`ImportStudentsView`, `StudentImporter`)
- [x] Sidebar: search, Dashboard, Settings, group picker, student list
- [ ] Rename / delete group; edit a student's details

## M2: Recording
- [~] Record / stop with the Mac microphone → `.m4a` (`AudioRecorder`)
- [ ] Recording UI: timer and level meter; record the next student while others process
- [ ] Import an existing audio file into a session

## M3: Transcription
- [ ] `SonioxEngine` (default): upload → create transcription → poll → map tokens to utterances
- [ ] `GeminiTranscribeEngine`
- [ ] `DeepgramEngine`
- [ ] Settings: API keys (Keychain), default engine
- [ ] Comparison mode: run one session through all engines and show the transcripts side by side

## M4: Summarization
- [~] `ClaudeCLISummarizer` (`claude -p`), prompt + JSON parsing
- [ ] Teacher/Student labels in the transcript view + swap button
- [ ] Editable summary (markdown); re-run button

## M5: Progress
- [~] Dashboard: this-week stats, not-reported list, students × last 8 weeks grid (`DashboardView`)
- [ ] Student timeline: weekly summaries, newest first; previous week shown while recording

## Later / out of scope for v1
- Export (Markdown / PDF / Excel)
- Better speaker classification (voice enrollment of the teacher)
- Local/offline engines
