<p align="center">
  <img src="docs/design/mascot.png" alt="Follow mascot: a white cat taking notes on a clipboard" width="320">
</p>

# Follow

A native macOS app for tracking weekly 1:1 project reports from students. It records each session, transcribes the Vietnamese conversation with speaker labels, and writes a Vietnamese summary.

- 📁 Organize students into groups; import each list from Excel with column mapping (names auto-normalized)
- 🎙️ Record a session per student per week (or import an audio file)
- 📝 Cloud transcription with diarization (Soniox by default; Gemini and Deepgram are pluggable)
- ✨ Vietnamese summary via the Anthropic API or any OpenAI-compatible API: *Đã làm được / Vấn đề gặp phải / Kế hoạch tuần tới / Góp ý & việc giao*
- ✅ See at a glance who has reported this week; read each student's weekly timeline

## Requirements
- macOS 26+ on Apple Silicon, Xcode 26+
- `brew install xcodegen`
- An API key for the summarizer (Anthropic, or an OpenAI-compatible server)
- An API key for the transcription provider (Soniox by default)

## Getting started
```bash
make run
```
Then open **Settings** (⌘,): paste your STT API key, pick the summarization provider and paste its API key.

Data is stored in `~/Documents/Follow/`: `Follow.sqlite` plus `audio/`.

## Docs
- [AGENTS.md](AGENTS.md): contributor/agent guide
- [docs/DECISIONS.md](docs/DECISIONS.md): product & technical decisions
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how it fits together
- [docs/ROADMAP.md](docs/ROADMAP.md): what's done and what's next
