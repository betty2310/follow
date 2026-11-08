import Foundation

struct StudentInfo: Sendable {
    var fullName: String
    var projectTitle: String
}

struct SummaryResult: Codable, Sendable, Equatable {
    /// Diarized speaker label ("A"/"B") inferred to be the teacher; nil when it can't tell
    /// (e.g. a few seconds of audio with a single speaker).
    var teacherSpeaker: String?
    /// Vietnamese markdown following the template in docs/DECISIONS.md.
    var summaryMarkdown: String

    enum CodingKeys: String, CodingKey {
        case teacherSpeaker = "teacher_speaker"
        case summaryMarkdown = "summary_markdown"
    }
}

extension SummaryResult {
    /// Parses the JSON object the prompt asks for out of the model's text, which may wrap it in ```json fences.
    static func parse(modelText text: String) throws -> SummaryResult {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let result = try? JSONDecoder().decode(SummaryResult.self, from: Data(text[open...close].utf8))
        else { throw SummarizationError.unparsable(text) }
        return result
    }
}

protocol SummarizationEngine: Sendable {
    /// Stable identifier stored in Settings, e.g. "anthropic".
    var id: String { get }
    var displayName: String { get }
    func summarize(utterances: [Utterance], student: StudentInfo) async throws -> SummaryResult
}

enum SummarizationError: LocalizedError {
    case missingAPIKey(String)
    case http(Int, String)
    case unparsable(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let engine): "Missing API key for \(engine). Add it in Settings."
        case .http(let code, let message): "HTTP \(code): \(message)"
        case .unparsable(let text): "Could not parse summary JSON: \(text.prefix(300))"
        }
    }
}

enum SummaryAPI {
    /// A JSON POST with a long timeout: a summary can take a few minutes.
    static func post(_ url: URL, headers: [String: String], body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Sends a request and returns the body of a 2xx response. Both providers report errors as
    /// `{"error": {"message": "..."}}`; that message is shown, else the start of the body.
    static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            struct Body: Decodable { struct Detail: Decodable { let message: String }; let error: Detail }
            let message = (try? JSONDecoder().decode(Body.self, from: data).error.message)
                ?? String(decoding: data.prefix(500), as: UTF8.self)
            throw SummarizationError.http(code, message)
        }
        return data
    }
}

enum SummaryPrompt {
    static func build(utterances: [Utterance], student: StudentInfo) -> String {
        let transcript = utterances.map { "[\($0.speaker)] \($0.text)" }.joined(separator: "\n")
        return """
        Bạn là trợ lý của một giáo viên hướng dẫn đồ án. Dưới đây là bản ghi cuộc trao đổi 1-1 hằng tuần \
        giữa giáo viên và sinh viên \(student.fullName) (đề tài: \(student.projectTitle.isEmpty ? "chưa rõ" : student.projectTitle)).
        Các người nói được gán nhãn ẩn danh (A, B, ...).

        Nhiệm vụ:
        1. Xác định nhãn nào là GIÁO VIÊN dựa vào ngữ cảnh (người đặt câu hỏi, góp ý, giao việc). \
        Nếu không thể xác định, dùng null cho "teacher_speaker".
        2. Tóm tắt bằng tiếng Việt, ngắn gọn, theo đúng mẫu markdown sau:

        ## Đã làm được
        ## Vấn đề gặp phải
        ## Kế hoạch tuần tới
        ## Góp ý & việc giáo viên giao

        Chỉ trả về một đối tượng JSON duy nhất, không kèm văn bản nào khác:
        {"teacher_speaker": "A", "summary_markdown": "..."}

        Bản ghi:
        \(transcript)
        """
    }
}
