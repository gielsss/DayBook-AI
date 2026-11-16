import Foundation

/// Nothing open quietly drops out of the plan:
/// - A session that ended without being checked off is "missed". It doesn't count as work, so the
///   planner plans that work again; the Catch Up card on Today asks whether it got done.
/// - The Unplanned list on Week shows every open task with nothing planned ahead, why, and a fix.
extension AppState {
    // MARK: - Missed sessions (Today → Catch Up)

    /// Open tasks' sessions that ended without being checked off, oldest first.
    public func missedSessions(now: Date = Date()) -> [WorkSession] {
        let open = Set(tasks.filter { !$0.isCompleted && !$0.isDismissed
            && (preferences.includeDemoDataInPlan || !$0.sourceEmail.isSimulatedDemo) }.map(\.id))
        return workSessions
            .filter { RuleBasedSchedulingEngine.isMissed($0, at: now) && open.contains($0.taskId!) }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Re-plans (placing only the missing work, nothing else moves) when a session has newly been missed.
    /// Runs at launch and every 5 minutes with the automatic-sync timer.
    func replanIfSessionsWereMissed(now: Date = Date()) {
        let missed = Set(missedSessions(now: now).map(\.id))
        defer { knownMissedSessionIds = missed }
        guard !missed.subtracting(knownMissedSessionIds).isEmpty, !isAnySyncRunning else { return }
        generateProposedPlan(isAutomatic: true, keepExistingPlan: true)
    }

    /// Done / Not Done Yet for a missed session (Catch Up card and the evening check-in).
    /// Done: the session counts as finished work; the task is completed when that covers all of it.
    /// Not done: the session is kept as skipped and its work is planned again with carryover priority,
    /// without changing the task's estimate or moving other sessions.
    public func answerMissedSession(id: UUID, done: Bool, now: Date = Date()) {
        guard let idx = workSessions.firstIndex(where: { $0.id == id }),
              workSessions[idx].status == .planned, let taskId = workSessions[idx].taskId else { return }
        if done {
            workSessions[idx].status = .completed
            completeTaskIfFullyDone(taskId, now: now)
            recalculateSchedule()
        } else {
            workSessions[idx].status = .skipped
            if let tIdx = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[tIdx].isCarryover = true
                tasks[tIdx].updatedAt = now
            }
            generateProposedPlan(isAutomatic: true, keepExistingPlan: true)
        }
        knownMissedSessionIds.remove(id)
        saveDatabase()
    }

    /// "None of these got done" / "All done".
    public func answerAllMissedSessions(done: Bool, now: Date = Date()) {
        let ids = missedSessions(now: now).map(\.id)
        guard !ids.isEmpty else { return }
        for id in ids {
            guard let idx = workSessions.firstIndex(where: { $0.id == id }), let taskId = workSessions[idx].taskId else { continue }
            workSessions[idx].status = done ? .completed : .skipped
            if done {
                completeTaskIfFullyDone(taskId, now: now)
            } else if let tIdx = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[tIdx].isCarryover = true
                tasks[tIdx].updatedAt = now
            }
        }
        knownMissedSessionIds.subtract(ids)
        if done { recalculateSchedule() } else { generateProposedPlan(isAutomatic: true, keepExistingPlan: true) }
        saveDatabase()
    }

    /// Completes a task once its finished sessions cover its estimate and nothing else is missed.
    private func completeTaskIfFullyDone(_ taskId: UUID, now: Date) {
        guard let tIdx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        let done = workSessions.filter { $0.taskId == taskId && $0.status == .completed }.reduce(0) { $0 + $1.durationMinutes }
        let stillMissed = workSessions.contains { $0.taskId == taskId && RuleBasedSchedulingEngine.isMissed($0, at: now) }
        guard done >= tasks[tIdx].effectiveDuration, !stillMissed else { return }
        tasks[tIdx].status = .completed
        tasks[tIdx].isCarryover = false
        tasks[tIdx].updatedAt = now
        // Planned time still ahead is no longer needed.
        workSessions.removeAll { $0.taskId == taskId && $0.status == .planned && $0.endTime > now
            && !$0.isLocked && !$0.isManuallyAdjusted && !$0.isPublished }
        recordActualTime(taskId: taskId, now: now)
    }

    // MARK: - Unplanned tasks (Week)

    /// Every open task with no planned work ahead, with the reason and what to do about it.
    public func unplannedTasks(now: Date = Date()) -> [UnplannedTask] {
        let reports = Dictionary((lastSchedulingResult?.unscheduledReports ?? []).map { ($0.task.id, $0) },
                                 uniquingKeysWith: { a, _ in a })
        return tasks.compactMap { task -> UnplannedTask? in
            guard !task.isCompleted, !task.isDismissed,
                  preferences.includeDemoDataInPlan || !task.sourceEmail.isSimulatedDemo else { return nil }
            let sessions = workSessions.filter { $0.taskId == task.id }
            guard !sessions.contains(where: { RuleBasedSchedulingEngine.countsAsPlannedWork($0, at: now) }) else { return nil }
            let missed = sessions.filter { RuleBasedSchedulingEngine.isMissed($0, at: now) }.count
            let done = sessions.filter { $0.status == .completed }.reduce(0) { $0 + $1.durationMinutes }
            let reason: UnplannedTask.Reason
            switch task.schedulingEligibility(asOf: now) {
            case .deadlinePassed(let deadline):
                reason = .deadlinePassed(deadline)
            case .needsPlanningTarget:
                reason = .needsTarget
            case .needsActionClarification:
                reason = .needsClarification
            case .completed, .dismissed:
                return nil
            case .eligible:
                if missed > 0 {
                    reason = .missedSessions(missed)
                } else if let report = reports[task.id],
                          [.insufficientTimeBeforeDeadline, .dailyCapReached, .calendarFullyBooked].contains(report.primaryReason) {
                    reason = .wontFit(minutesShort: report.unscheduledMinutes, deadline: task.effectiveDeadline)
                } else if done >= task.effectiveDuration {
                    reason = .allTimeDone
                } else {
                    reason = .notPlannedYet
                }
            }
            return UnplannedTask(task: task, reason: reason)
        }
        .sorted { ($0.task.effectiveDeadline ?? .distantFuture) < ($1.task.effectiveDeadline ?? .distantFuture) }
    }

    /// Re-plan for a task whose sessions were missed: they're marked not done and the work is planned again.
    public func replanMissedWork(taskId: UUID, now: Date = Date()) {
        let ids = workSessions.filter { $0.taskId == taskId && RuleBasedSchedulingEngine.isMissed($0, at: now) }.map(\.id)
        for id in ids {
            if let idx = workSessions.firstIndex(where: { $0.id == id }) { workSessions[idx].status = .skipped }
        }
        knownMissedSessionIds.subtract(ids)
        if let tIdx = tasks.firstIndex(where: { $0.id == taskId }), !ids.isEmpty {
            tasks[tIdx].isCarryover = true
            tasks[tIdx].updatedAt = now
        }
        generateProposedPlan(isAutomatic: true, keepExistingPlan: true)
        saveDatabase()
    }

    /// Raise Priority: one step up (Low → Medium → High → Urgent).
    public func raisePriority(taskId: UUID) {
        guard let task = tasks.first(where: { $0.id == taskId }) else { return }
        let next: TaskPriority
        switch task.userPriority {
        case .low: next = .medium
        case .medium: next = .high
        case .high, .urgent: next = .urgent
        }
        setTaskPriority(id: taskId, priority: next)
    }
}

/// An open task with nothing planned ahead.
public struct UnplannedTask: Identifiable {
    public enum Reason: Equatable {
        /// Sessions ended without being checked off (fix: Done or Re-plan).
        case missedSessions(Int)
        /// The deadline or planning target is over (fix: New Target or Dismiss).
        case deadlinePassed(Date)
        /// No deadline found (fix: Set Target).
        case needsTarget
        /// The required action is unclear (fix: review in Tasks).
        case needsClarification
        /// Not enough free time before the deadline (fix: Raise Priority or Change Estimate).
        case wontFit(minutesShort: Int, deadline: Date?)
        /// Finished sessions already cover the estimate (fix: Done or Change Estimate).
        case allTimeDone
        /// Nothing explains it yet (fix: Re-plan).
        case notPlannedYet
    }

    public let task: DiscoveredTask
    public let reason: Reason
    public var id: UUID { task.id }
}
