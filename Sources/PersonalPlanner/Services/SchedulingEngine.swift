import Foundation

public extension Date {
    func isBeforeOrEqual(_ other: Date) -> Bool {
        return self.timeIntervalSinceReferenceDate <= other.timeIntervalSinceReferenceDate
    }
    func isBefore(_ other: Date) -> Bool {
        return self.timeIntervalSinceReferenceDate < other.timeIntervalSinceReferenceDate
    }
    func isAfter(_ other: Date) -> Bool {
        return self.timeIntervalSinceReferenceDate > other.timeIntervalSinceReferenceDate
    }
    func isAfterOrEqual(_ other: Date) -> Bool {
        return self.timeIntervalSinceReferenceDate >= other.timeIntervalSinceReferenceDate
    }
}

public final class RuleBasedSchedulingEngine: SchedulingEngineProtocol {
    public init() {}
    
    struct TaskSchedulingItem {
        var task: DiscoveredTask
        var remainingMinutes: Int
        var hardCutoff: Date
        var alreadyCompletedMinutes: Int
        var scheduledMinutes: Int = 0
    }
    
    public func generateSchedule(
        tasks: [DiscoveredTask],
        commitments: [CalendarCommitment],
        existingSessions: [WorkSession],
        preferences: UserPreferences,
        dateRange: ClosedRange<Date>,
        currentDate: Date = Date(),
        deletedProposedMinutesByTaskId: [String: Int] = [:],
        keepPlannedBefore: Date? = nil,
        taskDayLimits: [UUID: [Date: Int]] = [:]
    ) -> SchedulingResult {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = preferences.timeZone
        
        // 1. Demo Mode Filtering
        let targetTasks: [DiscoveredTask]
        let targetCommitments: [CalendarCommitment]
        let targetExistingSessions: [WorkSession]
        var unscheduledReports: [UnscheduledTaskReport] = []
        
        if preferences.includeDemoDataInPlan {
            targetTasks = tasks
            targetCommitments = commitments
            targetExistingSessions = existingSessions
        } else {
            targetTasks = tasks.filter { !$0.sourceEmail.isSimulatedDemo }
            targetCommitments = commitments.filter { !$0.isSimulatedDemo }
            targetExistingSessions = existingSessions.filter { !$0.isSimulatedDemo }
            
            // Log excluded demo tasks with clear explanation so user is not confused
            for demoTask in tasks.filter({ $0.sourceEmail.isSimulatedDemo && !$0.isCompleted && !$0.isDismissed }) {
                unscheduledReports.append(UnscheduledTaskReport(
                    task: demoTask,
                    totalEstimatedMinutes: demoTask.effectiveDuration,
                    alreadyCompletedMinutes: 0,
                    scheduledMinutes: 0,
                    unscheduledMinutes: demoTask.effectiveDuration,
                    primaryReason: .missingDeadline,
                    detailedExplanation: "Sample demonstration task excluded from plan. To schedule work sessions for demonstration data, enable 'Include demonstration tasks in proposed plan' in Settings."
                ))
            }
        }
        
        // 2. Separate Preserved Sessions vs Discardable Future Proposals
        // Preserved: Completed, in-progress, locked, manually adjusted, past, or already published to Apple Calendar
        // keepPlannedBefore: planned sessions of still-open tasks that start before this time stay exactly
        // where they are (today's plan is kept steady during automatic re-plans).
        let openTaskIds = Set(targetTasks.filter { !$0.isCompleted && !$0.isDismissed }.map(\.id))
        var preservedSessions: [WorkSession] = []
        for s in targetExistingSessions {
            if let keepBefore = keepPlannedBefore, s.status == .planned, let taskId = s.taskId,
               openTaskIds.contains(taskId), s.startTime < keepBefore {
                preservedSessions.append(s)
                continue
            }
            if s.status == .completed || s.status == .inProgress || s.status == .skipped || s.isLocked || s.isManuallyAdjusted || s.endTime.isBeforeOrEqual(currentDate) || s.isPublished || s.isPaidWork || s.taskId == nil {
                preservedSessions.append(s)
            }
        }
        
        // 3. Filter Incomplete, Non-Dismissed Tasks & Separate by Eligibility
        let activeTasks = targetTasks.filter { !$0.isCompleted && !$0.isDismissed }
        var ambiguousTasks: [DiscoveredTask] = []
        var candidateTasks: [DiscoveredTask] = []
        var queue: [TaskSchedulingItem] = []
        
        for task in activeTasks {
            switch task.schedulingEligibility(asOf: currentDate) {
            case .completed, .dismissed:
                continue
                
            case .needsActionClarification(let reason):
                ambiguousTasks.append(task)
                unscheduledReports.append(UnscheduledTaskReport(
                    task: task,
                    totalEstimatedMinutes: task.effectiveDuration,
                    alreadyCompletedMinutes: 0,
                    scheduledMinutes: 0,
                    unscheduledMinutes: task.effectiveDuration,
                    primaryReason: .needsActionClarification,
                    detailedExplanation: "Required action is unclear: \(reason). Clarify action in task details to schedule."
                ))
                
            case .needsPlanningTarget:
                ambiguousTasks.append(task)
                unscheduledReports.append(UnscheduledTaskReport(
                    task: task,
                    totalEstimatedMinutes: task.effectiveDuration,
                    alreadyCompletedMinutes: 0,
                    scheduledMinutes: 0,
                    unscheduledMinutes: task.effectiveDuration,
                    primaryReason: .missingDeadline,
                    detailedExplanation: "No deadline found in email. Set a user planning target in task details to schedule work sessions."
                ))
                
            case .deadlinePassed(let deadline):
                unscheduledReports.append(UnscheduledTaskReport(
                    task: task,
                    totalEstimatedMinutes: task.effectiveDuration,
                    alreadyCompletedMinutes: 0,
                    scheduledMinutes: 0,
                    unscheduledMinutes: task.effectiveDuration,
                    primaryReason: .deadlinePassed,
                    detailedExplanation: "Deadline of \(formatDateTime(deadline)) has already passed. Set a new planning target in task details to schedule work sessions."
                ))
                
            case .eligible:
                candidateTasks.append(task)
            }
        }
        
        // 4. Calculate Prior Work (Completed + Preserved Planned)
        for task in candidateTasks {
            let completedMins = preservedSessions
                .filter { $0.taskId == task.id && $0.status == .completed }
                .reduce(0) { $0 + $1.durationMinutes }
            
            // Only work still ahead (or started) counts as planned. A session that ended without being
            // checked off was missed: it isn't counted, so its work is planned again.
            let preservedPlannedMins = preservedSessions
                .filter { $0.taskId == task.id && Self.countsAsPlannedWork($0, at: currentDate) }
                .reduce(0) { $0 + $1.durationMinutes }
            
            let deletedMins = deletedProposedMinutesByTaskId[task.id.uuidString] ?? 0
            
            let remaining = max(0, task.effectiveDuration - completedMins - preservedPlannedMins - deletedMins)
            
            guard remaining > 0 else {
                // Task is already fully satisfied by completed or locked sessions
                continue
            }
            
            // Calculate effective hard cutoff with buffer and date-only deadline policy
            guard let rawDeadline = task.effectiveDeadline else {
                ambiguousTasks.append(task)
                continue
            }
            
            let cutoff = calculateHardCutoff(for: task, rawDeadline: rawDeadline, preferences: preferences)
            
            if cutoff.isBeforeOrEqual(currentDate) {
                let reason: UnscheduledReason = (rawDeadline.isBeforeOrEqual(currentDate)) ? .deadlinePassed : .insufficientTimeBeforeDeadline
                let explanation = (rawDeadline.isBeforeOrEqual(currentDate))
                    ? "Deadline of \(formatDateTime(rawDeadline)) has already passed. No work sessions can be scheduled."
                    : "Deadline buffer of \(preferences.deadlineBufferMinutes)m leaves insufficient time before deadline (\(formatDateTime(rawDeadline))). No work sessions can be scheduled."
                
                unscheduledReports.append(UnscheduledTaskReport(
                    task: task,
                    totalEstimatedMinutes: task.effectiveDuration,
                    alreadyCompletedMinutes: completedMins + preservedPlannedMins,
                    scheduledMinutes: 0,
                    unscheduledMinutes: remaining,
                    primaryReason: reason,
                    detailedExplanation: explanation
                ))
            } else {
                queue.append(TaskSchedulingItem(
                    task: task,
                    remainingMinutes: remaining,
                    hardCutoff: cutoff,
                    alreadyCompletedMinutes: completedMins + preservedPlannedMins,
                    scheduledMinutes: 0
                ))
            }
        }
        
        // 5. Prioritize Queue (explicit 3-tier ordering):
        //    Tier 0: Urgent tasks (carryover or not)
        //    Tier 1: "Not Done Yet" carryovers that are not urgent
        //    Tier 2: Ordinary flexible tasks
        // Within a tier: earliest hard cutoff, then user priority, then creation time.
        // Deadline protection is unchanged: every task still respects its own hard cutoff in slot selection.
        queue.sort { a, b in
            let tierA = Self.schedulingTier(for: a.task)
            let tierB = Self.schedulingTier(for: b.task)
            if tierA != tierB {
                return tierA < tierB
            }
            if a.hardCutoff != b.hardCutoff {
                return a.hardCutoff.isBefore(b.hardCutoff)
            }
            if a.task.userPriority != b.task.userPriority {
                return a.task.userPriority < b.task.userPriority
            }
            return a.task.createdAt.isBefore(b.task.createdAt)
        }
        
        // 5b. Slack: how much free time each task has to spare before its deadline, given how busy the
        //     schedule is and the work due before it. Within a tier, the task with the least slack gets
        //     each slot (re-judged slot by slot), so long work due soon starts before short work due later.
        let freeTime = buildFreeTimeMap(from: currentDate, through: dateRange.upperBound, preservedSessions: preservedSessions,
                                        commitments: targetCommitments, preferences: preferences, calendar: cal)
        var urgencyByTaskId: [UUID: TaskUrgency] = [:]
        for item in queue {
            let slack = Self.slack(of: item, in: queue, at: currentDate, usedOnDay: 0, freeTime: freeTime, calendar: cal)
            urgencyByTaskId[item.task.id] = TaskUrgency(
                level: TaskUrgency.classify(slack: slack, remaining: item.remainingMinutes, dailyCap: preferences.maxDailyWorkMinutes),
                slackMinutes: slack, remainingMinutes: item.remainingMinutes)
        }

        // 6. Day-by-Day Slot Generation
        var proposedSessions: [WorkSession] = []
        var usedExistingIds: Set<UUID> = Set(preservedSessions.map { $0.id })
        var currentDay = cal.startOfDay(for: currentDate)
        let endDay = cal.startOfDay(for: dateRange.upperBound)
        
        while currentDay.isBeforeOrEqual(endDay) && !queue.isEmpty {
            let weekday = cal.component(.weekday, from: currentDay)
            let hours = preferences.workingHours(for: weekday)
            
            guard hours.isWorkday else {
                currentDay = cal.date(byAdding: .day, value: 1, to: currentDay) ?? endDay.addingTimeInterval(86400)
                continue
            }
            
            guard let workStart = cal.date(bySettingHour: hours.startHour, minute: hours.startMinute, second: 0, of: currentDay),
                  let workEnd = cal.date(bySettingHour: hours.endHour, minute: hours.endMinute, second: 0, of: currentDay),
                  workStart.isBefore(workEnd) else {
                currentDay = cal.date(byAdding: .day, value: 1, to: currentDay) ?? endDay.addingTimeInterval(86400)
                continue
            }
            
            // Check daily work cap against preserved sessions on this day (missed and skipped ones took no time)
            let dayPreservedMins = preservedSessions.filter { s in
                s.startTime.isBefore(workEnd) && s.endTime.isAfter(workStart)
                    && s.status != .skipped && !Self.isMissed(s, at: currentDate)
            }.reduce(0) { $0 + $1.durationMinutes }
            
            var dayCapRemaining = max(0, preferences.maxDailyWorkMinutes - dayPreservedMins)
            let dayCapStart = dayCapRemaining
            let minQueueNeeded = queue.map { min($0.remainingMinutes, preferences.minSessionMinutes) }.min() ?? preferences.minSessionMinutes
            
            if dayCapRemaining < minQueueNeeded {
                // Daily cap already reached for this day
                currentDay = cal.date(byAdding: .day, value: 1, to: currentDay) ?? endDay.addingTimeInterval(86400)
                continue
            }
            
            // Build occupied intervals on this day
            var busyIntervals: [(start: Date, end: Date)] = []
            
            // A. Never schedule earlier than currentDate (compare against the supplied clock,
            //    not the wall clock, so carryover-to-next-workday and tests behave identically)
            if currentDate.isAfter(workStart) {
                busyIntervals.append((workStart, min(workEnd, currentDate)))
            }
            
            // B. Preserved work sessions
            for s in preservedSessions where s.status != .skipped && (s.startTime.isBefore(workEnd) && s.endTime.isAfter(workStart)) {
                busyIntervals.append((max(workStart, s.startTime), min(workEnd, s.endTime)))
            }
            
            // C. Busy calendar commitments
            let dayCommitments = targetCommitments.filter { c in
                c.endTime.isAfter(workStart) && c.startTime.isBefore(workEnd)
            }
            
            for c in dayCommitments {
                guard c.blocksScheduling else { continue } // Free events and mirrors of planner's own published sessions do not block availability
                if c.isAllDay && !preferences.allDayEventsBlockTime { continue }
                busyIntervals.append((max(workStart, c.startTime), min(workEnd, c.endTime)))
            }
            
            // D. Lunch break
            if let lunchStart = cal.date(bySettingHour: preferences.lunchStartHour, minute: 0, second: 0, of: currentDay),
               let lunchEnd = cal.date(byAdding: .minute, value: preferences.lunchDurationMinutes, to: lunchStart) {
                if lunchStart.isBefore(workEnd) && lunchEnd.isAfter(workStart) {
                    busyIntervals.append((max(workStart, lunchStart), min(workEnd, lunchEnd)))
                }
            }
            
            // Per-task limits on this day (minutes already kept here count toward them)
            var placedOnDayByTask: [UUID: Int] = [:]
            for s in preservedSessions where s.status != .completed && s.startTime.isBefore(workEnd) && s.endTime.isAfter(workStart) {
                if let id = s.taskId { placedOnDayByTask[id, default: 0] += s.durationMinutes }
            }
            func dayLimitLeft(_ taskId: UUID) -> Int {
                guard let limit = taskDayLimits[taskId]?[currentDay] else { return Int.max }
                return max(0, limit - (placedOnDayByTask[taskId] ?? 0))
            }

            // Merge busy intervals
            let mergedBusy = mergeIntervals(busyIntervals)
            
            // Find free gaps between workStart and workEnd
            let freeGaps = findFreeGaps(between: workStart, and: workEnd, busyIntervals: mergedBusy)
            
            // Fill free gaps with tasks from queue
            for gap in freeGaps {
                let currentMinNeeded = queue.map { min($0.remainingMinutes, preferences.minSessionMinutes) }.min() ?? preferences.minSessionMinutes
                guard dayCapRemaining >= currentMinNeeded && !queue.isEmpty else { break }
                
                var gapCursor = gap.start
                while gap.end.timeIntervalSince(gapCursor) >= Double(currentMinNeeded * 60)
                        && dayCapRemaining >= currentMinNeeded
                        && !queue.isEmpty {
                    
                    let gapRemainingMinutes = Int(gap.end.timeIntervalSince(gapCursor) / 60)
                    
                    // Pick the task for this slot: tier first (Urgent, then carryovers), then least slack
                    // (differences under an hour count as equal), then earliest cutoff.
                    // taskDayLimits: after you delete a session on this day, its task gets no more time here
                    // than it had left (so other work moves up instead).
                    let fitting = queue.indices.filter {
                        let need = min(queue[$0].remainingMinutes, preferences.minSessionMinutes)
                        return queue[$0].hardCutoff.isAfter(gapCursor) && need <= min(gapRemainingMinutes, dayCapRemaining)
                            && need <= dayLimitLeft(queue[$0].task.id)
                    }
                    let usedToday = dayCapStart - dayCapRemaining
                    let slackByIndex = Dictionary(uniqueKeysWithValues: fitting.map {
                        ($0, Self.slack(of: queue[$0], in: queue, at: gapCursor, usedOnDay: usedToday, freeTime: freeTime, calendar: cal))
                    })
                    let picked = fitting.min { a, b in
                        let ta = Self.schedulingTier(for: queue[a].task), tb = Self.schedulingTier(for: queue[b].task)
                        if ta != tb { return ta < tb }
                        let sa = slackByIndex[a]!, sb = slackByIndex[b]!
                        if abs(sa - sb) >= 60 { return sa < sb }
                        if queue[a].hardCutoff != queue[b].hardCutoff { return queue[a].hardCutoff < queue[b].hardCutoff }
                        return a < b
                    }
                    guard let itemIdx = picked else {
                        // Check if any expired tasks remain at the front whose cutoffs have elapsed before this window
                        if let expiredIdx = queue.firstIndex(where: { $0.hardCutoff.isBeforeOrEqual(gapCursor) }) {
                            let item = queue[expiredIdx]
                            let unscheduledMins = item.remainingMinutes
                            unscheduledReports.append(UnscheduledTaskReport(
                                task: item.task,
                                totalEstimatedMinutes: item.task.effectiveDuration,
                                alreadyCompletedMinutes: item.alreadyCompletedMinutes,
                                scheduledMinutes: item.scheduledMinutes,
                                unscheduledMinutes: unscheduledMins,
                                primaryReason: .insufficientTimeBeforeDeadline,
                                detailedExplanation: "Only \(item.scheduledMinutes)m scheduled before deadline (\(formatDateTime(item.hardCutoff))). Remaining \(unscheduledMins)m could not fit in free calendar windows."
                            ))
                            queue.remove(at: expiredIdx)
                            continue
                        }
                        // No tasks can fit in remaining gap space; break to next gap
                        break
                    }
                    
                    var item = queue[itemIdx]
                    let effectiveMinSession = min(item.remainingMinutes, preferences.minSessionMinutes)
                    
                    // Calculate allowed session minutes respecting preferred length, min length, remaining effort, daily cap, and hard cutoff
                    let minutesBeforeCutoff = Int(item.hardCutoff.timeIntervalSince(gapCursor) / 60)
                    let maxDuration = min(
                        gapRemainingMinutes,
                        preferences.defaultSessionMinutes,
                        item.remainingMinutes,
                        dayCapRemaining,
                        minutesBeforeCutoff,
                        dayLimitLeft(item.task.id)
                    )
                    
                    guard maxDuration >= effectiveMinSession else {
                        // Cannot fit minimum useful session before cutoff or gap end
                        if minutesBeforeCutoff < effectiveMinSession {
                            // Task deadline prevents scheduling here
                            let unscheduledMins = item.remainingMinutes
                            unscheduledReports.append(UnscheduledTaskReport(
                                task: item.task,
                                totalEstimatedMinutes: item.task.effectiveDuration,
                                alreadyCompletedMinutes: item.alreadyCompletedMinutes,
                                scheduledMinutes: item.scheduledMinutes,
                                unscheduledMinutes: unscheduledMins,
                                primaryReason: .insufficientTimeBeforeDeadline,
                                detailedExplanation: "Only \(item.scheduledMinutes)m scheduled before deadline (\(formatDateTime(item.hardCutoff))). Remaining \(unscheduledMins)m could not fit in free calendar windows."
                            ))
                            queue.remove(at: itemIdx)
                            continue
                        } else {
                            // Gap is too tight for this task's minimum session; break to next gap
                            break
                        }
                    }
                    
                    // Create proposed session
                    let sessionStart = gapCursor
                    let sessionEnd = gapCursor.addingTimeInterval(Double(maxDuration * 60))
                    
                    let sessionTitle = "Work Session: \(item.task.displayTitle)"
                    let notes = "Scheduled before deadline (\(formatDateTime(item.hardCutoff))). Effort: \(maxDuration)m."
                    
                    let candidateSessionId = targetExistingSessions.first(where: {
                        $0.taskId == item.task.id && !usedExistingIds.contains($0.id)
                    })?.id ?? UUID()
                    usedExistingIds.insert(candidateSessionId)
                    
                    let proposed = WorkSession(
                        id: candidateSessionId,
                        taskId: item.task.id,
                        title: sessionTitle,
                        startTime: sessionStart,
                        endTime: sessionEnd,
                        status: .planned,
                        notes: notes,
                        isLocked: false,
                        isManuallyAdjusted: false,
                        isSimulatedDemo: item.task.sourceEmail.isSimulatedDemo,
                        isCarryover: item.task.isCarryover
                    )
                    proposedSessions.append(proposed)
                    
                    // Update counters
                    placedOnDayByTask[item.task.id, default: 0] += maxDuration
                    item.remainingMinutes -= maxDuration
                    item.scheduledMinutes += maxDuration
                    dayCapRemaining -= maxDuration
                    
                    // Advance gap cursor with break
                    gapCursor = sessionEnd.addingTimeInterval(Double(preferences.breakMinutes * 60))
                    
                    if item.remainingMinutes <= 0 {
                        queue.remove(at: itemIdx)
                    } else {
                        queue[itemIdx] = item
                    }
                }
            }
            
            currentDay = cal.date(byAdding: .day, value: 1, to: currentDay) ?? endDay.addingTimeInterval(86400)
        }
        
        // 7. Report any remaining tasks that could not be fully scheduled
        for item in queue where item.remainingMinutes > 0 {
            let reason: UnscheduledReason
            let explanation: String
            
            if item.hardCutoff.isBeforeOrEqual(endDay) {
                reason = .insufficientTimeBeforeDeadline
                explanation = "Only \(item.scheduledMinutes)m scheduled before deadline (\(formatDateTime(item.hardCutoff))). Remaining \(item.remainingMinutes)m could not fit in available calendar gaps."
            } else {
                reason = .calendarFullyBooked
                explanation = "\(item.remainingMinutes)m unscheduled: calendar commitments and daily planned work limits occupied available working hours."
            }
            
            unscheduledReports.append(UnscheduledTaskReport(
                task: item.task,
                totalEstimatedMinutes: item.task.effectiveDuration,
                alreadyCompletedMinutes: item.alreadyCompletedMinutes,
                scheduledMinutes: item.scheduledMinutes,
                unscheduledMinutes: item.remainingMinutes,
                primaryReason: reason,
                detailedExplanation: explanation
            ))
        }
        
        // 8. Add any ambiguous tasks to reports if not already reported
        for ambig in ambiguousTasks where !unscheduledReports.contains(where: { $0.task.id == ambig.id }) {
            unscheduledReports.append(UnscheduledTaskReport(
                task: ambig,
                totalEstimatedMinutes: ambig.effectiveDuration,
                alreadyCompletedMinutes: 0,
                scheduledMinutes: 0,
                unscheduledMinutes: ambig.effectiveDuration,
                primaryReason: .missingDeadline,
                detailedExplanation: "Task has no confirmed deadline or requires user clarification. Deadlines are never invented."
            ))
        }
        
        // Combine all sessions (preserved + proposed), sorted chronologically
        let combinedSessions = (preservedSessions + proposedSessions).sorted { $0.startTime < $1.startTime }
        
        // Calculate statistics
        let evaluatedCount = targetTasks.filter { !$0.isDismissed }.count
        let unscheduledCount = unscheduledReports.filter { $0.unscheduledMinutes > 0 }.count
        let fullyScheduledCount = max(0, evaluatedCount - unscheduledCount)
        let partiallyScheduledCount = unscheduledReports.filter { $0.scheduledMinutes > 0 && $0.unscheduledMinutes > 0 }.count
        let totalPlannedMins = proposedSessions.reduce(0) { $0 + $1.durationMinutes }
        
        let stats = SchedulingStats(
            tasksEvaluated: evaluatedCount,
            fullyScheduledCount: fullyScheduledCount,
            partiallyScheduledCount: partiallyScheduledCount,
            unscheduledCount: unscheduledCount,
            totalPlannedMinutes: totalPlannedMins,
            replannedDate: Date()
        )
        
        var result = SchedulingResult(
            proposedSessions: proposedSessions,
            preservedSessions: preservedSessions,
            allSessions: combinedSessions,
            unscheduledReports: unscheduledReports,
            ambiguousTasks: ambiguousTasks,
            stats: stats
        )
        result.urgencyByTaskId = urgencyByTaskId
        return result
    }

    /// Free working time per day from `from` through `through`: working hours minus time already past,
    /// kept sessions, busy events and lunch, with each day's remaining work cap.
    func buildFreeTimeMap(from: Date, through: Date, preservedSessions: [WorkSession], commitments: [CalendarCommitment],
                          preferences: UserPreferences, calendar cal: Calendar) -> FreeTimeMap {
        var days: [FreeTimeMap.Day] = []
        var day = cal.startOfDay(for: from)
        let last = cal.startOfDay(for: through)
        while day <= last {
            defer { day = cal.date(byAdding: .day, value: 1, to: day) ?? last.addingTimeInterval(86400) }
            let hours = preferences.workingHours(for: cal.component(.weekday, from: day))
            guard hours.isWorkday,
                  let workStart = cal.date(bySettingHour: hours.startHour, minute: hours.startMinute, second: 0, of: day),
                  let workEnd = cal.date(bySettingHour: hours.endHour, minute: hours.endMinute, second: 0, of: day),
                  workStart < workEnd else { continue }
            var busy: [(start: Date, end: Date)] = []
            if from > workStart { busy.append((workStart, min(workEnd, from))) }
            let kept = preservedSessions.filter { $0.status != .skipped && $0.startTime < workEnd && $0.endTime > workStart }
            for s in kept { busy.append((max(workStart, s.startTime), min(workEnd, s.endTime))) }
            for c in commitments where c.endTime > workStart && c.startTime < workEnd && c.blocksScheduling {
                if c.isAllDay && !preferences.allDayEventsBlockTime { continue }
                busy.append((max(workStart, c.startTime), min(workEnd, c.endTime)))
            }
            if let lunchStart = cal.date(bySettingHour: preferences.lunchStartHour, minute: 0, second: 0, of: day),
               let lunchEnd = cal.date(byAdding: .minute, value: preferences.lunchDurationMinutes, to: lunchStart),
               lunchStart < workEnd && lunchEnd > workStart {
                busy.append((max(workStart, lunchStart), min(workEnd, lunchEnd)))
            }
            let gaps = findFreeGaps(between: workStart, and: workEnd, busyIntervals: mergeIntervals(busy))
            let keptMinutes = kept.reduce(0) { $0 + $1.durationMinutes }
            days.append(FreeTimeMap.Day(start: day, gaps: gaps, capMinutes: max(0, preferences.maxDailyWorkMinutes - keptMinutes)))
        }
        let session = Double(max(15, preferences.defaultSessionMinutes))
        return FreeTimeMap(days: days, workShare: session / (session + Double(max(0, preferences.breakMinutes))))
    }
    
    // MARK: - Helper Methods

    /// Kept work that still covers part of a task: in progress, or planned and not yet over.
    /// Completed work is counted separately; skipped and missed (ended, never checked off) sessions count for nothing.
    public static func countsAsPlannedWork(_ s: WorkSession, at now: Date) -> Bool {
        s.status == .inProgress || (s.status == .planned && s.endTime > now)
    }

    /// A planned task session that ended without being checked off.
    public static func isMissed(_ s: WorkSession, at now: Date) -> Bool {
        s.status == .planned && s.taskId != nil && !s.isPaidWork && s.endTime <= now
    }

    /// 0 = Urgent, 1 = "Not Done Yet" carryover, 2 = ordinary.
    public static func schedulingTier(for task: DiscoveredTask) -> Int {
        if task.userPriority == .urgent { return 0 }
        if task.isCarryover { return 1 }
        return 2
    }

    private func calculateHardCutoff(for task: DiscoveredTask, rawDeadline: Date, preferences: UserPreferences) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = preferences.timeZone
        var effectiveDeadline = rawDeadline
        
        // 1. If task has a user-confirmed planning target, respect the target as the active deadline
        if let target = task.planningTargetDate {
            let hour = cal.component(.hour, from: target)
            let minute = cal.component(.minute, from: target)
            // If target date was set without a specific time (midnight 00:00:00), apply date-only policy
            if hour == 0 && minute == 0 {
                let dayStart = cal.startOfDay(for: target)
                let weekday = cal.component(.weekday, from: target)
                let hours = preferences.workingHours(for: weekday)
                switch preferences.dateOnlyDeadlinePolicy {
                case .endOfWorkday:
                    effectiveDeadline = cal.date(bySettingHour: hours.endHour, minute: hours.endMinute, second: 0, of: dayStart) ?? target
                case .endOfDay:
                    effectiveDeadline = cal.date(bySettingHour: 23, minute: 59, second: 59, of: dayStart) ?? target
                case .startOfWorkday:
                    effectiveDeadline = cal.date(bySettingHour: hours.startHour, minute: hours.startMinute, second: 0, of: dayStart) ?? target
                }
            } else {
                effectiveDeadline = target
            }
        }
        // 2. If task has a user-overridden deadline, use the overridden date
        else if let overridden = task.userOverriddenDeadline {
            effectiveDeadline = overridden
        }
        // 3. Otherwise, if task has an extracted date-only deadline, apply policy in preferences.timeZone
        else if task.isDateOnlyDeadline || task.originalDeadlineProvenance == .dateOnly || task.dateOnlyDeadlineString != nil {
            if let dateStr = task.dateOnlyDeadlineString {
                let parts = dateStr.split(separator: "-").compactMap { Int($0) }
                if parts.count == 3 {
                    var comp = DateComponents()
                    comp.year = parts[0]
                    comp.month = parts[1]
                    comp.day = parts[2]
                    comp.timeZone = preferences.timeZone
                    
                    if let dayDate = cal.date(from: comp) {
                        let weekday = cal.component(.weekday, from: dayDate)
                        let hours = preferences.workingHours(for: weekday)
                        
                        switch preferences.dateOnlyDeadlinePolicy {
                        case .endOfWorkday:
                            comp.hour = hours.endHour
                            comp.minute = hours.endMinute
                            comp.second = 0
                        case .endOfDay:
                            comp.hour = 23
                            comp.minute = 59
                            comp.second = 59
                        case .startOfWorkday:
                            comp.hour = hours.startHour
                            comp.minute = hours.startMinute
                            comp.second = 0
                        }
                        effectiveDeadline = cal.date(from: comp) ?? rawDeadline
                    }
                }
            } else {
                let dayStart = cal.startOfDay(for: rawDeadline)
                let weekday = cal.component(.weekday, from: rawDeadline)
                let hours = preferences.workingHours(for: weekday)
                
                switch preferences.dateOnlyDeadlinePolicy {
                case .endOfWorkday:
                    effectiveDeadline = cal.date(bySettingHour: hours.endHour, minute: hours.endMinute, second: 0, of: dayStart) ?? rawDeadline
                case .endOfDay:
                    effectiveDeadline = cal.date(bySettingHour: 23, minute: 59, second: 59, of: dayStart) ?? rawDeadline
                case .startOfWorkday:
                    effectiveDeadline = cal.date(bySettingHour: hours.startHour, minute: hours.startMinute, second: 0, of: dayStart) ?? rawDeadline
                }
            }
        }
        
        // Apply buffer before deadline
        let bufferSeconds = Double(max(0, preferences.deadlineBufferMinutes) * 60)
        return effectiveDeadline.addingTimeInterval(-bufferSeconds)
    }
    
    private func mergeIntervals(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start.isBefore($1.start) }
        var merged: [(start: Date, end: Date)] = [sorted[0]]
        
        for current in sorted.dropFirst() {
            guard var last = merged.last else { continue }
            if current.start.isBeforeOrEqual(last.end) {
                last.end = max(last.end, current.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(current)
            }
        }
        return merged
    }
    
    private func findFreeGaps(between start: Date, and end: Date, busyIntervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        var gaps: [(start: Date, end: Date)] = []
        var cursor = start
        
        for busy in busyIntervals {
            let bStart = max(start, busy.start)
            let bEnd = min(end, busy.end)
            
            if bStart.isAfter(cursor) {
                gaps.append((cursor, bStart))
            }
            cursor = max(cursor, bEnd)
        }
        
        if cursor.isBefore(end) {
            gaps.append((cursor, end))
        }
        return gaps
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}
