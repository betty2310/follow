import Foundation

/// Storage root: ~/Documents/ProjectRecord (visible, easy to back up). See docs/DECISIONS.md D14.
enum AppPaths {
    static var root: URL {
        let url = URL.documentsDirectory.appending(path: "ProjectRecord", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var store: URL { root.appending(path: "ProjectRecord.store") }

    /// Relative path for a new recording: audio/<term>/<MSSV>/<yyyy-MM-dd_HHmm>.m4a
    static func newAudioRelativePath(term: String, mssv: String, date: Date = .now) -> String {
        let stamp = date.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)_\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)",
                                             timeZone: .current, calendar: .current))
        return "audio/\(sanitize(term))/\(sanitize(mssv))/\(stamp).m4a"
    }

    static func absolute(_ relativePath: String) -> URL {
        root.appending(path: relativePath)
    }

    private static func sanitize(_ s: String) -> String {
        s.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
    }
}

enum AppSettings {
    static var claudeCLIPath: String {
        UserDefaults.standard.string(forKey: "claudeCLIPath")
            ?? URL.homeDirectory.appending(path: ".local/bin/claude").path
    }
    static var claudeModel: String {
        UserDefaults.standard.string(forKey: "claudeModel") ?? "sonnet"
    }
    static var transcriptionEngineID: String {
        UserDefaults.standard.string(forKey: "transcriptionEngineID") ?? "soniox"
    }
}
