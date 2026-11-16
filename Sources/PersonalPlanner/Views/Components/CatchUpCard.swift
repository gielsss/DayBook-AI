import SwiftUI

/// Today: sessions that ended without being checked off. Until answered they count as not done (their
/// work is already planned again); Done counts them as finished work.
public struct CatchUpCard: View {
    @ObservedObject var appState: AppState
    @State private var showAll = false
    private let collapsedCount = 4

    public init(appState: AppState) {
        self.appState = appState
    }

    private static let when: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d, h:mm a"
        return f
    }()

    public var body: some View {
        let missed = appState.missedSessions()
        if !missed.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    DayBookIconTile(systemImage: "clock.arrow.circlepath", color: .orange, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(missed.count == 1 ? "1 earlier session wasn't checked off" : "\(missed.count) earlier sessions weren't checked off")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.dbInk)
                        Text("Until you answer, they count as not done and their work is planned again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Menu {
                        Button("All of These Got Done") { appState.answerAllMissedSessions(done: true) }
                        Button("None of These Got Done") { appState.answerAllMissedSessions(done: false) }
                    } label: {
                        Text("Answer All")
                    }
                    .fixedSize()
                    .controlSize(.small)
                }

                VStack(spacing: 0) {
                    ForEach(Array((showAll ? missed : Array(missed.prefix(collapsedCount))).enumerated()), id: \.element.id) { index, session in
                        if index > 0 { Divider() }
                        row(session)
                    }
                }

                if missed.count > collapsedCount {
                    Button(showAll ? "Show Fewer" : "Show \(missed.count - collapsedCount) More") {
                        withAnimation(.easeInOut(duration: 0.2)) { showAll.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dbAccent)
                }
            }
            .dayBookCard(padding: 16, tint: .orange)
        }
    }

    private func row(_ session: WorkSession) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: session))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.dbInk)
                    .lineLimit(1)
                Text("\(Self.when.string(from: session.startTime)) · \(session.durationMinutes)m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Done") {
                withAnimation(.easeInOut(duration: 0.2)) { appState.answerMissedSession(id: session.id, done: true) }
            }
            Button("Not Done Yet") {
                withAnimation(.easeInOut(duration: 0.2)) { appState.answerMissedSession(id: session.id, done: false) }
            }
            .help("Plan this work again, with carryover priority")
        }
        .controlSize(.small)
        .padding(.vertical, 7)
    }

    private func title(for session: WorkSession) -> String {
        if let id = session.taskId, let task = appState.tasks.first(where: { $0.id == id }) { return task.displayTitle }
        return session.title.replacingOccurrences(of: "Work Session: ", with: "")
    }
}
