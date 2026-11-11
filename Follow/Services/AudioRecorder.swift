import AVFoundation
import Observation

/// Records the Mac microphone to AAC .m4a (mono, 16 kHz is enough for speech and keeps uploads small).
/// One per app, not per student page: the page is rebuilt when the teacher switches students, and a
/// recorder owned by it was lost mid-recording, leaving its session stuck at `.recording`.
@MainActor
@Observable
final class AudioRecorder {
    /// The session being recorded and its student, so each page knows whether the recording is its own.
    private(set) var session: (id: Int64, studentId: Int64)?
    private var recorder: AVAudioRecorder?

    var isRecording: Bool { session != nil }

    func start(to url: URL, session id: Int64, studentId: Int64) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
        self.recorder = recorder
        session = (id, studentId)
    }

    /// Stops recording; returns the ID of the session it was recording, if any.
    @discardableResult
    func stop() -> Int64? {
        recorder?.stop()
        recorder = nil
        defer { session = nil }
        return session?.id
    }

    var currentTime: TimeInterval { recorder?.currentTime ?? 0 }
}
