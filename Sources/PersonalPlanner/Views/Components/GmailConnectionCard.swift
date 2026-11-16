import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct GmailConnectionCard: View {
    @ObservedObject var appState: AppState
    @State private var showPasteSheet: Bool = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private func selectJSONFile() {
        let panel = NSOpenPanel()
        panel.title = "Select Google OAuth Credentials JSON"
        panel.prompt = "Import Credentials"
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                _ = appState.importGoogleCredentials(data: data)
            } catch {
                appState.gmailErrorMessage = "Could not read file: \(error.localizedDescription)"
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    public var body: some View {
        GroupBox(label: Label("Gmail API Connection (Desktop OAuth 2.0)", systemImage: "envelope.badge").font(.headline)) {
            VStack(alignment: .leading, spacing: 14) {
                // Status Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google Account Integration")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Private, single-user desktop integration. Requests strictly 'gmail.readonly' permission.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if appState.isGmailAuthenticated {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Connected")
                        }
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(6)
                    } else if appState.hasGmailClientConfig {
                        HStack(spacing: 4) {
                            Image(systemName: "key.fill")
                            Text("Credentials Ready")
                        }
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.dbNavy.opacity(0.15))
                        .foregroundColor(.dbNavy)
                        .cornerRadius(6)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text("Setup Needed")
                        }
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(6)
                    }
                }
                
                Divider()
                
                // Status / Error Messages
                if let error = appState.gmailErrorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connection Notice")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(6)
                }
                
                if let status = appState.gmailStatusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.dbNavy)
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(6)
                    .background(Color.dbNavy.opacity(0.06))
                    .cornerRadius(6)
                }
                
                // SECTION 1: Credentials configuration
                if !appState.hasGmailClientConfig {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Step 1: Import Google OAuth Client Credentials")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Select your downloaded Google Desktop OAuth client JSON file. Tokens and secrets are stored in macOS Keychain.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 10) {
                            Button(action: selectJSONFile) {
                                Label("Select Credentials JSON File...", systemImage: "doc.badge.plus")
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button(action: { showPasteSheet = true }) {
                                Label("Paste JSON...", systemImage: "clipboard")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(10)
                    .background(Color.dbSurface)
                    .cornerRadius(8)
                } else if !appState.isGmailAuthenticated {
                    // SECTION 2: Credentials ready, ready to sign in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Step 2: Sign In with Google")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Clicking the button will open your default browser to authorize read-only access. A local loopback listener will receive the authorization code.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                Task {
                                    await appState.connectGmail()
                                }
                            }) {
                                if appState.isAuthenticatingGmail {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Waiting for Browser Authorization...")
                                    }
                                } else {
                                    Label("Sign in with Google (Browser)", systemImage: "person.crop.circle.badge.checkmark")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.isAuthenticatingGmail)
                            
                            Button(action: selectJSONFile) {
                                Text("Change Credentials JSON")
                            }
                            .buttonStyle(.bordered)
                            .disabled(appState.isAuthenticatingGmail)
                        }
                    }
                    .padding(10)
                    .background(Color.dbSurface)
                    .cornerRadius(8)
                } else {
                    // SECTION 3: Connected & Showing 5 Recent Emails
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Live Connection Confirmed: 5 Recent Emails")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                Text("Showing recent email subjects fetched directly from your inbox via Gmail API.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                Task {
                                    await appState.fetchRecentGmailEmails()
                                }
                            }) {
                                if appState.isFetchingRecentEmails {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(appState.isFetchingRecentEmails)
                            
                            Button(action: {
                                appState.disconnectGmail()
                            }) {
                                Label("Disconnect", systemImage: "xmark.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        
                        if appState.recentGmailEmails.isEmpty {
                            if appState.isFetchingRecentEmails {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Fetching messages from your inbox...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                            } else {
                                Text("No messages returned or inbox empty. Click 'Refresh' to query your messages.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(8)
                            }
                        } else {
                            VStack(spacing: 8) {
                                ForEach(Array(appState.recentGmailEmails.enumerated()), id: \.element.id) { index, email in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(index + 1)")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.secondary)
                                            .frame(width: 16)
                                            .padding(.top, 2)
                                        
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(email.subject)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            
                                            HStack(spacing: 6) {
                                                Text(email.sender)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                                Spacer()
                                                Text(formatDate(email.date))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            if !email.snippet.isEmpty {
                                                Text(email.snippet)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary.opacity(0.8))
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background(Color(NSColor.textBackgroundColor).opacity(0.4))
                                    .cornerRadius(6)
                                }
                            }
                        }
                        
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("Tokens protected in macOS Keychain. Email content stays on this Mac.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    .padding(10)
                    .background(Color.dbSurface)
                    .cornerRadius(8)
                }
            }
            .padding(10)
        }
        .sheet(isPresented: $showPasteSheet) {
            PasteCredentialsSheet(appState: appState)
        }
    }
}
