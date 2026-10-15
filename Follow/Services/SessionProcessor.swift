import Foundation

/// The pipeline for one recording, in two steps (D36): `transcribe` runs on its own after recording stops;
/// `summarize` only when the teacher asks for it, since the transcript is often enough.
/// Both write status/results to the database as they go, so sessions process in the background
/// while the teacher records the next student.
enum SessionProcessor {
    static func transcribe(
        sessionId: Int64,
        db: AppDatabase,
        engine: any TranscriptionEngine = EngineRegistry.transcription(id: AppSettings.transcriptionEngineID)
    ) async {
        do {
            guard let session = try db.session(id: sessionId), let audioPath = session.audioPath else { return }
            try db.updateSession(id: sessionId) { $0.status = .transcribing; $0.errorMessage = nil }
            let utterances = try await engine.transcribe(audioURL: AppPaths.absolute(audioPath), language: "vi")
            let engineID = engine.id
            try db.updateSession(id: sessionId) {
                $0.utterances = utterances
                $0.transcriptEngine = engineID
                // Keep the teacher only if that label still exists; an existing summary is kept as is.
                if let teacher = $0.teacherSpeaker, !$0.speakers.contains(teacher) { $0.teacherSpeaker = nil }
                $0.status = .done
            }
        } catch {
            fail(sessionId, error, db: db)
        }
    }

    static func summarize(
        sessionId: Int64,
        db: AppDatabase,
        summarizer: any SummarizationEngine = EngineRegistry.summarizer()
    ) async {
        do {
            guard let session = try db.session(id: sessionId), !session.utterances.isEmpty,
                  let student = try db.student(id: session.studentId) else { return }
            let info = StudentInfo(fullName: student.fullName, projectTitle: student.projectTitle)
            try db.updateSession(id: sessionId) { $0.status = .summarizing; $0.errorMessage = nil }
            let summary = try await summarizer.summarize(utterances: session.utterances, student: info)
            try db.updateSession(id: sessionId) {
                $0.teacherSpeaker = summary.teacherSpeaker ?? $0.teacherSpeaker
                $0.summaryMarkdown = summary.summaryMarkdown
                $0.status = .done
            }
        } catch {
            fail(sessionId, error, db: db)
        }
    }

    private static func fail(_ sessionId: Int64, _ error: any Error, db: AppDatabase) {
        let message = error.localizedDescription
        try? db.updateSession(id: sessionId) { $0.status = .failed; $0.errorMessage = message }
    }
}
