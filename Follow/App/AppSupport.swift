import Foundation

/// Storage root: ~/Documents/Follow (visible, easy to back up). See docs/DECISIONS.md D14.
enum AppPaths {
    static var root: URL {
        let url = URL.documentsDirectory.appending(path: "Follow", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var database: URL { root.appending(path: "Follow.sqlite") }

    /// Relative path for a new recording: audio/<group>/<MSSV>/<yyyy-MM-dd_HHmm>.m4a
    static func newAudioRelativePath(group: String, mssv: String, date: Date = .now) -> String {
        let stamp = date.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)_\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)",
                                             timeZone: .current, calendar: .current))
        return "audio/\(sanitize(group))/\(sanitize(mssv))/\(stamp).m4a"
    }

    static func absolute(_ relativePath: String) -> URL {
        root.appending(path: relativePath)
    }

    /// Moves recordings to the Trash (recoverable) after their sessions were deleted. Missing files are skipped.
    static func trashAudio(_ relativePaths: [String]) {
        for path in relativePaths {
            try? FileManager.default.trashItem(at: absolute(path), resultingItemURL: nil)
        }
    }

    private static func sanitize(_ s: String) -> String {
        s.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
    }
}

enum AppSettings {
    static var transcriptionEngineID: String { string("transcriptionEngineID") ?? "soniox" }
    static var summarizationEngineID: String { string("summarizationEngineID") ?? "anthropic" }
    static var anthropicModel: String { string("anthropicModel") ?? AnthropicSummarizer.defaultModel }
    static var openAIBaseURL: String { string("openAIBaseURL") ?? OpenAICompatibleSummarizer.defaultBaseURL }
    static var openAIModel: String { string("openAIModel") ?? OpenAICompatibleSummarizer.defaultModel }

    /// A cleared text field in Settings falls back to the default.
    private static func string(_ key: String) -> String? {
        guard let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespaces),
              !value.isEmpty else { return nil }
        return value
    }
}
