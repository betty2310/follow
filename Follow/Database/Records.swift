import Foundation
import GRDB

// Plain value types persisted with GRDB. Schema lives in AppDatabase.migrator; keep both in sync.

/// How dates are stored in SQLite (docs/DECISIONS.md D22): readable **local time with UTC offset**,
/// e.g. `2026-09-30 10:37:39.175+07:00`. Never epoch numbers, never bare UTC.
/// Records with `Date` properties must adopt `LocalTimestampRecord`.
enum DBTimestamp {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSXXXXX"
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ string: String) -> Date? { formatter.date(from: string) }
}

protocol LocalTimestampRecord: FetchableRecord, EncodableRecord {}

extension LocalTimestampRecord {
    static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .formatted(DBTimestamp.formatter)
    }
    static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .formatted(DBTimestamp.formatter)
    }
}

/// A folder of students the teacher organizes together (e.g. "Đồ án 1 – 2025.1").
/// Not to be confused with `Student.projectTitle`, which is the student's own project.
struct StudentGroup: Codable, Hashable, Identifiable, Sendable, MutablePersistableRecord, LocalTimestampRecord {
    var id: Int64?
    var name: String
    var createdAt: Date
    /// Set when the teacher archives the group: it moves to the sidebar's Archived section. Nothing is deleted.
    var archivedAt: Date?

    static let databaseTableName = "studentGroup"

    init(id: Int64? = nil, name: String, createdAt: Date = .now, archivedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }

    var isArchived: Bool { archivedAt != nil }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    enum Columns {
        static let name = Column(CodingKeys.name)
        static let createdAt = Column(CodingKeys.createdAt)
        static let archivedAt = Column(CodingKeys.archivedAt)
    }
}

/// A group with its students' progress: one sidebar section.
struct GroupProgress: Hashable, Identifiable, Sendable {
    var group: StudentGroup
    var students: [StudentProgress]
    var id: Int64 { group.id! }
}

struct Student: Codable, Hashable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var groupId: Int64
    var mssv: String
    var fullName: String
    var className: String
    /// The student's own project (Tên đề tài).
    var projectTitle: String
    var email: String
    /// An animal emoji shown next to the name, just for fun (D35). Picked at random on insert when empty.
    var emoji: String = ""

    mutating func willInsert(_ db: Database) throws {
        guard emoji.isEmpty else { return }
        let used = try String.fetchAll(db, sql: "SELECT emoji FROM student WHERE groupId = ?", arguments: [groupId])
        emoji = AnimalEmoji.random(avoiding: used)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    enum Columns {
        static let groupId = Column(CodingKeys.groupId)
        static let mssv = Column(CodingKeys.mssv)
        static let fullName = Column(CodingKeys.fullName)
    }
}

enum SessionStatus: String, Codable, Sendable {
    case recording, recorded, transcribing, summarizing, done, failed
}

/// One pin on the day board (D36): a recording (audio → transcript → optional summary) or, when
/// `audioPath` is nil, a text note the teacher typed. Either one counts as the student reporting that day.
struct Session: Codable, Hashable, Identifiable, Sendable, MutablePersistableRecord, LocalTimestampRecord {
    var id: Int64?
    var studentId: Int64
    var date: Date
    /// Path relative to `AppPaths.root`; nil for a text note.
    var audioPath: String?
    var status: SessionStatus = .recorded
    var errorMessage: String?
    var transcriptEngine: String?
    /// Stored as JSON text.
    var utterances: [Utterance] = []
    /// "A" / "B": which diarized speaker is the teacher (inferred by the summarizer, swappable in UI).
    var teacherSpeaker: String?
    var summaryMarkdown: String?
    /// The teacher's own free text: the whole content of a text note, an extra note on a recording.
    /// Not used by the pipeline (D29).
    var note: String = ""

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    enum Columns {
        static let studentId = Column(CodingKeys.studentId)
        static let date = Column(CodingKeys.date)
    }
}

extension Session {
    var hasAudio: Bool { audioPath != nil }

    /// A recording can be transcribed (again) once recording stopped and nothing else is running.
    var canTranscribe: Bool { hasAudio && [.recorded, .failed, .done].contains(status) }

    /// Summarizing is on demand (D36) and needs a transcript.
    var canSummarize: Bool { !utterances.isEmpty && [.failed, .done].contains(status) }

    /// "Transcribed" / "Summarized" for a finished recording, otherwise the pipeline status.
    var statusLabel: String {
        guard status == .done else { return status.label }
        return summaryMarkdown?.isEmpty == false ? "Summarized" : "Transcribed"
    }

    /// The few lines a pin shows: a text note's text; for a recording its summary (headings and
    /// bullets stripped), else its note, else the start of the transcript. Empty when there's nothing yet.
    var preview: String {
        if let summary = summaryMarkdown, !summary.isEmpty {
            return summary.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                .map { $0.hasPrefix("- ") || $0.hasPrefix("* ") ? String($0.dropFirst(2)) : $0 }
                .joined(separator: "\n")
        }
        if !note.isEmpty { return note }
        return utterances.prefix(6).map(\.text).joined(separator: " ")
    }

    /// Diarized speaker labels in order of first appearance ("A", "B", …).
    var speakers: [String] {
        var seen: [String] = []
        for u in utterances where !seen.contains(u.speaker) { seen.append(u.speaker) }
        return seen
    }

    /// "Teacher" / "Student" once the teacher is known, otherwise the raw label ("Speaker A").
    func roleName(of speaker: String) -> String {
        guard let teacherSpeaker else { return "Speaker \(speaker)" }
        return speaker == teacherSpeaker ? "Teacher" : "Student"
    }

    /// The label the teacher becomes after pressing Swap: the next speaker after the current teacher.
    var swappedTeacherSpeaker: String? {
        let all = speakers
        guard all.count > 1 else { return nil }
        guard let teacherSpeaker, let i = all.firstIndex(of: teacherSpeaker) else { return all[0] }
        return all[(i + 1) % all.count]
    }
}

/// One diarized chunk of speech returned by a `TranscriptionEngine`.
struct Utterance: Codable, Hashable, Sendable {
    var speaker: String   // "A", "B", ...
    var text: String
    /// Seconds from the start of the recording.
    var start: TimeInterval
    /// Seconds from the start of the recording.
    var end: TimeInterval
}

/// A session with its student, for boards that show several students' pins (the group dashboard).
struct StudentSession: Hashable, Identifiable, Sendable {
    var session: Session
    var student: Student
    var id: Int64 { session.id! }
}

/// A student plus the dates of their sessions: enough for the sidebar ✓ and the dashboard grid.
struct StudentProgress: Hashable, Identifiable, Sendable {
    var student: Student
    var sessionDates: [Date]
    var id: Int64 { student.id! }

    func hasReported(in week: WeekID) -> Bool {
        sessionDates.contains { WeekCalendar.week(of: $0) == week }
    }
}
