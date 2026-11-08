import Foundation

/// Any server with OpenAI's Chat Completions API: OpenAI itself or a compatible one (OpenRouter, a local server, …).
/// Docs: https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create, checked 2026-11-08.
/// Sends only `model` and `messages`, which every compatible server accepts; the reply is `choices[0].message.content`.
struct OpenAICompatibleSummarizer: SummarizationEngine {
    let id = "openai"
    let displayName = "OpenAI-compatible"
    var baseURL: String
    var model: String

    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-6.1-sol"

    enum Failure: LocalizedError {
        case invalidBaseURL(String)
        var errorDescription: String? {
            switch self { case .invalidBaseURL(let url): "Invalid base URL “\(url)”. Fix it in Settings." }
        }
    }

    func summarize(utterances: [Utterance], student: StudentInfo) async throws -> SummaryResult {
        let prompt = SummaryPrompt.build(utterances: utterances, student: student)
        return try Self.parse(response: try await SummaryAPI.send(request(prompt: prompt, apiKey: APIKeys.get(.openAI))))
    }

    /// The key is optional: local servers often don't need one.
    func request(prompt: String, apiKey: String?) throws -> URLRequest {
        guard let base = URL(string: baseURL), base.host() != nil else { throw Failure.invalidBaseURL(baseURL) }
        return try SummaryAPI.post(base.appending(path: "chat/completions"),
                                   headers: apiKey.map { ["Authorization": "Bearer \($0)"] } ?? [:],
                                   body: ["model": model, "messages": [["role": "user", "content": prompt]]])
    }

    /// Takes `choices[0].message.content` (or the refusal), then parses the JSON inside.
    static func parse(response: Data) throws -> SummaryResult {
        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String?; let refusal: String? }
                let message: Message
                let finish_reason: String?
            }
            let choices: [Choice]
        }
        let choice = try JSONDecoder().decode(Completion.self, from: response).choices.first
        let text = choice?.message.content ?? choice?.message.refusal ?? "No content, finish_reason: \(choice?.finish_reason ?? "none")"
        return try SummaryResult.parse(modelText: text)
    }
}
