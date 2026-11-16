import SwiftUI

public struct WeekView: View {
    @ObservedObject var appState: AppState
    @State private var dayRangeCount: Int = 14
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private var weekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<dayRangeCount).compactMap { dayOffset in
            cal.date(byAdding: .day, value: dayOffset, to: today)
        }
    }
    
    private func dayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                DayBookPageHeader("Week", subtitle: "Deadlines, events and planned work for the next \(dayRangeCount) days") {
                    HStack(spacing: 8) {
                        Picker("Range", selection: $dayRangeCount) {
                            Text("7 Days").tag(7)
                            Text("14 Days").tag(14)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 140)
                        
                        if let result = appState.lastSchedulingResult, (!result.unscheduledReports.isEmpty || !result.ambiguousTasks.isEmpty) {
                            Button {
                                appState.showUnscheduledSheet = true
                            } label: {
                                Label("\(result.unscheduledReports.count) Unscheduled", systemImage: "exclamationmark.triangle")
                            }
                            .help("Review tasks that couldn't be scheduled")
                        }
                        
                        Button {
                            appState.showReviewAndPublishSheet = true
                        } label: {
                            Label("Publish", systemImage: "square.and.arrow.up")
                        }
                        .help("Review proposed sessions and add them to Apple Calendar")
                        
                        Button {
                            appState.generateProposedPlan(isAutomatic: false)
                        } label: {
                            if appState.isGeneratingSchedule {
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.small)
                                    Text("Planning…")
                                }
                            } else {
                                Label("Plan Week", systemImage: "wand.and.stars")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.isGeneratingSchedule)
                        .help("Generate a proposed plan around your calendar")
                        
                        Menu {
                            Button {
                                appState.showCreateActivitySheet = true
                            } label: {
                                Label("Add Activity…", systemImage: "plus")
                            }
                            if appState.calendarAuthorizationStatus == .authorized {
                                Button {
                                    Task { await appState.refreshCalendarCommitments(isAutomatic: false) }
                                } label: {
                                    Label("Refresh Calendar", systemImage: "arrow.clockwise")
                                }
                                .disabled(appState.isRefreshingCalendar)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("More")
                    }
                }
                
                if let status = appState.schedulingStatusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.dbAccent)
                            .font(.caption)
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Replan & Undo Banner
                if let explanation = appState.replanExplanation {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.swap")
                            .foregroundColor(.dbAccent)
                        Text(explanation)
                            .font(.caption)
                            .foregroundColor(.primary)
                        Spacer()
                        if appState.lastUndoSnapshot != nil {
                            Button("Undo") {
                                appState.undoLatestReplan()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        Button {
                            appState.replanExplanation = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.dbAccent.opacity(0.12))
                    .cornerRadius(8)
                }
                
                // Discrepancy warning banner
                if !appState.externalDiscrepancies.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(appState.externalDiscrepancies.count) Calendar Discrepanc\(appState.externalDiscrepancies.count == 1 ? "y" : "ies") Detected")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                            Text("Events were moved, deleted, or conflicted externally in Apple Calendar.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Review Changes") {
                            appState.showDiscrepancySheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(8)
                }
                
                // Open tasks with nothing planned ahead, and how to fix each.
                UnplannedTasksCard(appState: appState)

                // Legend
                HStack(spacing: 16) {
                    legendItem(color: .red, title: "Deadline", icon: "flag.fill")
                    legendItem(color: .green, title: "Done", icon: "checkmark.circle.fill")
                    legendItem(color: .dbAccent, title: "Planned Work", icon: "deskclock")
                    legendItem(color: .dbNavy, title: "Calendar", icon: "calendar")
                    legendItem(color: .orange, title: "Overlap", icon: "exclamationmark.triangle.fill")
                    Spacer()
                    Text("Drag a session onto a day or after an item to move it")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 2)
                
                // 7-day cards
                VStack(spacing: 16) {
                    ForEach(weekDays, id: \.self) { day in
                        dayCard(for: day)
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $appState.showUnscheduledSheet) {
            UnscheduledTasksSheet(appState: appState)
        }
        .sheet(item: $appState.sessionBeingEdited) { session in
            EditSessionSheet(appState: appState, session: session)
        }
        .sheet(isPresented: $appState.showReviewAndPublishSheet) {
            ReviewAndPublishSheet(appState: appState)
        }
        .sheet(isPresented: $appState.showDiscrepancySheet) {
            CalendarDiscrepancySheet(appState: appState)
        }
        .sheet(item: $appState.sessionForCarryover) { session in
            CarryoverConfirmationSheet(appState: appState, session: session)
        }
    }
    
    private func legendItem(color: Color, title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func dayCard(for day: Date) -> some View {
        let dayData = UnifiedTimelineEngine.buildDayData(
            day: day,
            tasks: appState.tasks,
            workSessions: appState.workSessions,
            commitments: appState.commitments,
            timeZone: appState.preferences.timeZone
        )
        let isCurrent = isToday(day)
        let daySessionsCount = dayData.timedItems.filter { $0.isWorkSession }.count
        let dayDeadlinesCount = dayData.deadlines.count
        
        return VStack(alignment: .leading, spacing: 10) {
            // Day header
            HStack {
                Text(dayTitle(day))
                    .font(.headline)
                    .foregroundColor(isCurrent ? .dbAccent : .primary)
                
                if isCurrent {
                    Text("Today")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.dbAccent)
                }
                
                Spacer()
                
                Text("\(daySessionsCount) work sessions • \(dayDeadlinesCount) deadlines")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // 1. Deadlines due on this day (Flag / Target), sorted by due time
            if !dayData.deadlines.isEmpty {
                let hasIncomplete = dayData.deadlines.contains(where: { !$0.isCompleted })
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(isCurrent ? "Due Today" : "Due")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    ForEach(dayData.deadlines) { task in
                        let isDone = task.isCompleted
                        let boxColor: Color = isDone ? .green : .red
                        
                        HStack(spacing: 8) {
                            Button(action: {
                                appState.toggleTaskCompletion(id: task.id)
                            }) {
                                Image(systemName: isDone ? "checkmark.circle.fill" : "flag.fill")
                                    .foregroundColor(boxColor)
                            }
                            .buttonStyle(.plain)
                            .help(isDone ? "Mark task as incomplete" : "Mark task as complete")
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(task.title)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .strikethrough(isDone)
                                        .foregroundColor(isDone ? .secondary : .primary)
                                    
                                    if task.hasUnseenUpdate, let update = task.syncUpdate {
                                    
                                        TaskUpdatedBadge(update)
                                    
                                    }
                                    
                                    if isDone {
                                        Text("Completed")
                                            .font(.caption.weight(.medium))
                                            .foregroundColor(.green)
                                    }
                                }
                                
                                if let deadline = task.effectiveDeadline ?? task.extractedDeadline {
                                    Text("Due at \(formatTime(deadline)) • From: \(task.sourceEmail.senderName)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                if let update = task.deadlineUpdateNote {
                                    Label(update, systemImage: "pin")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }
                            Spacer()
                            OpenSourceButton(appState: appState, task: task, compact: true)
                        }
                        .contextMenu { OpenSourceMenuItem(appState: appState, task: task) }
                        .padding(8)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            
            // 2. All-Day Commitments for this day (Above timed timeline)
            if !dayData.allDayCommitments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("All Day")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    ForEach(dayData.allDayCommitments) { c in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: c.colorHex))
                                .frame(width: 8, height: 8)
                            
                            Text("All Day")
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            Text("• \(c.title)")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            if c.isSimulatedDemo {
                                Text("Demo")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(c.isBusy ? "Busy" : "Free")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                            
                            DayBookTag(c.calendarName, color: Color(hex: c.colorHex))
                        }
                        .padding(6)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                        .cornerRadius(4)
                    }
                }
            }
            
            // 3. Combined Timed Timeline (Sorted by start time)
            if !dayData.timedItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Schedule")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        let plannedMins = dayData.timedItems.compactMap { $0.workSession }.reduce(0) { $0 + $1.durationMinutes }
                        if plannedMins > 0 {
                            Text("\(plannedMins)m work planned")
                                .font(.system(size: 9))
                                .foregroundColor(.dbAccent)
                        }
                    }
                    
                    ForEach(dayData.timedItems) { item in
                        weekTimelineRow(for: item)
                            .sessionDraggable(item.workSession, appState: appState)
                            .sessionDropTarget(appState: appState, day: day, after: item.endTime,
                                               ownSessionId: item.workSession?.id, cornerRadius: 4)
                    }
                }
            }
            
            if dayData.deadlines.isEmpty && dayData.allDayCommitments.isEmpty && dayData.timedItems.isEmpty {
                Text("No deadlines or scheduled sessions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
        }
        .dayBookCard(padding: 16)
        .sessionDropTarget(appState: appState, day: day, cornerRadius: 12)
    }
    
    @ViewBuilder
    private func weekTimelineRow(for item: UnifiedTimelineItem) -> some View {
        switch item.kind {
        case .workSession(let s):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: s.status == .completed ? "checkmark.circle.fill" : "deskclock.fill")
                        .foregroundColor(s.status == .completed ? .green : (s.isLocked ? .orange : .dbAccent))
                        .font(.caption)
                    
                    Text("\(formatTime(s.startTime)) - \(formatTime(s.endTime)) (\(s.durationMinutes)m)")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text("• \(s.title)")
                        .font(.caption)
                        .strikethrough(s.status == .completed)
                        .foregroundColor(s.status == .completed ? .secondary : .primary)
                    
                    Spacer()
                    
                    // Overlap Badge
                    if item.isOverlapping {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                            Text("Overlap")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(.orange)
                        .help("Conflicts with: \(item.overlappingTitles.joined(separator: ", "))")
                    }
                    
                    if s.isLocked {
                        Label("Locked", systemImage: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18))
                            .foregroundColor(.orange)
                            .cornerRadius(3)
                    }
                    
                    if s.isManuallyAdjusted {
                        Text("Adjusted")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.dbNavy)
                    }
                    
                    if s.isPaidWork {
                        HStack(spacing: 2) {
                            Image(systemName: "briefcase.fill")
                                .font(.system(size: 8))
                            Text(s.paidJob ?? "Paid Work")
                        }
                        .font(.system(size: 9))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.dbAccent.opacity(0.15))
                        .foregroundColor(.dbAccent)
                        .cornerRadius(3)
                    }
                    
                    if s.isPublished {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar")
                                .font(.system(size: 8))
                            Text("Published")
                        }
                        .font(.system(size: 9))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(3)
                    }
                    
                    if s.hasUnpublishedChanges {
                        Text("Unpublished Changes")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.orange)
                    }
                    
                    if s.isCarryover || item.isCarryover {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.system(size: 8))
                            Text("Carryover")
                        }
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.dbAccent.opacity(0.18))
                        .foregroundColor(.dbAccent)
                        .cornerRadius(3)
                    }
                    
                    Button(action: {
                        appState.toggleSessionLock(id: s.id)
                    }) {
                        Image(systemName: s.isLocked ? "lock.fill" : "lock.open")
                            .font(.caption2)
                            .foregroundColor(s.isLocked ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(s.isLocked ? "Unlock session" : "Lock session")
                    
                    Button(action: {
                        appState.sessionBeingEdited = s
                    }) {
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Move or edit session")
                    
                    Button(action: {
                        appState.toggleSessionStatus(id: s.id)
                    }) {
                        Text(s.status == .completed ? "Done" : "Mark")
                            .font(.caption.weight(.medium))
                            .foregroundColor(s.status == .completed ? .green : .dbAccent)
                    }
                    .buttonStyle(.plain)
                    
                    if s.status != .completed {
                        Button(action: {
                            appState.promptNotDoneYet(for: s)
                        }) {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.caption2)
                                .foregroundColor(.dbAccent)
                        }
                        .buttonStyle(.plain)
                        .help("Not Done Yet (Carry over remaining effort)")
                    }
                    
                    Button(action: {
                        appState.removeSession(id: s.id)
                    }) {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete proposed session")
                }
                
                // Explanatory note for overlapping conflict
                if item.isOverlapping {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                        Text("Overlaps with: \(item.overlappingTitles.joined(separator: ", "))")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                    .padding(.leading, 24)
                }
            }
            .padding(6)
            .background(item.isOverlapping ? Color.orange.opacity(0.08) : Color.dbAccent.opacity(0.06))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(item.isOverlapping ? Color.orange.opacity(0.7) : (s.status == .completed ? Color.green : (s.isLocked ? Color.orange : Color.dbAccent)).opacity(0.25), lineWidth: item.isOverlapping ? 1.5 : 1)
            )
            
        case .commitment(let c):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: c.colorHex))
                        .frame(width: 8, height: 8)
                    
                    Text("\(formatTime(c.startTime)) - \(formatTime(c.endTime))")
                        .font(.caption)
                    
                    Text("• \(c.title)")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    if c.isMultiDay && !c.isAllDay {
                        Text("(Multi-day)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Overlap Badge
                    if item.isOverlapping {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                            Text("Overlap")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(.orange)
                        .help("Conflicts with: \(item.overlappingTitles.joined(separator: ", "))")
                    }
                    
                    if c.isSimulatedDemo {
                        Text("Demo")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Text(c.isBusy ? "Busy" : "Free")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    DayBookTag(c.calendarName, color: Color(hex: c.colorHex))
                }
                
                // Explanatory note for overlapping conflict
                if item.isOverlapping {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                        Text("Overlaps with: \(item.overlappingTitles.joined(separator: ", "))")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                    .padding(.leading, 16)
                }
            }
            .padding(6)
            .background(item.isOverlapping ? Color.orange.opacity(0.08) : Color(NSColor.textBackgroundColor).opacity(0.6))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(item.isOverlapping ? Color.orange.opacity(0.7) : Color.clear, lineWidth: item.isOverlapping ? 1.5 : 1)
            )
        }
    }
}
