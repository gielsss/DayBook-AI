import SwiftUI
import AppKit

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
                    .disabled(appState.isTestingOllama || appState.isDownloadingOllamaModel)

                    Spacer()
                }

                downloadSection

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

    /// Get Ollama → Download Model → progress → ready. No Terminal needed.
    @ViewBuilder
    private var downloadSection: some View {
        if let progress = appState.ollamaDownloadProgress {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Downloading \(appState.ollamaModel)…")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Cancel") { appState.cancelOllamaDownload() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                Text("\(progress.description). You can keep using DayBook AI while this runs; if it stops, press Download Model again to continue.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if appState.isOllamaReachable == false {
            VStack(alignment: .leading, spacing: 6) {
                Label("Ollama isn't running or isn't installed yet. Install the free Ollama app, open it (a llama appears near the clock), then press Check Again.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Get Ollama…") {
                        if let url = URL(string: "https://ollama.com/download") { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.bordered)
                    Button("Check Again") { Task { await appState.refreshOllamaModels() } }
                        .buttonStyle(.bordered)
                }
            }
        } else if appState.isOllamaReachable == true && !appState.isOllamaModelDownloaded {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(appState.ollamaModel) isn't on this Mac yet. Download it once to turn on the AI features\(appState.ollamaModel == OllamaDefaults.model ? " (about 6 GB)" : "").")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if modelInput != appState.ollamaModel { appState.setOllamaModel(modelInput) }
                    appState.downloadOllamaModel()
                } label: {
                    Label("Download Model", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
            }
        } else if appState.isOllamaReachable == true {
            Label("\(appState.ollamaModel) is downloaded.", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if let message = appState.ollamaDownloadMessage {
            Label(message, systemImage: "arrow.down.circle")
                .font(.caption)
                .foregroundColor(appState.isOllamaModelDownloaded ? .green : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let message = appState.ollamaDownloadError {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
