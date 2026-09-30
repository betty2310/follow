import Foundation

/// Runs the pipeline for one session: transcribe → summarize. Writes status/results to the database as it goes.
/// Sessions process concurrently in the background while the teacher records the next student.
enum SessionProcessor {
    static func process(
        sessionId: Int64,
        db: AppDatabase,
        engine: any TranscriptionEngine = EngineRegistry.transcription(id: AppSettings.transcriptionEngineID)
    ) async {
        do {
            guard let session = try db.session(id: sessionId),
                  let student = try db.student(id: session.studentId) else { return }
            let info = StudentInfo(fullName: student.fullName, projectTitle: student.projectTitle)

            try db.updateSession(id: sessionId) { $0.status = .transcribing; $0.errorMessage = nil }
            let utterances = try await engine.transcribe(audioURL: AppPaths.absolute(session.audioPath), language: "vi")
            let engineID = engine.id
            try db.updateSession(id: sessionId) {
                $0.utterances = utterances
                $0.transcriptEngine = engineID
                $0.status = .summarizing
            }

            let summary = try await EngineRegistry.summarizer().summarize(utterances: utterances, student: info)
            try db.updateSession(id: sessionId) {
                $0.teacherSpeaker = summary.teacherSpeaker
                $0.summaryMarkdown = summary.summaryMarkdown
                $0.status = .done
            }
        } catch {
            let message = error.localizedDescription
            try? db.updateSession(id: sessionId) { $0.status = .failed; $0.errorMessage = message }
        }
    }
}
