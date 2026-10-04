import SwiftUI

struct SettingsView: View {
    @AppStorage("claudeCLIPath") private var claudeCLIPath = AppSettings.claudeCLIPath
    @AppStorage("claudeModel") private var claudeModel = "sonnet"
    @AppStorage("transcriptionEngineID") private var engineID = "soniox"
    @State private var keys: [APIKey: String] = [:]
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Default engine", selection: $engineID) {
                    ForEach(EngineRegistry.transcriptionEngines, id: \.id) { Text($0.displayName).tag($0.id) }
                }
                ForEach(APIKey.allCases, id: \.self) { key in
                    SecureField(key.rawValue, text: Binding(
                        get: { keys[key] ?? "" },
                        set: { keys[key] = $0; APIKeys.set($0, for: key) }
                    ))
                }
            }
            Section("Summarization (claude -p)") {
                TextField("Claude CLI path", text: $claudeCLIPath)
                TextField("Model", text: $claudeModel)
            }
            Section("Updates") {
                @Bindable var updater = updater
                Toggle("Check for updates every day", isOn: $updater.automaticallyChecks)
                LabeledContent("Version", value: UpdateStatus.currentVersion())
                Button("Check for Updates…") { updater.checkForUpdates() }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, maxWidth: 640)
        .frame(maxWidth: .infinity)
        .navigationTitle("Settings")
        .onAppear {
            for key in APIKey.allCases { keys[key] = APIKeys.get(key) }
        }
    }
}
