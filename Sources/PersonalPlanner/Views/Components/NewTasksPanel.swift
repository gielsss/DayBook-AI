import SwiftUI

/// Where a task came from, as a short name and an SF Symbol.
enum TaskSourceStyle {
    static func name(for task: DiscoveredTask) -> String {
        switch task.sourceEmail.category {
        case .canvas: return "Canvas"
        case .gradescope: return "Gradescope"
        case .quickCapture: return "Quick Capture"
        default: return "Email"
        }
    }

    static func symbol(for task: DiscoveredTask) -> String {
        switch task.sourceEmail.category {
        case .canvas: return "graduationcap.fill"
        case .gradescope: return "checkmark.seal.fill"
        case .quickCapture: return "bolt.fill"
        default: return "envelope.fill"
        }
    }
}

/// On-screen card shown when a sync finds tasks it hasn't seen before. The tasks stay highlighted as
/// "New" at the top of Tasks until you press Got It (here or there); closing the card keeps them New.
public struct NewTasksPanel: View {
    @ObservedObject var appState: AppState
    private let maxRows = 5

    public init(appState: AppState) {
        self.appState = appState
    }

    private static let due: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d, h:mm a"
        return f
    }()

    public var body: some View {
        let found = appState.newlyFoundTasks
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                DayBookIconTile(systemImage: "sparkles", color: .dbAccent, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(found.count == 1 ? "1 new task found" : "\(found.count) new tasks found")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Color.dbInk)
                    Text("Found by your last sync. They stay marked New in Tasks until you've seen them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    appState.showNewTasksPanel = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (tasks stay marked New)")
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(found.prefix(maxRows)) { task in
                    Button {
                        show(task.id)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: TaskSourceStyle.symbol(for: task))
                                .font(.caption)
                                .foregroundStyle(Color.dbAccent)
                                .frame(width: 16)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(task.displayTitle)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(Color.dbInk)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(detail(for: task))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show in Tasks")
                }
                if found.count > maxRows {
                    Text("and \(found.count - maxRows) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 24)
                }
            }

            HStack {
                Spacer()
                Button("Got It") {
                    appState.acknowledgeAllNewTasks()
                }
                .help("Move these into your regular tasks")
                Button("Show in Tasks") {
                    show(found.first?.id)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 340)
        .background(Color.dbSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.dbAccent.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New tasks found")
    }

    private func detail(for task: DiscoveredTask) -> String {
        var parts = [TaskSourceStyle.name(for: task)]
        if task.sourceEmail.category == .canvas || task.sourceEmail.category == .gradescope {
            if !task.sourceEmail.senderName.isEmpty { parts.append(task.sourceEmail.senderName) }
        }
        if let due = task.effectiveDeadline {
            parts.append("due " + Self.due.string(from: due))
        } else {
            parts.append("no due date")
        }
        return parts.joined(separator: " · ")
    }

    private func show(_ taskId: UUID?) {
        appState.selectedTab = .tasks
        if let taskId { appState.selectedTaskId = taskId }
        appState.showNewTasksPanel = false
    }
}
