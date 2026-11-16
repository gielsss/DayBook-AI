import SwiftUI

/// Settings for the local AI model (Ollama) used for email scanning, Quick Capture and receipts.
public struct AISettingsCard: View {
    @ObservedObject var appState: AppState
    @State private var modelInput: String = ""

    public init(appState: AppState) {
        self.appState = appState
        _modelInput = State(initialValue: appState.ollamaModel)
    }

    static let intro = "Email scanning and Quick Capture run on a model on this Mac through Ollama. Nothing is sent online and there is no cost. Text-only models still handle screenshots: their text is read on this Mac first. A vision model can also look at the images themselves."

    public var body: some View {
        GroupBox(label: Label("Local AI (Ollama)", systemImage: "cpu").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(Self.intro)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("Model:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    TextField(OllamaDefaults.model, text: $modelInput, onCommit: {
                        appState.setOllamaModel(modelInput)
                    })
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: 200)
                    if !appState.ollamaInstalledModels.isEmpty {
                        Menu("Downloaded") {
                            ForEach(appState.ollamaInstalledModels, id: \.self) { name in
                                Button(name) {
                                    modelInput = name
                                    appState.setOllamaModel(name)
                                }
                            }
                        }
                        .frame(width: 120)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button(action: {
                        if modelInput != appState.ollamaModel {
                            appState.setOllamaModel(modelInput)
                        }
                        Task { await appState.testOllamaConnection() }
                    }) {
                        HStack(spacing: 4) {
                            if appState.isTestingOllama {
                                ProgressView().controlSize(.small)
                                Text("Testing (can take a minute)...")
                            } else {
                                Text("Test Connection")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.isTestingOllama)

                    Spacer()

                    Text("Download: ollama pull \(OllamaDefaults.model)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                if let message = appState.ollamaTestSuccessMessage {
                    Label(message, systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundColor(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let message = appState.ollamaTestErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
        }
        .task { await appState.refreshOllamaModels() }
    }
}
