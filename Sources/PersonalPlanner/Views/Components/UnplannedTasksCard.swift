import SwiftUI

/// Week: every open task with nothing planned ahead, why, and a fix right there.
public struct UnplannedTasksCard: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        let items = appState.unplannedTasks()
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    DayBookIconTile(systemImage: "tray.full", color: .orange, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(items.count == 1 ? "1 open task has nothing planned" : "\(items.count) open tasks have nothing planned")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.dbInk)
                        Text("Each one needs a decision before it can go back in the plan.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider() }
                        UnplannedTaskRow(appState: appState, item: item)
                    }
                }
            }
            .dayBookCard(padding: 16, tint: .orange)
        }
    }
}

private struct UnplannedTaskRow: View {
    @ObservedObject var appState: AppState
    let item: UnplannedTask
    @State private var showTarget = false
    @State private var showEstimate = false
    @State private var target = Date()
    @State private var minutes = 60

    private static let due: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d, h:mm a"
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.task.displayTitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.dbInk)
                    .lineLimit(1)
                Label(reasonText, systemImage: reasonSymbol)
                    .font(.caption)
                    .foregroundStyle(reasonColor)
                    .lineLimit(2)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                appState.selectedTaskId = item.task.id
                appState.selectedTab = .tasks
            }
            .help("Open in Tasks")
            Spacer(minLength: 8)
            actions
        }
        .controlSize(.small)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var actions: some View {
        switch item.reason {
        case .missedSessions:
            Button("Done") { appState.completeTask(taskId: item.task.id) }
                .help("The task is finished")
            Button("Re-plan") { appState.replanMissedWork(taskId: item.task.id) }
                .help("Plan the missed work again")
        case .deadlinePassed:
            targetButton("New Target")
            Button("Dismiss") { appState.dismissTask(taskId: item.task.id) }
        case .needsTarget:
            targetButton("Set Target")
        case .needsClarification:
            Button("Review") {
                appState.selectedTaskId = item.task.id
                appState.selectedTab = .tasks
            }
        case .wontFit:
            Button("Raise Priority") { appState.raisePriority(taskId: item.task.id) }
                .disabled(item.task.userPriority == .urgent)
            estimateButton
        case .allTimeDone:
            Button("Done") { appState.completeTask(taskId: item.task.id) }
            estimateButton
        case .notPlannedYet:
            Button("Re-plan") { appState.replanMissedWork(taskId: item.task.id) }
        }
    }

    private func targetButton(_ label: String) -> some View {
        Button(label) {
            target = Self.suggestedTarget()
            showTarget = true
        }
        .popover(isPresented: $showTarget, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Plan to finish by").font(.subheadline.weight(.semibold))
                DatePicker("", selection: $target, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.graphical)
                HStack {
                    Spacer()
                    Button("Cancel") { showTarget = false }
                    Button("Set Target") {
                        appState.setPlanningTarget(id: item.task.id, targetDate: target)
                        showTarget = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .frame(width: 300)
        }
    }

    private var estimateButton: some View {
        Button("Change Estimate") {
            minutes = item.task.effectiveDuration
            showEstimate = true
        }
        .popover(isPresented: $showEstimate, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("How long will it take?").font(.subheadline.weight(.semibold))
                Stepper(value: $minutes, in: 15...1200, step: 15) {
                    Text(AppState.durationText(minutes)).monospacedDigit()
                }
                HStack {
                    Spacer()
                    Button("Cancel") { showEstimate = false }
                    Button("Save") {
                        appState.updateTaskDuration(id: item.task.id, minutes: minutes)
                        showEstimate = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .frame(width: 260)
        }
    }

    /// Tomorrow at 5 PM.
    private static func suggestedTarget() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private var reasonText: String {
        switch item.reason {
        case .missedSessions(let n):
            return n == 1 ? "1 session was missed" : "\(n) sessions were missed"
        case .deadlinePassed(let date):
            return "Deadline passed (\(Self.due.string(from: date)))"
        case .needsTarget:
            return "No deadline: needs a target date"
        case .needsClarification:
            return "What to do isn't clear yet"
        case .wontFit(let short, let deadline):
            let by = deadline.map { " before \(Self.due.string(from: $0))" } ?? ""
            return "Won't fit\(by): \(AppState.durationText(short)) short"
        case .allTimeDone:
            return "All estimated time is done. Finished, or need more?"
        case .notPlannedYet:
            return "Not planned yet"
        }
    }

    private var reasonSymbol: String {
        switch item.reason {
        case .missedSessions: return "clock.badge.xmark"
        case .deadlinePassed: return "exclamationmark.circle"
        case .needsTarget: return "calendar.badge.plus"
        case .needsClarification: return "questionmark.circle"
        case .wontFit: return "hourglass"
        case .allTimeDone: return "checkmark.circle"
        case .notPlannedYet: return "circle.dashed"
        }
    }

    private var reasonColor: Color {
        switch item.reason {
        case .deadlinePassed, .wontFit: return .red
        case .missedSessions, .needsTarget, .needsClarification: return .orange
        case .allTimeDone, .notPlannedYet: return .secondary
        }
    }
}
