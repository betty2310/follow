import SwiftUI

@main
struct ProjectRecordApp: App {
    let database: AppDatabase = {
        do {
            return try AppDatabase.onDisk(at: AppPaths.database)
        } catch {
            fatalError("Failed to open database at \(AppPaths.database.path): \(error)")
        }
    }()
    @State private var updater = AppUpdater()

    init() {
        APIKeys.migrateFromKeychain()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .environment(\.appDatabase, database)
        .environment(updater)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
            }
        }

        Settings {
            SettingsView()
                .environment(updater)
        }
    }
}
