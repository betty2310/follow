import Foundation

/// Default summarizer. Claude Messages API (docs: https://platform.claude.com/docs/en/api/messages, checked 2026-11-08):
/// one `POST /v1/messages` with the prompt as the user message; the reply's `text` blocks hold the JSON.
struct AnthropicSummarizer: SummarizationEngine {
    let id = "anthropic"
    let displayName = "Anthropic (Claude)"
    var model: String

    static let defaultModel = "claude-sonnet-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func summarize(utterances: [Utterance], student: StudentInfo) async throws -> SummaryResult {
        guard let apiKey = APIKeys.get(.anthropic) else { throw SummarizationError.missingAPIKey(displayName) }
        let prompt = SummaryPrompt.build(utterances: utterances, student: student)
        return try Self.parse(response: try await SummaryAPI.send(request(prompt: prompt, apiKey: apiKey)))
    }

    func request(prompt: String, apiKey: String) throws -> URLRequest {
        try SummaryAPI.post(Self.endpoint, headers: [
            "Authorization": "Bearer \(apiKey)",
            "anthropic-version": "2026-10-21",
        ], body: [
            "model": model,
            // Includes adaptive thinking, which can't be turned off on Sonnet 5.5; the summary itself is short.
            "max_tokens": 16000,
            "messages": [["role": "user", "content": prompt]],
        ])
    }

    /// Joins the `text` blocks of a Messages API response (skipping `thinking` blocks), then parses the JSON inside.
    static func parse(response: Data) throws -> SummaryResult {
        struct Message: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
            let stop_reason: String?
        }
        let message = try JSONDecoder().decode(Message.self, from: response)
        let text = message.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        return try SummaryResult.parse(modelText: text.isEmpty ? "No text, stop_reason: \(message.stop_reason ?? "none")" : text)
    }
}
