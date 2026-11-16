import SwiftUI

public enum TaskFilter: String, CaseIterable, Identifiable {
    case all = "Active"
    case ready = "Ready"
    case needsClarification = "Needs Review"
    case completed = "Done"
    case dismissed = "Dismissed"
    
    public var id: String { rawValue }
}

public struct TasksView: View {
    @ObservedObject var appState: AppState
    @State private var filter: TaskFilter = .all
    @State private var showManualTaskSheet: Bool = false
    @State private var showClearDismissedConfirmation: Bool = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private var filteredTasks: [DiscoveredTask] {
        switch filter {
        case .all:
            return appState.tasks.filter { !$0.isDismissed }
        case .ready:
            return appState.tasks.filter { !$0.isCompleted && !$0.isDismissed && $0.isEligibleForScheduling }
        case .needsClarification:
            return appState.tasks.filter { !$0.isCompleted && !$0.isDismissed && !$0.isEligibleForScheduling }
        case .completed:
            return appState.tasks.filter { $0.isCompleted && !$0.isDismissed }
        case .dismissed:
            return appState.tasks.filter { $0.isDismissed }
        }
    }
    
    private var selectedTask: DiscoveredTask? {
        appState.tasks.first(where: { $0.id == appState.selectedTaskId }) ?? filteredTasks.first
    }
    
    private func formatScanDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    public var body: some View {
        HSplitView {
            // Task List Sidebar
            VStack(spacing: 0) {
                // Header & Scan Controls
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Tasks")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.dbInk)
                        
                        Spacer()
                        
                        if appState.isScanningEmails {
                            ProgressView().controlSize(.small)
                            Button("Cancel Scan", role: .cancel) {
                                appState.cancelActiveScan()
                            }
                        } else {
                            Menu {
                                Button("Scan Last 3 Days") {
                                    Task { await appState.scanEmailsFromLast3Days() }
                                }
                                Button("Test Scan (5 Emails)") {
                                    Task { await appState.testScanFiveEmails() }
                                }
                                if !appState.lastAnalyzedEmailItems.isEmpty {
                                    Divider()
                                    Button("Show Analyzed Emails (\(appState.lastAnalyzedEmailItems.count))") {
                                        appState.showAnalyzedEmailsSheet = true
                                    }
                                }
                            } label: {
                                Label("Scan Email", systemImage: "envelope")
                            }
                            .fixedSize()
                        }
                        
                        Button {
                            showManualTaskSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("Add a task by hand")
                    }
                    
                    // Scan status
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            if let active = appState.currentActiveProcessingModel {
                                Text("Model: \(active)")
                                if active != appState.ollamaModel {
                                    Text("(fallback)").foregroundColor(.orange)
                                }
                            } else {
                                Text("Model: \(appState.ollamaModel)")
                            }
                            Text("· reads email bodies only")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        // Live Email Processing Counters
                        if appState.isScanningEmails || appState.lastScanDate != nil || !appState.failedEmailRecords.isEmpty {
                            HStack(spacing: 8) {
                                Text("New: **\(appState.scanNewCount)**")
                                    .font(.system(size: 10))
                                    .foregroundColor(.dbAccent)
                                    .help("New emails discovered in inbox from last 3 days (72h)")
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text("Analyzed: **\(appState.scanProcessedCount)**")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)
                                    .help("Emails analyzed with Ollama")
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text("Cached: **\(appState.scanCachedCount)**")
                                    .font(.system(size: 10))
                                    .foregroundColor(.dbNavy)
                                    .help("Emails loaded from local cache with zero API calls")
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text("Pending: **\(appState.scanPendingCount)**")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .help("Emails waiting to be analyzed")
                                if appState.scanFailedCount > 0 || !appState.failedEmailRecords.isEmpty {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Button(action: {
                                        appState.showFailedEmailsSheet = true
                                    }) {
                                        HStack(spacing: 3) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                            Text("Failed: **\(appState.failedEmailRecords.count)**")
                                        }
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Click to view failure details and retry")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        
                        // Fallback Plain-Language Explanation
                        
                        // Countdown Banner
                        
                        if let progress = appState.scanProgressText {
                            Text(progress)
                                .font(.caption2)
                                .foregroundColor(.dbAccent)
                        }
                        
                        HStack(spacing: 12) {
                            Text("Coverage: **Last 3 days (72h)**")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("Last check: **\(appState.lastCompletedCheckText)**")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if let error = appState.lastScanError {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption2)
                                Text(error)
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                            .padding(4)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(4)
                        }
                        
                        if let summary = appState.lastScanSuccessSummary {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption2)
                                Text(summary)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(4)
                            .background(Color.green.opacity(0.08))
                            .cornerRadius(4)
                        }
                    }
                    
                    Picker("Filter", selection: $filter) {
                        ForEach(TaskFilter.allCases) { f in
                            Text(countLabel(for: f)).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(12)
                
                if appState.tasks.contains(where: { $0.sourceEmail.isSimulatedDemo }) {
                    HStack(spacing: 8) {
                        Image(systemName: "flask.fill")
                            .foregroundColor(.dbAccent)
                            .font(.caption)
                        Text("Sample demo tasks present")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Remove Demos") {
                            appState.removeDemonstrationData()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.dbAccent.opacity(0.08))
                }
                
                if filter == .dismissed && !filteredTasks.isEmpty {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dismissed Tasks (\(filteredTasks.count))")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("Clear these from view while preserving source IDs to prevent recreation.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: {
                            showClearDismissedConfirmation = true
                        }) {
                            Label("Clear Dismissed", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.08))
                }
                
                Divider()
                
                // Tasks list
                if filteredTasks.isEmpty {
                    DayBookEmptyState(
                        filter == .dismissed ? "No dismissed tasks" : (appState.tasks.isEmpty ? "A blank page" : "Nothing here"),
                        message: filter == .all && appState.tasks.isEmpty
                            ? "Scan your email to fill in the last 3 days (72h), or add a task with +."
                            : (filter == .dismissed ? nil : "No tasks match this filter.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let newTasks = filter == .completed || filter == .dismissed
                        ? [] : filteredTasks.filter { appState.isNewlyFound($0.id) }
                    List(selection: $appState.selectedTaskId) {
                        if !newTasks.isEmpty {
                            // New from a sync: highlighted here until you've seen them, then they join the list below.
                            Section {
                                ForEach(newTasks) { task in
                                    taskRow(for: task)
                                        .tag(task.id)
                                        .listRowBackground(Color.dbAccent.opacity(0.10))
                                }
                            } header: {
                                HStack {
                                    Label("New from Sync (\(newTasks.count))", systemImage: "sparkles")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.dbAccent)
                                    Spacer()
                                    Button("Got It") { appState.acknowledgeAllNewTasks() }
                                        .controlSize(.small)
                                        .help("Move these into your regular tasks")
                                }
                            }
                        }
                        let regularTasks = filteredTasks.filter { !newTasks.map(\.id).contains($0.id) }
                        if !regularTasks.isEmpty {
                            Section {
                                ForEach(regularTasks) { task in
                                    taskRow(for: task)
                                        .tag(task.id)
                                }
                            } header: {
                                if !newTasks.isEmpty {
                                    Text("Tasks")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 340, idealWidth: 380, maxWidth: 480)
            
            // Task Detail Pane
            if let task = selectedTask {
                TaskDetailView(task: task, appState: appState)
                    .frame(minWidth: 420)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Select a task to inspect details, required actions, and email provenance.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showManualTaskSheet) {
            ManualTaskBackupSheet(appState: appState)
        }
        .sheet(isPresented: $appState.showAnalyzedEmailsSheet) {
            AnalyzedEmailsView(appState: appState)
        }
        .sheet(isPresented: $appState.showFailedEmailsSheet) {
            FailedEmailsSheet(appState: appState)
        }
        .confirmationDialog(
            "Clear Dismissed Tasks?",
            isPresented: $showClearDismissedConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Dismissed Tasks", role: .destructive) {
                appState.clearDismissedTasks()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all dismissed tasks from the visible list. Their source email and thread identifiers are permanently preserved in dismissal history so future scans will not recreate them.")
        }
    }
    
    private func countLabel(for f: TaskFilter) -> String {
        switch f {
        case .all: return "Active (\(appState.tasks.filter { !$0.isDismissed }.count))"
        case .ready: return "Ready (\(appState.tasks.filter { !$0.isCompleted && !$0.isDismissed && $0.isEligibleForScheduling }.count))"
        case .needsClarification: return "Review (\(appState.tasks.filter { !$0.isCompleted && !$0.isDismissed && !$0.isEligibleForScheduling }.count))"
        case .completed: return "Done (\(appState.tasks.filter { $0.isCompleted && !$0.isDismissed }.count))"
        case .dismissed: return "Dismissed (\(appState.tasks.filter { $0.isDismissed }.count))"
        }
    }
    
    private func formatDeadline(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
    
    private func taskRow(for task: DiscoveredTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: {
                    appState.toggleTaskCompletion(id: task.id)
                }) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(task.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)
                
                Text(task.displayTitle)
                    .font(.headline)
                    .strikethrough(task.isCompleted)
                    .lineLimit(2)
                if appState.isNewlyFound(task.id) && !task.isCompleted {
                    Text("New")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.dbAccent)
                        .help("Found by your last sync")
                } else if task.hasUnseenUpdate, let update = task.syncUpdate {
                    TaskUpdatedBadge(update)
                }
                if !task.isCompleted, let urgency = appState.lastSchedulingResult?.urgencyByTaskId[task.id] {
                    UrgencyTag(urgency)
                }
                Spacer(minLength: 4)
                OpenSourceButton(appState: appState, task: task, compact: true)
            }
            
            if !task.requiredAction.isEmpty && task.requiredAction != task.displayTitle {
                Text(task.requiredAction)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            HStack(spacing: 6) {
                Text("From: \(task.sourceEmail.senderName)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                if task.sourceEmail.isSimulatedDemo {
                    Text(appState.preferences.includeDemoDataInPlan ? "Demo" : "Demo (Excluded)")
                        .font(.caption2)
                        .foregroundColor(.dbAccent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.dbAccent.opacity(0.12))
                        .cornerRadius(3)
                }
                
                let taskSessions = appState.workSessions.filter { $0.taskId == task.id }
                if !taskSessions.isEmpty {
                    Text("Scheduled (\(taskSessions.count))")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(3)
                }
                
                switch task.schedulingEligibility {
                case .completed, .dismissed:
                    EmptyView()
                case .deadlinePassed(let dl):
                    Text("Overdue")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.red.opacity(0.18))
                        .cornerRadius(3)
                    Text(formatDeadline(dl))
                        .font(.caption2)
                        .foregroundColor(.red)
                case .needsPlanningTarget:
                    Text("Needs Target")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(3)
                case .needsActionClarification:
                    Text("Needs Clarification")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(3)
                case .eligible:
                    if task.hasPlanningTarget {
                        Text("Target: \(formatDeadline(task.effectiveDeadline!))")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.dbNavy)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.dbNavy.opacity(0.15))
                            .cornerRadius(3)
                    } else if let deadline = task.effectiveDeadline {
                        Text(formatDeadline(deadline))
                            .font(.caption2)
                            .foregroundColor(.dbNavy)
                    }
                }
                
                Text("\(task.effectiveDuration)m est")
                    .font(.caption2)
                    .foregroundColor(task.needsEstimateCheck ? .orange : .secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(task.needsEstimateCheck ? Color.orange.opacity(0.15) : Color.gray.opacity(0.15))
                    .cornerRadius(3)
                    .help(task.needsEstimateCheck ? "Check Estimate: the AI had little to go on" : "Estimated time")
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if appState.isNewlyFound(task.id) {
                Button("Got It") { appState.acknowledgeNewTask(task.id) }
            }
            if task.needsEstimateCheck {
                Button("Estimate Looks Right") { appState.confirmEstimate(taskId: task.id) }
            }
            OpenSourceMenuItem(appState: appState, task: task)
        }
    }
}

// Backup manual task entry sheet
public struct ManualTaskBackupSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var durationMinutes: Int = 60
    @State private var hasDeadline: Bool = true
    @State private var deadline: Date = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Manual Task (Optional Backup)")
                        .font(.headline)
                    Text("Email discovery is the primary experience. Use this only for offline or manual tasks.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            .background(Color.dbBackground)
            
            Divider()
            
            Form {
                TextField("Task Title:", text: $title)
                TextField("Notes / Details:", text: $notes)
                Stepper("Estimated Duration: \(durationMinutes) min", value: $durationMinutes, in: 15...480, step: 15)
                
                Toggle("Set Extracted Deadline", isOn: $hasDeadline)
                if hasDeadline {
                    DatePicker("Deadline:", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .padding(20)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Save Task") {
                    let manualEmail = EmailSource(
                        id: "manual-\(UUID().uuidString.prefix(6))",
                        threadId: "manual-backup-thread",
                        senderName: "Manual Task Entry",
                        senderEmail: "me@local.device",
                        subject: "Direct Manual Entry (Backup)",
                        receivedDate: Date(),
                        snippet: title,
                        fullBody: notes.isEmpty ? "Manually entered task." : notes,
                        category: .assignment,
                        isSimulatedDemo: false
                    )
                    
                    let newTask = DiscoveredTask(
                        title: title.isEmpty ? "Untitled Manual Task" : title,
                        requiredAction: title.isEmpty ? "Manual Task" : title,
                        notes: notes,
                        sourceEmail: manualEmail,
                        extractedDeadline: hasDeadline ? deadline : nil,
                        isDeadlineSupportedByEmail: hasDeadline,
                        supportingExcerpt: notes,
                        estimatedMinutes: durationMinutes,
                        status: .ready,
                        isClarified: true
                    )
                    
                    appState.tasks.append(newTask)
                    appState.selectedTaskId = newTask.id
                    appState.recalculateSchedule()
                    appState.saveDatabase()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 340)
    }
}
