import SwiftUI

struct SettingsView: View {
    @AppStorage("claudeCLIPath") private var claudeCLIPath = AppSettings.claudeCLIPath
    @AppStorage("claudeModel") private var claudeModel = "sonnet"
    @AppStorage("transcriptionEngineID") private var engineID = "soniox"
    @State private var keys: [KeychainKey: String] = [:]

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Default engine", selection: $engineID) {
                    ForEach(EngineRegistry.transcriptionEngines, id: \.id) { Text($0.displayName).tag($0.id) }
                }
                ForEach(KeychainKey.allCases, id: \.self) { key in
                    SecureField(key.rawValue, text: Binding(
                        get: { keys[key] ?? "" },
                        set: { keys[key] = $0; Keychain.set($0, for: key) }
                    ))
                }
            }
            Section("Summarization (claude -p)") {
                TextField("Claude CLI path", text: $claudeCLIPath)
                TextField("Model", text: $claudeModel)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, maxWidth: 640)
        .frame(maxWidth: .infinity)
        .navigationTitle("Settings")
        .onAppear {
            for key in KeychainKey.allCases { keys[key] = Keychain.get(key) }
        }
    }
}
