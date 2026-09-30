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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .environment(\.appDatabase, database)

        Settings {
            SettingsView()
        }
    }
}
