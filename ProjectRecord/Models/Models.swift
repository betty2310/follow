import Foundation
import SwiftData

@Model
final class Term {
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Student.term)
    var students: [Student] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}

@Model
final class Student {
    var mssv: String
    var fullName: String
    var className: String
    var projectTitle: String
    var email: String
    var term: Term?
    @Relationship(deleteRule: .cascade, inverse: \Session.student)
    var sessions: [Session] = []

    init(mssv: String, fullName: String, className: String = "", projectTitle: String = "", email: String = "") {
        self.mssv = mssv
        self.fullName = fullName
        self.className = className
        self.projectTitle = projectTitle
        self.email = email
    }
}

enum SessionStatus: String, Codable, Sendable {
    case recording, recorded, transcribing, summarizing, done, failed
}

@Model
final class Session {
    var date: Date
    /// Path relative to `AppPaths.root`.
    var audioFileName: String
    var statusRaw: String = SessionStatus.recorded.rawValue
    var errorMessage: String?
    var transcriptEngine: String?
    var utterancesData: Data?
    /// "A" / "B": which diarized speaker is the teacher (inferred by the summarizer, swappable in UI).
    var teacherSpeaker: String?
    var summaryMarkdown: String?
    var student: Student?

    init(date: Date = .now, audioFileName: String) {
        self.date = date
        self.audioFileName = audioFileName
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var utterances: [Utterance] {
        get { utterancesData.flatMap { try? JSONDecoder().decode([Utterance].self, from: $0) } ?? [] }
        set { utterancesData = try? JSONEncoder().encode(newValue) }
    }
}

/// One diarized chunk of speech returned by a `TranscriptionEngine`.
struct Utterance: Codable, Hashable, Sendable {
    var speaker: String   // "A", "B", ...
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}
