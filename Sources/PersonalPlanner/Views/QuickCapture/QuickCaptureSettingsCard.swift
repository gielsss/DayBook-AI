import SwiftUI

public struct QuickCaptureSettingsCard: View {
    @ObservedObject var appState: AppState
    @State private var retainedCount: Int = 0
    @State private var showDeleteConfirmation: Bool = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "bolt.badge.automatic.fill")
                    .foregroundColor(.dbAccent)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Capture Settings")
                        .font(.headline)
                    Text("Capture copied text or screenshots from other applications and create tasks or calendar events.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    appState.openQuickCapture()
                }) {
                    Label("Open Quick Capture", systemImage: "bolt.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Divider()
            
            // Shortcut Setting
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keyboard Shortcut")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Invoke Quick Capture anywhere within the app or system.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Picker("", selection: $appState.preferences.quickCaptureShortcut) {
                    Text("⌘⇧C (Command + Shift + C)").tag("Command+Shift+C")
                    Text("⌥Space (Option + Space)").tag("Option+Space")
                    Text("⌃⌥C (Control + Option + C)").tag("Control+Option+C")
                }
                .frame(width: 230)
                .onChange(of: appState.preferences.quickCaptureShortcut) { _ in
                    appState.saveDatabase()
                }
            }
            
            Divider()
            
            // Source Retention Setting
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $appState.preferences.quickCaptureRetainSource) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Retain Captured Source Content Locally")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("When disabled, raw captured text and temporary screenshots are deleted immediately after review. When enabled, original captures are saved locally in Application Support.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: appState.preferences.quickCaptureRetainSource) { _ in
                    appState.saveDatabase()
                }
                
                HStack {
                    Text("Local storage: \(retainedCount) retained \(retainedCount == 1 ? "capture" : "captures")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if retainedCount > 0 {
                        Button("Delete All Retained Captures", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color.dbSurface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .confirmationDialog(
            "Delete All Retained Captures?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                appState.quickCaptureStorageService.deleteAllRetainedCaptures()
                updateRetainedCount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all retained capture text files and screenshots from your local disk.")
        }
        .onAppear {
            updateRetainedCount()
        }
    }
    
    private func updateRetainedCount() {
        retainedCount = appState.quickCaptureStorageService.listRetainedCaptures().count
    }
}
