import SwiftUI
import AppKit

public struct TaskDetailView: View {
    public let task: DiscoveredTask
    @ObservedObject var appState: AppState
    
    @State private var clarificationDate: Date = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    @State private var clarificationNotes: String = ""
    @State private var durationInput: Int = 45
    @State private var isEditingUserTitle: Bool = false
    @State private var editedTitle: String = ""
    @State private var isEditingAction: Bool = false
    @State private var editedAction: String = ""
    @State private var planningTargetInput: Date = Date()
    @State private var showPlanningTargetPicker: Bool = false
    
    public init(task: DiscoveredTask, appState: AppState) {
        self.task = task
        self.appState = appState
        _durationInput = State(initialValue: task.effectiveDuration)
        _editedTitle = State(initialValue: task.displayTitle)
        _editedAction = State(initialValue: task.requiredAction)
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = appState.preferences.timeZone
        if let existing = task.planningTargetDate {
            _planningTargetInput = State(initialValue: existing)
        } else {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            let endOfWorkday = cal.date(
                bySettingHour: appState.preferences.workEndHour,
                minute: appState.preferences.workEndMinute,
                second: 0,
                of: tomorrow
            ) ?? tomorrow
            _planningTargetInput = State(initialValue: endOfWorkday)
        }
    }
    
    private var sourceHeading: String {
        switch task.sourceEmail.category {
        case .canvas: return "Found in Canvas"
        case .gradescope: return "Found in Gradescope"
        case .quickCapture: return "From Quick Capture"
        default: return "Original Email"
        }
    }

    private var associatedSessions: [WorkSession] {
        appState.workSessions.filter { $0.taskId == task.id }
    }
    
    /// What the AI estimate was based on: files it read and files it couldn't open.
    private func estimateBasis(_ task: DiscoveredTask) -> String? {
        guard task.estimateNote != nil, task.userOverriddenDuration == nil, let details = task.assignmentDetails else { return nil }
        let read = details.components(separatedBy: "\n").compactMap { line -> String? in
            guard line.hasPrefix("Attached file \""), let end = line.lastIndex(of: "\"") else { return nil }
            return String(line[line.index(line.startIndex, offsetBy: 15)..<end])
        }
        let unread = details.components(separatedBy: "\n")
            .first { $0.hasPrefix("Attached files that couldn't be read: ") }?
            .dropFirst("Attached files that couldn't be read: ".count)
        var parts: [String] = []
        if details.contains("Rubric:\n") { parts.append("rubric") }
        if !read.isEmpty { parts.append(read.joined(separator: ", ")) }
        var text = parts.isEmpty ? "" : "Based on the instructions, " + parts.joined(separator: " and ")
        if let unread { text += (text.isEmpty ? "" : ". ") + "Couldn't open: \(unread)" }
        return text.isEmpty ? nil : text
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = appState.preferences.timeZone
        let tzAbbr = appState.preferences.timeZone.abbreviation(for: date) ?? ""
        return "\(formatter.string(from: date)) (\(tzAbbr))"
    }
    
    private func provenanceIcon(_ p: DeadlineProvenance) -> String {
        switch p {
        case .explicitDateTime: return "calendar.badge.clock"
        case .dateOnly: return "calendar"
        case .relativeWindow: return "hourglass"
        case .userTarget: return "person.badge.shield.checkmark"
        case .userOverridden: return "pencil.and.outline"
        case .unsupported: return "questionmark.circle"
        }
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with title and action controls
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        if isEditingUserTitle {
                            HStack {
                                TextField("Edit Title", text: $editedTitle)
                                    .textFieldStyle(.roundedBorder)
                                Button("Save") {
                                    appState.updateTaskUserOverrides(id: task.id, title: editedTitle)
                                    isEditingUserTitle = false
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else {
                            HStack(spacing: 8) {
                                Text(task.displayTitle)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .strikethrough(task.isCompleted)
                                
                                Button(action: {
                                    editedTitle = task.displayTitle
                                    isEditingUserTitle = true
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Edit task title (correction preserved across scans)")
                            }
                        }
                        
                        // Required Action
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checklist")
                                .foregroundColor(.dbNavy)
                                .font(.caption)
                                .padding(.top, 2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Required Action:")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                Text(task.requiredAction)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.dbNavy.opacity(0.08))
                        .cornerRadius(6)
                        
                        HStack(spacing: 8) {
                            statusBadge(for: task.status)
                            
                            // User-set priority picker
                            Menu {
                                ForEach(TaskPriority.allCases, id: \.self) { prio in
                                    Button(action: {
                                        appState.setTaskPriority(id: task.id, priority: prio)
                                    }) {
                                        HStack {
                                            Text(prio.rawValue)
                                            if task.userPriority == prio {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "flag.fill")
                                        .foregroundColor(priorityColor(task.userPriority))
                                    Text("Priority: \(task.userPriority.rawValue)")
                                }
                                .font(.caption2)
                            }
                            .menuStyle(.borderlessButton)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(priorityColor(task.userPriority).opacity(0.12))
                            .cornerRadius(4)
                            
                            Label("\(task.effectiveDuration) min estimated (Estimate)", systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 8) {
                        Button(action: {
                            appState.toggleTaskCompletion(id: task.id)
                        }) {
                            Label(
                                task.isCompleted ? "Completed ✓" : "Mark Complete",
                                systemImage: task.isCompleted ? "checkmark.circle.fill" : "circle"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(task.isCompleted ? .gray : .green)
                        
                        if task.isDismissed {
                            Button("Restore Task") {
                                appState.restoreTask(id: task.id)
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Dismiss Task") {
                                appState.dismissTask(id: task.id)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .help("Dismisses this task and prevents it from reappearing in future scans.")
                        }
                    }
                }
                
                Divider()
                
                // Supporting Excerpt from Email
                if !task.supportingExcerpt.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "quote.opening")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("Supporting Email Excerpt")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("“\(task.supportingExcerpt)”")
                            .font(.system(.body, design: .serif))
                            .italic()
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                
                // Deadline & Planning Target Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Deadline & Planning Target")
                            .font(.headline)
                        Spacer()
                        if task.isOriginalDeadlineOverdue && !task.hasPlanningTarget {
                            Text("Overdue")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.red)
                        } else if task.hasPlanningTarget {
                            Text("User Target Confirmed")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.dbNavy)
                        }
                    }
                    
                    // Original Extracted Deadline Provenance
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: provenanceIcon(task.originalDeadlineProvenance))
                                .foregroundColor(task.isOriginalDeadlineOverdue ? .red : .dbNavy)
                            Text("Email Provenance: \(task.originalDeadlineProvenance.rawValue)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(task.isOriginalDeadlineOverdue ? .red : .dbNavy)
                            Spacer()
                        }
                        
                        if let origDeadline = task.extractedDeadline, task.isDeadlineSupportedByEmail {
                            HStack(spacing: 6) {
                                Text(formatDate(origDeadline))
                                    .font(.body)
                                    .fontWeight(.medium)
                                if task.isOriginalDeadlineOverdue {
                                    Text("(Passed / Overdue)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.red)
                                }
                            }
                            
                            if let wording = task.originalDeadlineWording {
                                Text("Original Wording: \"\(wording)\"")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }
                            
                            if let dateStr = task.dateOnlyDeadlineString {
                                Text("Calendar Date: \(dateStr) (Stored as calendar date; not an invented UTC time)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let tz = task.timeZoneAssumption {
                                Text("Timezone Assumption: \(tz)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            if task.originalDeadlineProvenance == .dateOnly {
                                Text("Evaluated using your '\(appState.preferences.dateOnlyDeadlinePolicy.shortTitle)' policy.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else if task.originalDeadlineProvenance == .relativeWindow {
                                Text("Extracted as elapsed time from email receipt timestamp.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("No deadline stated in email. Original deadline remains unknown.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let tz = task.timeZoneAssumption {
                                Text("Timezone: \(tz)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((task.isOriginalDeadlineOverdue && !task.hasPlanningTarget ? Color.red : Color.dbNavy).opacity(0.08))
                    .cornerRadius(6)
                    
                    // Planning Target (Lets user schedule work without overwriting original deadline)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Planning Target:")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            if let target = task.planningTargetDate {
                                Text(formatDate(target))
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.dbNavy)
                                Text("(User-Selected)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Clear Target") {
                                    appState.setPlanningTarget(id: task.id, targetDate: nil)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Text("None set")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if task.planningTargetDate == nil {
                            if task.originalDeadlineProvenance == .unsupported {
                                Text("This task has no deadline in the email. To schedule work sessions, explicitly confirm a future planning target below. The original email deadline will remain unknown.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if task.isOriginalDeadlineOverdue {
                                Text("Since this task's original deadline has passed, the planner will not schedule sessions into the past. Choose a new planning target date to schedule work sessions without modifying the original email deadline record.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack(spacing: 8) {
                            Button("Today 5 PM") {
                                var cal = Calendar(identifier: .gregorian)
                                cal.timeZone = appState.preferences.timeZone
                                let target = cal.date(bySettingHour: appState.preferences.workEndHour, minute: appState.preferences.workEndMinute, second: 0, of: Date()) ?? Date()
                                planningTargetInput = target
                                appState.setPlanningTarget(id: task.id, targetDate: target)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button("Tomorrow 5 PM") {
                                var cal = Calendar(identifier: .gregorian)
                                cal.timeZone = appState.preferences.timeZone
                                let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                                let target = cal.date(bySettingHour: appState.preferences.workEndHour, minute: appState.preferences.workEndMinute, second: 0, of: tomorrow) ?? tomorrow
                                planningTargetInput = target
                                appState.setPlanningTarget(id: task.id, targetDate: target)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            DatePicker("Target Date:", selection: $planningTargetInput, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                            Button("Set Custom") {
                                appState.setPlanningTarget(id: task.id, targetDate: planningTargetInput)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dbSurface)
                    .cornerRadius(6)
                    
                    if task.sourceEmail.isSimulatedDemo && !appState.preferences.includeDemoDataInPlan {
                        HStack(spacing: 8) {
                            Image(systemName: "flask.fill")
                                .foregroundColor(.dbAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Demonstration Task (Excluded from Schedule)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.dbAccent)
                                Text("This task is sample demonstration data. To include demonstration tasks in your schedule, enable 'Include demonstration tasks in proposed plan' in Settings.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.dbAccent.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    // New from a sync: stays at the top of Tasks until you've seen it
                    if appState.isNewlyFound(task.id) && !task.isCompleted {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.dbAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("New from \(TaskSourceStyle.name(for: task))")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text("Found by your last sync. Press Got It to move it into your regular tasks.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Got It") {
                                appState.acknowledgeNewTask(task.id)
                            }
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(Color.dbAccent.opacity(0.1))
                        .cornerRadius(6)
                    }

                    // "Updated" reminder from a later sync (task memory)
                    if task.hasUnseenUpdate, let update = task.syncUpdate {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.dbAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Updated from \(update.source) · \(update.date.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(update.summary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Got It") {
                                appState.acknowledgeTaskUpdate(taskId: task.id)
                            }
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(Color.dbAccent.opacity(0.1))
                        .cornerRadius(6)
                    } else if let updateNote = task.deadlineUpdateNote {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Deadline Updated")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                                Text(updateNote)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                
                // Informational Uncertain Details (If any)
                if !task.uncertainDetails.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.dbNavy)
                            Text("Informational Extraction Notes")
                                .font(.headline)
                                .foregroundColor(.dbNavy)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(task.uncertainDetails, id: \.self) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .foregroundColor(.dbNavy)
                                    Text(item)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.dbNavy.opacity(0.08))
                        .cornerRadius(6)
                    }
                }
                
                // Clarification Card (Only if required action is unclear)
                if task.isActionUnclear {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Required Action Unclear: Needs Clarification")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                        
                        TextField("Clarify Required Action / Scope:", text: $clarificationNotes)
                            .textFieldStyle(.roundedBorder)
                        
                        HStack {
                            Spacer()
                            Button("Save Clarification") {
                                appState.clarifyTask(id: task.id, targetDeadline: nil, notes: clarificationNotes)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Estimated Duration Adjuster
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Estimated Duration:")
                            .font(.headline)
                        Text("(Estimate)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Stepper(value: $durationInput, in: 15...600, step: 15) {
                            Text("\(durationInput) minutes (\(String(format: "%.1f", Double(durationInput)/60.0)) hours)")
                                .font(.body)
                        }
                        .onChange(of: durationInput) { _, newValue in
                            appState.updateTaskDuration(id: task.id, minutes: newValue)
                        }
                        Spacer()
                    }
                    if let note = task.estimateNote, task.userOverriddenDuration == nil {
                        Label(note, systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let basis = estimateBasis(task) {
                        Label(basis, systemImage: "doc.text.magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if task.needsEstimateCheck {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                            Text("Check this estimate: the AI had little to go on. Change the time above, or keep it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Button("Looks Right") { appState.confirmEstimate(taskId: task.id) }
                                .controlSize(.small)
                        }
                    }
                    if !task.isCompleted, let urgency = appState.lastSchedulingResult?.urgencyByTaskId[task.id] {
                        HStack(spacing: 6) {
                            UrgencyTag(urgency)
                            Text(urgency.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let note = task.calibrationNote, task.userOverriddenDuration == nil {
                        Label(note, systemImage: "chart.line.uptrend.xyaxis")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Source Email & Link to Original Message
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(sourceHeading)
                            .font(.headline)
                        Spacer()
                        OpenSourceButton(appState: appState, task: task)
                    }
                    
                    EmailSourceBadge(email: task.sourceEmail)
                }
                
                // Scheduled Work Sessions
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Scheduled Work Sessions (\(associatedSessions.count))")
                            .font(.headline)
                        Spacer()
                        Text("Tasks are separate from planned work sessions")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if associatedSessions.isEmpty {
                        let report = appState.lastSchedulingResult?.unscheduledReports.first(where: { $0.task.id == task.id })
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.subheadline)
                                Text(report != nil ? "Unscheduled: \(report!.primaryReason.rawValue)" : (task.status == .needsClarification ? "Needs Clarification" : "Not Scheduled in Current Plan"))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            }
                            
                            if let rep = report {
                                Text(rep.detailedExplanation)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            } else if task.isOriginalDeadlineOverdue && !task.hasPlanningTarget {
                                Text("This task's deadline passed in the past. Set a planning target above to allow the scheduler to allocate work sessions before that target.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if task.status == .needsClarification {
                                Text("Work sessions will be scheduled once the task's deadline is clarified.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Generate a proposed plan to calculate work session slots for this task.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(associatedSessions) { session in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("\(formatDate(session.startTime)) - \(formatDate(session.endTime)) (\(session.durationMinutes) min)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    
                                    Button(action: {
                                        appState.toggleSessionStatus(id: session.id)
                                    }) {
                                        Text(session.status.rawValue)
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding(10)
                                .background(Color.dbSurface)
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    private func statusBadge(for status: TaskStatus) -> some View {
        let (color, name): (Color, String) = {
            switch status {
            case .discovered: return (.dbNavy, "Discovered")
            case .needsClarification: return (.orange, "Needs Clarification")
            case .ready: return (.green, "Ready to Schedule")
            case .completed: return (.gray, "Completed")
            case .dismissed: return (.red, "Dismissed")
            }
        }()
        
        return Text(name)
     .font(.caption.weight(.medium))
     .foregroundColor(color)
    }
    
    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .dbNavy
        case .low: return .secondary
        }
    }
}
