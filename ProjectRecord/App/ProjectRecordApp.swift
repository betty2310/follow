import SwiftData
import SwiftUI

@main
struct ProjectRecordApp: App {
    let container: ModelContainer = {
        let config = ModelConfiguration(url: AppPaths.store)
        do {
            return try ModelContainer(for: Term.self, Student.self, Session.self, configurations: config)
        } catch {
            fatalError("Failed to open store at \(AppPaths.store.path): \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)

        Settings {
            SettingsView()
        }
    }
}
