import SwiftUI

public struct PasteCredentialsSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var jsonText: String = ""
    @State private var errorMessage: String? = nil
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paste Google OAuth Credentials JSON")
                        .font(.headline)
                    Text("Paste the contents of your downloaded client secret JSON file")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            .background(Color.dbBackground)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("JSON Content:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $jsonText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Text("Security Note: Credentials are saved directly to macOS Keychain and never stored in git or app logs.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Import to Keychain") {
                    guard let data = jsonText.data(using: .utf8) else {
                        errorMessage = "Invalid text encoding."
                        return
                    }
                    if appState.importGoogleCredentials(data: data) {
                        dismiss()
                    } else {
                        errorMessage = appState.gmailErrorMessage ?? "Failed to parse JSON credentials."
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 360)
    }
}
