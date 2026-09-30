import Foundation
import SwiftData

/// Runs the pipeline for one session: transcribe → summarize. Updates `Session.status` as it goes.
/// Sessions process concurrently in the background while the teacher records the next student.
@MainActor
enum SessionProcessor {
    static func process(_ session: Session, engine: any TranscriptionEngine = EngineRegistry.transcription(id: AppSettings.transcriptionEngineID)) async {
        let audioURL = AppPaths.absolute(session.audioFileName)
        let student = StudentInfo(fullName: session.student?.fullName ?? "", projectTitle: session.student?.projectTitle ?? "")
        session.errorMessage = nil
        do {
            session.status = .transcribing
            let utterances = try await engine.transcribe(audioURL: audioURL, language: "vi")
            session.utterances = utterances
            session.transcriptEngine = engine.id

            session.status = .summarizing
            let summary = try await EngineRegistry.summarizer().summarize(utterances: utterances, student: student)
            session.teacherSpeaker = summary.teacherSpeaker
            session.summaryMarkdown = summary.summaryMarkdown
            session.status = .done
        } catch {
            session.status = .failed
            session.errorMessage = error.localizedDescription
        }
    }
}
