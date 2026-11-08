import Foundation

protocol TranscriptionEngine: Sendable {
    /// Stable identifier stored on `Session.transcriptEngine`, e.g. "soniox".
    var id: String { get }
    var displayName: String { get }
    /// Transcribe with speaker diarization. `language` is a BCP-47 code, "vi" by default.
    /// `student` lets engines that accept context or custom vocabulary use the student's name and project.
    func transcribe(audioURL: URL, language: String, student: StudentInfo) async throws -> [Utterance]
}

enum TranscriptionError: LocalizedError {
    case missingAPIKey(String)
    case http(Int, String)
    case notImplemented(String)
    case providerFailed(String, String)
    case emptyTranscript(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let engine): "Missing API key for \(engine). Add it in Settings."
        case .http(let code, let body): "HTTP \(code): \(body)"
        case .notImplemented(let engine): "\(engine) is not implemented yet."
        case .providerFailed(let engine, let message): "\(engine) failed: \(message)"
        case .emptyTranscript(let engine): "\(engine) returned no speech for this recording."
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

    /// Built from the current Settings, so a changed model or base URL applies to the next summary.
    static var summarizationEngines: [any SummarizationEngine] {
        [
            AnthropicSummarizer(model: AppSettings.anthropicModel),
            OpenAICompatibleSummarizer(baseURL: AppSettings.openAIBaseURL, model: AppSettings.openAIModel),
        ]
    }

    static func summarizer(id: String = AppSettings.summarizationEngineID) -> any SummarizationEngine {
        summarizationEngines.first { $0.id == id } ?? summarizationEngines[0]
    }
}
