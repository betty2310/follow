import Foundation

/// Default engine. Soniox async REST API (docs: https://soniox.com/docs/stt/async/async-transcription, checked 2026-09-30):
/// upload file → create transcription (diarization on, language hint) → poll → fetch tokens → delete file + transcription.
struct SonioxEngine: TranscriptionEngine {
    let id = "soniox"
    let displayName = "Soniox"
    var model = "stt-async-v5"
    var pollInterval: Duration = .seconds(2)
    var timeout: Duration = .seconds(15 * 60)

    private static let baseURL = URL(string: "https://api.soniox.com/v1")!

    func transcribe(audioURL: URL, language: String) async throws -> [Utterance] {
        guard let apiKey = Keychain.get(.soniox), !apiKey.isEmpty else { throw TranscriptionError.missingAPIKey(displayName) }
        let api = API(key: apiKey)

        let fileID = try await api.upload(audioURL)
        var transcriptionID: String?
        defer {
            // Best-effort cleanup: Soniox keeps uploads/transcripts until deleted and storage is limited.
            let tid = transcriptionID
            Task.detached {
                if let tid { await api.delete("transcriptions/\(tid)") }
                await api.delete("files/\(fileID)")
            }
        }

        let created: Transcription = try await api.json("POST", "transcriptions", body: [
            "model": model,
            "file_id": fileID,
            "language_hints": [language],
            "enable_speaker_diarization": true,
        ])
        transcriptionID = created.id

        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            let job: Transcription = try await api.json("GET", "transcriptions/\(created.id)")
            switch job.status {
            case "completed":
                let transcript: Transcript = try await api.json("GET", "transcriptions/\(created.id)/transcript")
                let utterances = Self.utterances(from: transcript.tokens)
                guard !utterances.isEmpty else { throw TranscriptionError.emptyTranscript(displayName) }
                return utterances
            case "error":
                throw TranscriptionError.providerFailed(displayName, job.errorMessage ?? job.errorType ?? "unknown error")
            default:
                guard clock.now < deadline else { throw TranscriptionError.providerFailed(displayName, "timed out waiting for transcription") }
                try await Task.sleep(for: pollInterval)
            }
        }
    }

    /// Groups consecutive tokens by speaker into utterances. Soniox speaker ids ("1", "2", …) are relabelled
    /// "A", "B", … in order of first appearance. Tokens are sub-word pieces carrying their own leading spaces.
    static func utterances(from tokens: [Token]) -> [Utterance] {
        var labels: [String: String] = [:]
        func label(for speaker: String?) -> String {
            let key = speaker ?? "?"
            if let existing = labels[key] { return existing }
            let scalar = UnicodeScalar(UInt8(65 + labels.count % 26))
            let new = String(Character(scalar))
            labels[key] = new
            return new
        }

        var result: [Utterance] = []
        for token in tokens where !token.text.isEmpty {
            let speaker = label(for: token.speaker)
            let start = Double(token.startMs ?? 0) / 1000
            let end = Double(token.endMs ?? token.startMs ?? 0) / 1000
            if var last = result.last, last.speaker == speaker {
                last.text += token.text
                last.end = max(last.end, end)
                result[result.count - 1] = last
            } else {
                result.append(Utterance(speaker: speaker, text: token.text, start: start, end: end))
            }
        }
        return result.compactMap { u in
            let text = u.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : Utterance(speaker: u.speaker, text: text, start: u.start, end: u.end)
        }
    }

    // MARK: - Wire types

    struct Token: Decodable, Sendable {
        var text: String
        var startMs: Int?
        var endMs: Int?
        var speaker: String?

        enum CodingKeys: String, CodingKey {
            case text, speaker
            case startMs = "start_ms"
            case endMs = "end_ms"
        }

        init(text: String, startMs: Int?, endMs: Int?, speaker: String?) {
            self.text = text
            self.startMs = startMs
            self.endMs = endMs
            self.speaker = speaker
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            text = try c.decode(String.self, forKey: .text)
            startMs = try c.decodeIfPresent(Double.self, forKey: .startMs).map { Int($0) }
            endMs = try c.decodeIfPresent(Double.self, forKey: .endMs).map { Int($0) }
            // Documented as a string ("1"), but accept a number too.
            if let s = try? c.decodeIfPresent(String.self, forKey: .speaker) {
                speaker = s
            } else if let n = try? c.decodeIfPresent(Int.self, forKey: .speaker) {
                speaker = String(n)
            } else {
                speaker = nil
            }
        }
    }

    struct Transcript: Decodable, Sendable {
        var tokens: [Token]
    }

    struct Transcription: Decodable, Sendable {
        var id: String
        var status: String
        var errorType: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case id, status
            case errorType = "error_type"
            case errorMessage = "error_message"
        }
    }

    private struct UploadedFile: Decodable { var id: String }

    // MARK: - HTTP

    private struct API: Sendable {
        let key: String

        func request(_ method: String, _ path: String) -> URLRequest {
            var req = URLRequest(url: SonioxEngine.baseURL.appending(path: path))
            req.httpMethod = method
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            return req
        }

        func json<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> T {
            var req = request(method, path)
            if let body {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
            return try await send(req)
        }

        func upload(_ fileURL: URL) async throws -> String {
            let boundary = "Boundary-\(UUID().uuidString)"
            var req = request("POST", "files")
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".utf8))
            body.append(Data("Content-Type: audio/mp4\r\n\r\n".utf8))
            body.append(try Data(contentsOf: fileURL))
            body.append(Data("\r\n--\(boundary)--\r\n".utf8))
            req.httpBody = body
            let file: UploadedFile = try await send(req)
            return file.id
        }

        func delete(_ path: String) async {
            _ = try? await URLSession.shared.data(for: request("DELETE", path))
        }

        private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                throw TranscriptionError.http(code, String(decoding: data.prefix(500), as: UTF8.self))
            }
            return try JSONDecoder().decode(T.self, from: data)
        }
    }
}
