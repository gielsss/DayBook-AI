import SwiftUI

/// One quiet line under the Today header: what Sync Everything is doing, or how the last one went
/// and when the next automatic sync runs. Failed sources are listed with their reason.
public struct SyncStatusView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private var lastSyncText: String? {
        guard let last = appState.preferences.lastFullSyncDate else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(last) { return "Synced at \(Self.time.string(from: last))" }
        if cal.isDateInYesterday(last) { return "Synced yesterday at \(Self.time.string(from: last))" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "Synced \(f.string(from: last))"
    }

    private var nextSyncText: String? {
        guard appState.preferences.autoSyncEnabled,
              let next = AppState.nextAutoSyncTime(after: Date()) else { return nil }
        return "next at \(Self.time.string(from: next))"
    }

    public var body: some View {
        if appState.isSyncingAll {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(appState.syncAllProgress ?? "Syncing…")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        } else if lastSyncText != nil || !appState.lastSyncAllResults.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let lastSyncText { Text(lastSyncText) }
                    if let nextSyncText { Text("·"); Text(nextSyncText) }
                    ForEach(appState.lastSyncAllResults) { result in
                        Text("·")
                        Label(result.name, systemImage: result.succeeded ? "checkmark" : "exclamationmark.triangle.fill")
                            .foregroundStyle(result.succeeded ? Color.secondary : Color.orange)
                            .help(result.detail)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                if !appState.lastSyncAllResults.isEmpty {
                    let changes = appState.lastSyncPlanChanges
                    Text(changes.isEmpty ? "Plan unchanged."
                         : "Plan updated: " + changes.prefix(4).joined(separator: " · ") + (changes.count > 4 ? " · +\(changes.count - 4) more" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(appState.lastSyncAllResults.filter { !$0.succeeded }) { result in
                    Text("\(result.name): \(result.detail)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
