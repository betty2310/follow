import SwiftUI

@main
struct FollowApp: App {
    let database: AppDatabase
    @State private var updater = AppUpdater()

    init() {
        // Unit tests run inside the app (TEST_HOST): keep them away from the real data folder,
        // or they would create an empty ~/Documents/Follow before the real app migrates the old one.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            database = try! AppDatabase.inMemory()
            return
        }
        do {
            try RenameMigration.run()
        } catch {
            fatalError("Failed to move ~/Documents/\(RenameMigration.legacyName) to ~/Documents/Follow: \(error)")
        }
        APIKeys.migrateFromKeychain()
        do {
            database = try AppDatabase.onDisk(at: AppPaths.database)
        } catch {
            fatalError("Failed to open database at \(AppPaths.database.path): \(error)")
        }
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
