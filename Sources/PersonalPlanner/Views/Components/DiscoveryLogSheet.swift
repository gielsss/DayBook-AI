import SwiftUI

public struct DiscoveryLogSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private func iconForAction(_ action: DiscoveryAction) -> (String, Color) {
        switch action {
        case .taskCreated:
            return ("checkmark.circle.fill", .dbNavy)
        case .taskNeedsClarification:
            return ("questionmark.circle.fill", .orange)
        case .taskUpdated:
            return ("arrow.triangle.2.circlepath.circle.fill", .green)
        case .ignoredNewsletter:
            return ("line.3.horizontal.decrease.circle.fill", .dbAccent)
        case .taskDismissed:
            return ("xmark.circle.fill", .red)
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Email Discovery & Processing Log")
                        .font(.headline)
                    Text("Audit trail of simulated extractor analyzing sample emails")
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
            .background(Color.dbBackground)
            
            Divider()
            
            if appState.logs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No emails scanned yet.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.logs) { log in
                        let (iconName, color) = iconForAction(log.action)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: iconName)
                                    .foregroundColor(color)
                                    .font(.system(size: 16))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(log.subject)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        
                                        Spacer()
                                        
                                        Text(log.action.rawValue)
                                            .font(.caption.weight(.medium))
                                            .foregroundColor(color)
                                    }
                                    
                                    Text("From: \(log.sender)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Text(log.explanation)
                                .font(.caption)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.dbSurface)
                                .cornerRadius(6)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 550, minHeight: 420)
    }
}
