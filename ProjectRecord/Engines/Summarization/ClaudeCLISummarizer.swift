import Foundation

/// Summarizes by shelling out to the Claude Code CLI: `claude -p --model <model> --output-format json`.
/// The prompt is written to stdin. The CLI's JSON envelope carries the model text in `result`.
struct ClaudeCLISummarizer: SummarizationEngine {
    var cliPath: String
    var model: String

    enum Failure: LocalizedError {
        case cliNotFound(String)
        case exited(Int32, String)
        case unparsable(String)

        var errorDescription: String? {
            switch self {
            case .cliNotFound(let path): "Claude CLI not found at \(path). Set the path in Settings."
            case .exited(let code, let err): "claude exited with code \(code): \(err)"
            case .unparsable(let text): "Could not parse summary JSON: \(text.prefix(300))"
            }
        }
    }

    func summarize(utterances: [Utterance], student: StudentInfo) async throws -> SummaryResult {
        guard FileManager.default.isExecutableFile(atPath: cliPath) else { throw Failure.cliNotFound(cliPath) }
        let prompt = SummaryPrompt.build(utterances: utterances, student: student)
        let output = try await run(arguments: ["-p", "--model", model, "--output-format", "json"], stdin: prompt)
        return try Self.parse(cliOutput: output)
    }

    /// Parses the CLI envelope `{"result": "<model text>", ...}`, then the JSON object inside the model text.
    static func parse(cliOutput: Data) throws -> SummaryResult {
        struct Envelope: Decodable { let result: String }
        let text = (try? JSONDecoder().decode(Envelope.self, from: cliOutput).result)
            ?? String(decoding: cliOutput, as: UTF8.self)
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"),
              let result = try? JSONDecoder().decode(SummaryResult.self, from: Data(text[open...close].utf8))
        else { throw Failure.unparsable(text) }
        return result
    }

    private func run(arguments: [String], stdin: String) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { p in
                let out = outPipe.fileHandleForReading.readDataToEndOfFile()
                let err = errPipe.fileHandleForReading.readDataToEndOfFile()
                if p.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else {
                    continuation.resume(throwing: Failure.exited(p.terminationStatus, String(decoding: err, as: UTF8.self)))
                }
            }
            do {
                try process.run()
                inPipe.fileHandleForWriting.write(Data(stdin.utf8))
                try? inPipe.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
