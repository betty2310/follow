import Foundation

/// One-time move of what the app left under its old name, ProjectRecord (docs/DECISIONS.md D32):
/// the data folder `~/Documents/ProjectRecord` (database renamed to `Follow.sqlite`) and the
/// settings and API keys saved under the old bundle id. Runs at launch, before the database opens.
enum RenameMigration {
    static let legacyName = "ProjectRecord"
    static let legacyBundleID = "dev.betty.ProjectRecord"

    static func run() throws {
        try moveDataFolder(documents: .documentsDirectory)
        copySettings(from: UserDefaults.standard.persistentDomain(forName: legacyBundleID), to: .standard)
    }

    /// Moves the old folder only while the new one doesn't exist, and renames the database only while
    /// `Follow.sqlite` doesn't exist, so it never overwrites data and finishes on the next launch if interrupted.
    static func moveDataFolder(documents: URL, fileManager: FileManager = .default) throws {
        let old = documents.appending(path: legacyName, directoryHint: .isDirectory)
        let new = documents.appending(path: "Follow", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: old.path), !fileManager.fileExists(atPath: new.path) {
            try fileManager.moveItem(at: old, to: new)
        }
        guard fileManager.fileExists(atPath: new.appending(path: "\(legacyName).sqlite").path),
              !fileManager.fileExists(atPath: new.appending(path: "Follow.sqlite").path) else { return }
        for suffix in ["-wal", "-shm", ""] {  // the main file last: its presence is what marks the job unfinished
            let file = new.appending(path: "\(legacyName).sqlite\(suffix)")
            guard fileManager.fileExists(atPath: file.path) else { continue }
            try fileManager.moveItem(at: file, to: new.appending(path: "Follow.sqlite\(suffix)"))
        }
    }

    /// Copies the old settings once, keeping any value already set under the new bundle id.
    static func copySettings(from legacy: [String: Any]?, to defaults: UserDefaults) {
        let doneKey = "settingsCopiedFromProjectRecord"
        guard let legacy, !defaults.bool(forKey: doneKey) else { return }
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: doneKey)
    }
}
