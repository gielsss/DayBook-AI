import SwiftUI

public struct TodayView: View {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private var todayDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: Date())
    }
    
    private var todayCommitments: [CalendarCommitment] {
        let dayData = UnifiedTimelineEngine.buildDayData(
            day: Date(),
            tasks: appState.tasks,
            workSessions: appState.workSessions,
            commitments: appState.commitments,
            timeZone: appState.preferences.timeZone
        )
        return dayData.allDayCommitments + dayData.timedItems.compactMap { $0.commitment }
    }
    
    private var todaySessions: [WorkSession] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return [] }
        return appState.workSessions.filter {
            $0.status != .skipped && $0.startTime >= today && $0.startTime < tomorrow
        }.sorted { $0.startTime < $1.startTime }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                DayBookPageHeader("Today", subtitle: "\(DayBookGreeting.current()). Here's your day, written down.") {
                    HStack(spacing: 8) {
                        if appState.isScanningEmails && !appState.isSyncingAll {
                            ProgressView().controlSize(.small)
                            Button("Cancel Scan", role: .cancel) {
                                appState.cancelActiveScan()
                            }
                        } else {
                            // Click: sync everything. Arrow: email-only scans.
                            Menu {
                                Button("Scan Email Only (Last 3 Days)") {
                                    Task { await appState.scanEmailsFromLast3Days() }
                                }
                                Button("Test Scan (5 Emails)") {
                                    Task { await appState.testScanFiveEmails() }
                                }
                            } label: {
                                Label(appState.isSyncingAll ? "Syncing…" : "Sync Everything", systemImage: "arrow.triangle.2.circlepath")
                            } primaryAction: {
                                Task { await appState.syncEverything() }
                            }
                            .fixedSize()
                            .disabled(appState.isAnySyncRunning)
                            .help("Sync Apple Calendar, Canvas, Gradescope and email now")
                        }
                        
                        Button {
                            appState.showCreateActivitySheet = true
                        } label: {
                            Label("Add Activity", systemImage: "plus")
                        }
                    }
                    .controlSize(.regular)
                }
                
                SyncStatusView(appState: appState)

                // Sessions that ended without being checked off.
                CatchUpCard(appState: appState)

                // Finished tasks: how long they really took.
                TimeQuestionCard(appState: appState)
                
                // Fallback & Live Scan Status Indicators
                if appState.isScanningEmails || appState.lastScanDate != nil || !appState.failedEmailRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Last check: **\(appState.lastCompletedCheckText)**")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("Coverage: **Last 3 days (72h)**")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if let active = appState.currentActiveProcessingModel {
                                Text("Model: **\(active)**")
                                    .font(.caption2)
                                if active != appState.ollamaModel {
                                    Text("(Fallback)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        
                        HStack(spacing: 8) {
                            Text("New: **\(appState.scanNewCount)**")
                                .font(.caption2)
                                .foregroundColor(.dbAccent)
                                .help("New emails discovered in inbox from last 3 days (72h)")
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("Analyzed: **\(appState.scanProcessedCount)**")
                                .font(.caption2)
                                .foregroundColor(.green)
                                .help("Emails analyzed with Ollama")
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("Cached: **\(appState.scanCachedCount)**")
                                .font(.caption2)
                                .foregroundColor(.dbNavy)
                                .help("Emails loaded from local cache with zero API calls")
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("Pending: **\(appState.scanPendingCount)**")
                                .font(.caption2)
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
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                                .help("Click to view failure details and retry")
                            }
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
                }
                
                
                
                if let scanProgress = appState.scanProgressText {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(scanProgress)
                            .font(.caption)
                            .foregroundColor(.dbAccent)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dbAccent.opacity(0.1))
                    .cornerRadius(6)
                }
                
                if let scanError = appState.lastScanError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(scanError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                }
                
                if let scanSummary = appState.lastScanSuccessSummary {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(scanSummary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(6)
                }
                
                // Stat cards
                HStack(spacing: 12) {
                    statCard(
                        title: "Planned Work",
                        count: "\(todaySessions.filter { $0.status != .completed }.count)",
                        subtitle: "\(todaySessions.reduce(0) { $0 + $1.durationMinutes }) minutes today",
                        color: .dbAccent,
                        systemImage: "deskclock"
                    )
                    
                    statCard(
                        title: "Events",
                        count: "\(todayCommitments.count)",
                        subtitle: "From Apple Calendar",
                        color: .dbNavy,
                        systemImage: "calendar"
                    )
                    
                    statCard(
                        title: "Open Tasks",
                        count: "\(appState.tasks.filter { !$0.isCompleted }.count)",
                        subtitle: "\(appState.tasks.filter { $0.status == .needsClarification }.count) need clarification",
                        color: .secondary,
                        systemImage: "checklist"
                    )
                }
                
                // Live Gmail Connection Confirmation (5 Recent Email Subjects)
                if appState.isGmailAuthenticated {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("Live Gmail Connected • 5 Recent Email Subjects")
                                .font(.headline)
                            Spacer()
                            if appState.isFetchingRecentEmails {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Button(action: {
                                    Task {
                                        await appState.fetchRecentGmailEmails()
                                    }
                                }) {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                        .font(.caption2)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        
                        if appState.recentGmailEmails.isEmpty {
                            Text("Fetching recent email subjects from your inbox...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(Array(appState.recentGmailEmails.enumerated()), id: \.element.id) { idx, email in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(idx + 1).")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .frame(width: 18, alignment: .trailing)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(email.subject)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .lineLimit(1)
                                            
                                            HStack {
                                                Text("From: \(email.sender)")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                                Spacer()
                                                Text(formatTime(email.date))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background(Color.dbSurface)
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
                }
                
                // Timeline comparison: Planned Work Sessions vs Calendar Commitments
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Schedule")
                            .font(.title2.weight(.semibold))
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            if let result = appState.lastSchedulingResult, (!result.unscheduledReports.isEmpty || !result.ambiguousTasks.isEmpty) {
                                Button {
                                    appState.showUnscheduledSheet = true
                                } label: {
                                    Label("\(result.unscheduledReports.count) Unscheduled", systemImage: "exclamationmark.triangle")
                                }
                                .help("Review tasks that couldn't be scheduled")
                            }
                            
                            if !appState.externalDiscrepancies.isEmpty {
                                Button {
                                    appState.showDiscrepancySheet = true
                                } label: {
                                    Label("\(appState.externalDiscrepancies.count) Calendar Changes", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                                }
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
                                    Label("Plan My Day", systemImage: "wand.and.stars")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.isGeneratingSchedule)
                            .help("Generate a proposed plan around your calendar")
                            
                            Menu {
                                Button {
                                    appState.showEndOfDayReviewSheet = true
                                } label: {
                                    Label("End-of-Day Review…", systemImage: "sunset")
                                }
                                if appState.calendarAuthorizationStatus == .authorized {
                                    Button {
                                        Task { await appState.refreshCalendarCommitments(isAutomatic: false) }
                                    } label: {
                                        Label("Refresh Calendar", systemImage: "arrow.clockwise")
                                    }
                                    .disabled(appState.isRefreshingCalendar)
                                } else if appState.calendarAuthorizationStatus == .notDetermined {
                                    Button {
                                        Task { await appState.requestCalendarAccess() }
                                    } label: {
                                        Label("Connect Apple Calendar", systemImage: "calendar.badge.plus")
                                    }
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
                    
                    // Task Scheduling Analysis Breakdown (Always visible after generating plan)
                    if let result = appState.lastSchedulingResult {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Task Scheduling Analysis")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                Spacer()
                                Text("\(result.proposedSessions.count) session\(result.proposedSessions.count == 1 ? "" : "s") planned • \(result.unscheduledReports.count) unscheduled")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            let activeTasks = appState.tasks.filter { !$0.isDismissed && !$0.isCompleted }
                            if activeTasks.isEmpty {
                                Text("No active tasks to schedule.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(activeTasks) { task in
                                        let taskSessions = appState.workSessions.filter { $0.taskId == task.id }
                                        let report = result.unscheduledReports.first(where: { $0.task.id == task.id })
                                        
                                        HStack(alignment: .top, spacing: 8) {
                                            if !taskSessions.isEmpty {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                    .font(.caption)
                                                    .padding(.top, 2)
                                            } else {
                                                switch task.schedulingEligibility {
                                                case .deadlinePassed:
                                                    Image(systemName: "exclamationmark.octagon.fill")
                                                        .foregroundColor(.red)
                                                        .font(.caption)
                                                        .padding(.top, 2)
                                                case .needsPlanningTarget:
                                                    Image(systemName: "calendar.badge.plus")
                                                        .foregroundColor(.orange)
                                                        .font(.caption)
                                                        .padding(.top, 2)
                                                case .needsActionClarification:
                                                    Image(systemName: "questionmark.circle.fill")
                                                        .foregroundColor(.orange)
                                                        .font(.caption)
                                                        .padding(.top, 2)
                                                case .eligible, .completed, .dismissed:
                                                    Image(systemName: "exclamationmark.triangle.fill")
                                                        .foregroundColor(.orange)
                                                        .font(.caption)
                                                        .padding(.top, 2)
                                                }
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text(task.displayTitle)
                                                        .font(.caption)
                                                        .fontWeight(.semibold)
                                                    
                                                    switch task.schedulingEligibility {
                                                    case .deadlinePassed:
                                                        Text("Overdue")
                                                            .font(.caption.weight(.medium))
                                                            .foregroundColor(.red)
                                                    case .needsPlanningTarget:
                                                        Text("Needs Target")
                                                            .font(.caption.weight(.medium))
                                                            .foregroundColor(.orange)
                                                    case .needsActionClarification:
                                                        Text("Needs Clarification")
                                                            .font(.caption.weight(.medium))
                                                            .foregroundColor(.orange)
                                                    case .eligible:
                                                        if task.hasPlanningTarget {
                                                            Text("Target Set")
                                                                .font(.caption.weight(.medium))
                                                                .foregroundColor(.dbNavy)
                                                        }
                                                        if let urgency = result.urgencyByTaskId[task.id] {
                                                            UrgencyTag(urgency)
                                                        }
                                                    case .completed, .dismissed:
                                                        EmptyView()
                                                    }
                                                }
                                                
                                                if !taskSessions.isEmpty {
                                                    Text("\(taskSessions.count) session\(taskSessions.count == 1 ? "" : "s") scheduled (\(taskSessions.reduce(0) { $0 + $1.durationMinutes })m total planned)")
                                                        .font(.caption2)
                                                        .foregroundColor(.green)
                                                } else if let rep = report {
                                                    Text(rep.detailedExplanation)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                } else if task.schedulingEligibility == .needsPlanningTarget {
                                                    Text("No deadline in email. Set a user planning target in task details to schedule work.")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                } else if task.isActionUnclear {
                                                    Text("Task required action is unclear. Clarify scope in task details.")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            Button("Inspect") {
                                                appState.selectedTaskId = task.id
                                                appState.selectedTab = .tasks
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.mini)
                                        }
                                        .padding(8)
                                        .background(Color.dbSurface)
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.06))
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
                    
                    // 1. Deadlines due today (sorted by due time)
                    let todayData = UnifiedTimelineEngine.buildDayData(
                        day: Date(),
                        tasks: appState.tasks,
                        workSessions: appState.workSessions,
                        commitments: appState.commitments,
                        timeZone: appState.preferences.timeZone
                    )
                    
                    if !todayData.deadlines.isEmpty {
                        let hasIncomplete = todayData.deadlines.contains(where: { !$0.isCompleted })
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Due Today")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                            
                            ForEach(todayData.deadlines) { task in
                                let isDone = task.isCompleted
                                let boxColor: Color = isDone ? .green : .red
                                
                                HStack(spacing: 10) {
                                    Button(action: {
                                        appState.toggleTaskCompletion(id: task.id)
                                    }) {
                                        Image(systemName: isDone ? "checkmark.circle.fill" : "flag.fill")
                                            .foregroundColor(boxColor)
                                            .font(.body)
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
                                .padding(10)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    
                    // 2. All-day events above timed timeline
                    if !todayData.allDayCommitments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("All Day")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                            
                            ForEach(todayData.allDayCommitments) { c in
                                HStack(spacing: 12) {
                                    Text("All Day")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .frame(width: 80, alignment: .trailing)
                                    
                                    Rectangle()
                                        .frame(width: 4)
                                        .foregroundColor(Color(hex: c.colorHex))
                                        .cornerRadius(2)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(c.title)
                                                .font(.headline)
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
                                        if let loc = c.location, !loc.isEmpty {
                                            Label(loc, systemImage: "location")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.dbSurface)
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                    
                    // 3. Combined Chronological Timed Timeline
                    if todayData.timedItems.isEmpty {
                        if todayData.deadlines.isEmpty && todayData.allDayCommitments.isEmpty {
                            Text("No events or work sessions scheduled for today.")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    } else {
                        let today = Calendar.current.startOfDay(for: Date())
                        VStack(spacing: 10) {
                            ForEach(todayData.timedItems, id: \.id) { item in
                                timelineRow(for: item)
                                    .sessionDraggable(item.workSession, appState: appState)
                                    .sessionDropTarget(appState: appState, day: today, after: item.endTime,
                                                       ownSessionId: item.workSession?.id)
                            }
                        }
                        .sessionDropTarget(appState: appState, day: today)
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
        .sheet(isPresented: $appState.showFailedEmailsSheet) {
            FailedEmailsSheet(appState: appState)
        }
        .sheet(item: $appState.sessionForCarryover) { session in
            CarryoverConfirmationSheet(appState: appState, session: session)
        }
        .sheet(isPresented: $appState.showEndOfDayReviewSheet) {
            EndOfDayReviewSheet(appState: appState)
        }
    }
    
    private func statCard(title: String, count: String, subtitle: String, color: Color, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                DayBookIconTile(systemImage: systemImage, color: color == .secondary ? Color.dbInk.opacity(0.55) : color, size: 24)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dbInk)
            }
            Text(count)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color.dbInk)
                .monospacedDigit()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dayBookCard(tint: color)
    }
    
    @ViewBuilder
    private func timelineRow(for item: UnifiedTimelineItem) -> some View {
        switch item.kind {
        case .commitment(let c):
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    if c.isAllDay {
                        Text("All Day")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    } else {
                        Text(formatTime(c.startTime))
                            .font(.headline)
                        Text(formatTime(c.endTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 80, alignment: .trailing)
                
                Rectangle()
                    .frame(width: 4)
                    .foregroundColor(Color(hex: c.colorHex))
                    .cornerRadius(2)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(c.title)
                            .font(.headline)
                        Spacer()
                        
                        // Overlap Badge
                        if item.isOverlapping {
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 8))
                                Text("Overlap")
                            }
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                            .help("Overlaps with: \(item.overlappingTitles.joined(separator: ", "))")
                        }
                        
                        if c.isSimulatedDemo {
                            Text("Demo")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                        
                        if c.isAllDay {
                            Text("All-Day")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                        
                        Text(c.isBusy ? "Busy" : "Free")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                        
                        DayBookTag(c.calendarName, color: Color(hex: c.colorHex))
                    }
                    if let loc = c.location, !loc.isEmpty {
                        Label(loc, systemImage: "location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if item.isOverlapping {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("Overlaps with: \(item.overlappingTitles.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(12)
                .background(item.isOverlapping ? Color.orange.opacity(0.08) : Color.dbSurface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(item.isOverlapping ? Color.orange.opacity(0.8) : Color.clear, lineWidth: item.isOverlapping ? 1.5 : 1)
                )
            }
            
        case .workSession(let s):
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatTime(s.startTime))
                        .font(.headline)
                    Text(formatTime(s.endTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(s.durationMinutes)m")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 80, alignment: .trailing)
                
                Rectangle()
                    .frame(width: 4)
                    .foregroundColor(s.status == .completed ? .green : (s.isLocked ? .orange : .dbAccent))
                    .cornerRadius(2)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(s.title)
                            .font(.headline)
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
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                            .help("Overlaps with: \(item.overlappingTitles.joined(separator: ", "))")
                        }
                        
                        if s.isLocked {
                            Label("Locked", systemImage: "lock.fill")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.18))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                        
                        if s.isManuallyAdjusted {
                            Text("Adjusted")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.dbNavy)
                        }
                        
                        if s.isPublished {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 9))
                                Text("Published")
                            }
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                        }
                        
                        if s.hasUnpublishedChanges {
                            Text("Unpublished Changes")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.orange)
                        }
                        
                        if s.isPaidWork {
                            HStack(spacing: 4) {
                                Image(systemName: "briefcase.fill")
                                Text(s.paidJob ?? "Paid Work")
                            }
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.dbAccent.opacity(0.15))
                            .foregroundColor(.dbAccent)
                            .cornerRadius(4)
                        }
                        
                        if s.isSimulatedDemo {
                            Text("Demo")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                        
                        if s.isCarryover || item.isCarryover {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.uturn.forward")
                                    .font(.system(size: 8))
                                Text("Carryover")
                            }
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.dbAccent.opacity(0.18))
                            .foregroundColor(.dbAccent)
                            .cornerRadius(4)
                        }
                        
                        Text(s.status == .completed ? "Completed" : "Proposed Session")
                            .font(.caption.weight(.medium))
                            .foregroundColor(s.status == .completed ? .green : .dbAccent)
                    }
                    
                    if let notes = s.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if item.isOverlapping {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("Overlaps with: \(item.overlappingTitles.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        .padding(.top, 2)
                    }
                    
                    // Session action controls: Mark Complete, Lock, Move/Edit, Remove
                    HStack(spacing: 8) {
                        Button(action: {
                            appState.toggleSessionStatus(id: s.id)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: s.status == .completed ? "checkmark.circle.fill" : "circle")
                                Text(s.status == .completed ? "Mark Incomplete" : "Mark Completed")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button(action: {
                            appState.toggleSessionLock(id: s.id)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: s.isLocked ? "lock.open" : "lock")
                                Text(s.isLocked ? "Unlock" : "Lock")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        if s.status != .completed {
                            Button(action: {
                                appState.promptNotDoneYet(for: s)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.uturn.forward")
                                    Text("Not Done Yet")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.dbAccent)
                            .controlSize(.small)
                            .help("Carry over remaining effort to the next available working slot")
                        }
                        
                        Button(action: {
                            appState.sessionBeingEdited = s
                        }) {
                            Label("Move / Edit", systemImage: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button(action: {
                            appState.removeSession(id: s.id)
                        }) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Delete proposed session")
                    }
                    .padding(.top, 2)
                }
                .padding(12)
                .background(item.isOverlapping ? Color.orange.opacity(0.08) : Color.dbSurface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(item.isOverlapping ? Color.orange.opacity(0.8) : (s.status == .completed ? Color.green : (s.isLocked ? Color.orange : Color.dbAccent)).opacity(0.3), lineWidth: item.isOverlapping ? 1.5 : 1)
                )
            }
        }
    }
}
