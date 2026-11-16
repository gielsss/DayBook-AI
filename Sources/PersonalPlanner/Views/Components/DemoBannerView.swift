import SwiftUI

/// Thin notice shown while the app runs on sample data. Discovery Log lives in the toolbar.
public struct DemoBannerView: View {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.dbAccent)
            Text("You're viewing sample data.")
                .fontWeight(.medium)
            Text(appState.lastSyncMessage ?? "Connect Gmail, Canvas or Apple Calendar in Settings to use your own.")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                Task { await appState.runSimulatedEmailDiscovery() }
            } label: {
                if appState.isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Re-scan Sample Inbox")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dbAccent)
            .fontWeight(.semibold)
            .disabled(appState.isSyncing)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.dbAccent.opacity(0.08))
        .background(Color.dbBackground)
        .overlay(alignment: .bottom) { Divider() }
    }
}
