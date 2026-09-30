# Roadmap

Status: `[ ]` todo, `[~]` in progress / stubbed, `[x]` done. Update this file as you work.

## M0: Bootstrap
- [x] Design interview, decisions (`docs/DECISIONS.md`)
- [x] XcodeGen project, SwiftData models, engine protocols, app shell that builds

## M1: Students
- [~] Import `.xlsx` → new Term + Students (`StudentImporter`; needs real-file testing)
- [ ] Term picker in sidebar; student list with search

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
- [ ] Students × weeks grid (reported / not reported)
- [ ] Student timeline: weekly summaries, newest first; previous week shown while recording

## Later / out of scope for v1
- Excel re-import / merge by MSSV
- Export (Markdown / PDF / Excel)
- Better speaker classification (voice enrollment of the teacher)
- Local/offline engines
