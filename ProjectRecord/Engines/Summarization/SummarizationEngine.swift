import Foundation

struct StudentInfo: Sendable {
    var fullName: String
    var projectTitle: String
}

struct SummaryResult: Codable, Sendable, Equatable {
    /// Diarized speaker label ("A"/"B") inferred to be the teacher.
    var teacherSpeaker: String
    /// Vietnamese markdown following the template in docs/DECISIONS.md.
    var summaryMarkdown: String

    enum CodingKeys: String, CodingKey {
        case teacherSpeaker = "teacher_speaker"
        case summaryMarkdown = "summary_markdown"
    }
}

protocol SummarizationEngine: Sendable {
    func summarize(utterances: [Utterance], student: StudentInfo) async throws -> SummaryResult
}

enum SummaryPrompt {
    static func build(utterances: [Utterance], student: StudentInfo) -> String {
        let transcript = utterances.map { "[\($0.speaker)] \($0.text)" }.joined(separator: "\n")
        return """
        Bạn là trợ lý của một giáo viên hướng dẫn đồ án. Dưới đây là bản ghi cuộc trao đổi 1-1 hằng tuần \
        giữa giáo viên và sinh viên \(student.fullName) (đề tài: \(student.projectTitle.isEmpty ? "chưa rõ" : student.projectTitle)).
        Các người nói được gán nhãn ẩn danh (A, B, ...).

        Nhiệm vụ:
        1. Xác định nhãn nào là GIÁO VIÊN dựa vào ngữ cảnh (người đặt câu hỏi, góp ý, giao việc).
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
