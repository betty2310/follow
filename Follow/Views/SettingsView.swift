import SwiftUI

struct SettingsView: View {
    @AppStorage("transcriptionEngineID") private var engineID = "soniox"
    @AppStorage("summarizationEngineID") private var summarizerID = "anthropic"
    @AppStorage("anthropicModel") private var anthropicModel = AnthropicSummarizer.defaultModel
    @AppStorage("openAIBaseURL") private var openAIBaseURL = OpenAICompatibleSummarizer.defaultBaseURL
    @AppStorage("openAIModel") private var openAIModel = OpenAICompatibleSummarizer.defaultModel
    @AppStorage("cat.visible") private var showsCat = true
    @AppStorage("cat.size") private var catSize = CatSprite.defaultSize
    @State private var keys: [APIKey: String] = [:]
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Default engine", selection: $engineID) {
                    ForEach(EngineRegistry.transcriptionEngines, id: \.id) { Text($0.displayName).tag($0.id) }
                }
                ForEach(APIKey.transcription, id: \.self) { key in
                    SecureField(key.rawValue, text: binding(for: key))
                }
            }
            Section("Summarization") {
                Picker("Provider", selection: $summarizerID) {
                    ForEach(EngineRegistry.summarizationEngines, id: \.id) { Text($0.displayName).tag($0.id) }
                }
                if summarizerID == "openai" {
                    TextField("Base URL", text: $openAIBaseURL, prompt: Text(OpenAICompatibleSummarizer.defaultBaseURL))
                    TextField("Model", text: $openAIModel, prompt: Text(OpenAICompatibleSummarizer.defaultModel))
                    SecureField("API key", text: binding(for: .openAI), prompt: Text("Optional for local servers"))
                } else {
                    TextField("Model", text: $anthropicModel, prompt: Text(AnthropicSummarizer.defaultModel))
                    SecureField("API key", text: binding(for: .anthropic))
                }
            }
            Section("Fun") {
                Toggle("Show Cat", isOn: $showsCat)
                Slider(value: $catSize, in: CatSprite.sizes, step: 1) {
                    Text("Cat size")
                } minimumValueLabel: {
                    Image(systemName: "cat").imageScale(.small)
                } maximumValueLabel: {
                    Image(systemName: "cat").imageScale(.large)
                }
                CatPreview(pixel: catSize)
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

    private func binding(for key: APIKey) -> Binding<String> {
        Binding(get: { keys[key] ?? "" }, set: { keys[key] = $0; APIKeys.set($0, for: key) })
    }
}
