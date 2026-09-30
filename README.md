# ProjectRecord

A native macOS app for tracking weekly 1:1 project reports from students. It records each session, transcribes the Vietnamese conversation with speaker labels, and writes a Vietnamese summary.

- 📁 Organize students into groups; import each list from Excel with column mapping (names auto-normalized)
- 🎙️ Record a session per student per week (or import an audio file)
- 📝 Cloud transcription with diarization (Soniox by default; Gemini and Deepgram are pluggable)
- ✨ Vietnamese summary via `claude -p`: *Đã làm được / Vấn đề gặp phải / Kế hoạch tuần tới / Góp ý & việc giao*
- ✅ See at a glance who has reported this week; read each student's weekly timeline

## Requirements
- macOS 26+ on Apple Silicon, Xcode 26+
- `brew install xcodegen`
- [Claude Code](https://claude.com/claude-code) CLI logged in (`claude -p` must work in your terminal)
- An API key for the transcription provider (Soniox by default)

## Getting started
```bash
make run
```
Then open **Settings** (⌘,): paste your STT API key and check the `claude` path (default `~/.local/bin/claude`).

Data is stored in `~/Documents/ProjectRecord/`: `ProjectRecord.sqlite` plus `audio/`.

## Docs
- [AGENTS.md](AGENTS.md): contributor/agent guide
- [docs/DECISIONS.md](docs/DECISIONS.md): product & technical decisions
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how it fits together
- [docs/ROADMAP.md](docs/ROADMAP.md): what's done and what's next
