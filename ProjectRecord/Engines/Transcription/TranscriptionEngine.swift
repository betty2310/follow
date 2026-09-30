import Foundation

protocol TranscriptionEngine: Sendable {
    /// Stable identifier stored on `Session.transcriptEngine`, e.g. "soniox".
    var id: String { get }
    var displayName: String { get }
    /// Transcribe with speaker diarization. `language` is a BCP-47 code, "vi" by default.
    func transcribe(audioURL: URL, language: String) async throws -> [Utterance]
}

enum TranscriptionError: LocalizedError {
    case missingAPIKey(String)
    case http(Int, String)
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let engine): "Missing API key for \(engine). Add it in Settings."
        case .http(let code, let body): "HTTP \(code): \(body)"
        case .notImplemented(let engine): "\(engine) is not implemented yet."
        }
    }
}

enum EngineRegistry {
    static let transcriptionEngines: [any TranscriptionEngine] = [
        SonioxEngine(),
        GeminiTranscribeEngine(),
        DeepgramEngine(),
    ]

    static func transcription(id: String) -> any TranscriptionEngine {
        transcriptionEngines.first { $0.id == id } ?? SonioxEngine()
    }

    static func summarizer() -> any SummarizationEngine {
        ClaudeCLISummarizer(cliPath: AppSettings.claudeCLIPath, model: AppSettings.claudeModel)
    }
}
