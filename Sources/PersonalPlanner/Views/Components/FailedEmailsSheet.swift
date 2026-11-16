import SwiftUI
import AppKit

public struct FailedEmailsSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var retryingId: String? = nil
    @State private var emailConfirmingRetry: FailedEmailRecord? = nil
    @State private var showConfirmRetryAllOutsideWindow = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar
            
            Divider()
            
            // Content List
            if appState.failedEmailRecords.isEmpty {
                emptyView
            } else {
                failedListView
            }
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 460, idealHeight: 540)
        .background(Color.dbBackground)
        .confirmationDialog(
            "Retry Outside 72-Hour Window",
            isPresented: Binding(
                get: { emailConfirmingRetry != nil },
                set: { if !$0 { emailConfirmingRetry = nil } }
            ),
            titleVisibility: .visible,
            presenting: emailConfirmingRetry
        ) { item in
            Button("Explicitly Analyze Outside-Window Email") {
                let id = item.id
                retryingId = id
                emailConfirmingRetry = nil
                Task {
                    await appState.retryFailedEmail(id: id)
                    retryingId = nil
                }
            }
            Button("Dismiss Failure Record", role: .destructive) {
                appState.dismissFailedEmail(id: item.id)
                emailConfirmingRetry = nil
            }
            Button("Cancel", role: .cancel) {
                emailConfirmingRetry = nil
            }
        } message: { item in
            Text("This email was received on \(formatDate(item.receivedDate)), which is outside the rolling 3-day (72-hour) scan window. Would you like to explicitly analyze it now?")
        }
        .confirmationDialog(
            "Retry Failed Emails",
            isPresented: $showConfirmRetryAllOutsideWindow,
            titleVisibility: .visible
        ) {
            Button("Retry All (\(appState.failedEmailRecords.count) Emails, Including Outside Window)") {
                Task {
                    await appState.retryAllFailedEmails(includeOutsideWindow: true)
                }
            }
            Button("Retry Recent Only (Within 72h)") {
                Task {
                    await appState.retryAllFailedEmails(includeOutsideWindow: false)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let outsideCount = appState.failedEmailRecords.filter { $0.isOutsideScanWindow(hours: 72) }.count
            Text("\(outsideCount) failed email(s) were received more than 72 hours ago. Choose whether to include them in this retry.")
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Mailbox Processing Failures")
                    .font(.headline)
                Text("\(appState.failedEmailRecords.count) email(s) require attention or retry")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !appState.failedEmailRecords.isEmpty {
                Button(action: {
                    let outsideCount = appState.failedEmailRecords.filter { $0.isOutsideScanWindow(hours: 72) }.count
                    if outsideCount > 0 {
                        showConfirmRetryAllOutsideWindow = true
                    } else {
                        Task {
                            await appState.retryAllFailedEmails()
                        }
                    }
                }) {
                    if appState.isScanningEmails {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Retry All Failed", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(appState.isScanningEmails)
            }
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.dbSurface)
    }
    
    // MARK: - Empty View
    
    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)
            Text("No Processing Failures")
                .font(.headline)
            Text("All discovered emails in your 3-day (72h) inbox have been analyzed or cached successfully.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
    
    // MARK: - Failed Items List
    
    private var failedListView: some View {
        List {
            ForEach(appState.failedEmailRecords) { item in
                failedRow(item)
                    .padding(.vertical, 6)
            }
        }
        .listStyle(.inset)
    }
    
    private func failedRow(_ item: FailedEmailRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                stageBadge(item.failureStage)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.subject.isEmpty ? "(No Subject)" : item.subject)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 6) {
                        Text(item.sender)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatDate(item.receivedDate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if item.attemptCount > 1 {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("Attempts: \(item.attemptCount)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Row Action Buttons
                HStack(spacing: 8) {
                    if let url = URL(string: item.gmailWebLink) {
                        Link(destination: url) {
                            Label("Open in Gmail", systemImage: "arrow.up.right")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("View this email in Gmail web app")
                    }
                    
                    Button(action: {
                        if item.isOutsideScanWindow(hours: 72) {
                            emailConfirmingRetry = item
                        } else {
                            retryingId = item.id
                            Task {
                                await appState.retryFailedEmail(id: item.id)
                                retryingId = nil
                            }
                        }
                    }) {
                        if retryingId == item.id || appState.isScanningEmails {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.isScanningEmails)
                    
                    Button(role: .destructive, action: {
                        appState.dismissFailedEmail(id: item.id)
                    }) {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss failure record")
                }
            }
            
            // Plain-Language Failure Explanation
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.red)
                Text(item.failureReason)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .cornerRadius(6)
            
            // Outside 3-day (72h) scope explanation banner
            if item.isOutsideScanWindow(hours: 72) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("Received on \(formatDate(item.receivedDate)) (outside rolling 3-day / 72h scan window). Retrying will analyze it explicitly.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(10)
        .background(Color.dbSurface)
        .cornerRadius(8)
    }
    
    private func stageBadge(_ stage: EmailFailureStage) -> some View {
        HStack(spacing: 4) {
            Image(systemName: stage.iconName)
                .font(.system(size: 9))
            Text(stage.userFacingTitle)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(stageBadgeBackground(stage))
        .foregroundColor(stageBadgeForeground(stage))
        .cornerRadius(4)
    }
    
    private func stageBadgeBackground(_ stage: EmailFailureStage) -> Color {
        switch stage {
        case .retrieval: return Color.dbNavy.opacity(0.15)
        case .decoding: return Color.dbAccent.opacity(0.15)
        case .analysis: return Color.orange.opacity(0.15)
        case .validation: return Color.red.opacity(0.15)
        case .saving: return Color.yellow.opacity(0.2)
        }
    }
    
    private func stageBadgeForeground(_ stage: EmailFailureStage) -> Color {
        switch stage {
        case .retrieval: return .dbNavy
        case .decoding: return .dbAccent
        case .analysis: return .orange
        case .validation: return .red
        case .saving: return .brown
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}
