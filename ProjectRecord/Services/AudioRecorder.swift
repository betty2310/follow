import AVFoundation
import Observation

/// Records the Mac microphone to AAC .m4a (mono, 16 kHz is enough for speech and keeps uploads small).
@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private var recorder: AVAudioRecorder?

    func start(to url: URL) throws {
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
        isRecording = true
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        isRecording = false
    }

    var currentTime: TimeInterval { recorder?.currentTime ?? 0 }
}
