import SwiftUI

public struct AnalyzedEmailsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analyzed Emails")
                        .font(.headline)
                    Text("Compare analyzed emails and discovered tasks directly with your Gmail inbox.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            
            Divider()
            
            if appState.lastAnalyzedEmailItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No emails analyzed in the recent scan")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Run 'Test Scan (5 Emails)' to inspect live extraction results.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section(header: Text("Emails Analyzed in Most Recent Scan (\(appState.lastAnalyzedEmailItems.count))")) {
                        ForEach(appState.lastAnalyzedEmailItems) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.subject)
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack(spacing: 8) {
                                    Text("From: \(item.sender)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("Model: \(item.modelUsed)")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.12))
                                        .cornerRadius(3)
                                }
                                
                                HStack(spacing: 6) {
                                    Image(systemName: item.tasksDiscoveredCount > 0 ? "checkmark.circle.fill" : "info.circle")
                                        .foregroundColor(item.tasksDiscoveredCount > 0 ? .green : .secondary)
                                        .font(.caption2)
                                    Text(item.statusDescription)
                                        .font(.caption2)
                                        .fontWeight(item.tasksDiscoveredCount > 0 ? .semibold : .regular)
                                        .foregroundColor(item.tasksDiscoveredCount > 0 ? .primary : .secondary)
                                }
                                
                                if !item.taskTitles.isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Discovered Tasks:")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.secondary)
                                        ForEach(item.taskTitles, id: \.self) { title in
                                            HStack(alignment: .top, spacing: 4) {
                                                Text("•")
                                                    .font(.caption2)
                                                    .foregroundColor(.dbAccent)
                                                Text(title)
                                                    .font(.caption2)
                                            }
                                        }
                                    }
                                    .padding(.top, 2)
                                    .padding(.leading, 8)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 540, minHeight: 400)
    }
}
