import SwiftUI

/// Settings for reading Gradescope assignments through a signed-in browser tab.
public struct GradescopeSettingsCard: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        GroupBox(label: Label("Gradescope", systemImage: "checkmark.rectangle.stack").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reads assignments and due dates from your current Gradescope courses through a Gradescope tab you have open and signed in to. Read-only. Assignments also posted on Canvas are not added twice.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if let browser = appState.preferences.gradescopeBrowser {
                        Button(action: { Task { await appState.syncGradescope() } }) {
                            HStack(spacing: 4) {
                                if appState.isSyncingGradescope { ProgressView().controlSize(.small) }
                                Text(appState.isSyncingGradescope ? "Syncing..." : "Sync Gradescope")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.isSyncingGradescope)
                        Button("Disconnect") { appState.disconnectGradescope() }
                            .buttonStyle(.bordered)
                            .disabled(appState.isSyncingGradescope)
                        Spacer()
                        Label("Using \(browser.displayName)", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Menu("Use my browser") {
                            Button("Find my Gradescope tab") { Task { await appState.connectGradescope(nil) } }
                            Divider()
                            ForEach(CanvasBrowser.allCases) { browser in
                                Button(browser.displayName) { Task { await appState.connectGradescope(browser) } }
                            }
                        }
                        .fixedSize()
                        .disabled(appState.isSyncingGradescope)
                        Spacer()
                    }
                }

                if let last = appState.preferences.lastGradescopeSyncDate, appState.isGradescopeConnected, !appState.isSyncingGradescope {
                    Text("Last synced \(appState.relativeTimeString(from: last)). Also syncs when you press Scan Emails.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let status = appState.gradescopeStatusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = appState.gradescopeErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
        }
    }
}
