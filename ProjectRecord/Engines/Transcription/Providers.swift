import Foundation

// Provider stubs. Implement each in its own file when you work on it (see docs/ROADMAP.md, M3).
// Read the provider's current API docs before implementing; do not rely on memory.

/// Default engine. Async API: upload file → create transcription (diarization on, language hint "vi") → poll → fetch tokens.
/// Docs: https://soniox.com/docs
struct SonioxEngine: TranscriptionEngine {
    let id = "soniox"
    let displayName = "Soniox"
    func transcribe(audioURL: URL, language: String) async throws -> [Utterance] {
        guard Keychain.get(.soniox) != nil else { throw TranscriptionError.missingAPIKey(displayName) }
        throw TranscriptionError.notImplemented(displayName)
    }
}

/// Gemini 3.5 Transcribe (preview). Single call, diarization, custom vocabulary.
/// Docs: https://ai.google.dev/gemini-api/docs/models/gemini-3.5-transcribe
struct GeminiTranscribeEngine: TranscriptionEngine {
    let id = "gemini"
    let displayName = "Gemini 3.5 Transcribe"
    func transcribe(audioURL: URL, language: String) async throws -> [Utterance] {
        guard Keychain.get(.gemini) != nil else { throw TranscriptionError.missingAPIKey(displayName) }
        throw TranscriptionError.notImplemented(displayName)
    }
}

/// Deepgram Nova-3. Single sync POST of raw audio bytes with `diarize=true&language=vi`.
/// Docs: https://developers.deepgram.com
struct DeepgramEngine: TranscriptionEngine {
    let id = "deepgram"
    let displayName = "Deepgram Nova-3"
    func transcribe(audioURL: URL, language: String) async throws -> [Utterance] {
        guard Keychain.get(.deepgram) != nil else { throw TranscriptionError.missingAPIKey(displayName) }
        throw TranscriptionError.notImplemented(displayName)
    }
}
