import Foundation

/// Deleting and dragging planned sessions on Today and Week.
extension AppState {
    private var planningCalendar: Calendar { SessionShifter.calendar(preferences) }

    /// A deleted task session keeps that task off its day until the day is over.
    func pruneDeclinedSlots(now: Date = Date()) {
        let cal = planningCalendar
        declinedSlots.removeAll { slot in
            let dayEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: slot.start)) ?? slot.end
            return max(slot.end, dayEnd) <= now
        }
    }

    /// Most minutes each task may have on a day where you deleted one of its sessions.
    var taskDayLimits: [UUID: [Date: Int]] {
        let cal = planningCalendar
        var limits: [UUID: [Date: Int]] = [:]
        for slot in declinedSlots {
            guard let id = slot.taskId else { continue }
            let day = cal.startOfDay(for: slot.start)
            let minutes = slot.minutesLeftThatDay ?? 0
            limits[id, default: [:]][day] = min(limits[id]?[day] ?? .max, minutes)
        }
        return limits
    }

    /// Planned (not done) minutes of a task on the day containing `date`.
    func plannedMinutes(of taskId: UUID, onDayOf date: Date) -> Int {
        let cal = planningCalendar
        return workSessions.filter { $0.taskId == taskId && $0.status == .planned && cal.isDate($0.startTime, inSameDayAs: date) }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    /// After deleting a session: later sessions that day move up into the freed time.
    func shiftSessionsForward(freedFrom: Date, now: Date = Date()) {
        workSessions = SessionShifter.shiftForward(sessions: workSessions, freedFrom: freedFrom,
                                                   commitments: planningCommitments, preferences: preferences, now: now)
    }

    // MARK: - Drag and drop

    /// Sessions you can drag: anything not done, locked or paid work.
    public func canDragSession(_ s: WorkSession) -> Bool {
        s.status != .completed && s.status != .skipped && !s.isLocked && !s.isPaidWork
    }

    /// Moves a dragged session to the first free time on `day`, after `after` when it was dropped on an
    /// item (so it lands right after that item). The session becomes "Adjusted", so re-plans keep it there;
    /// nothing else moves, and only missing work is placed again. Returns false when it doesn't fit.
    @discardableResult
    public func dropSession(id: UUID, onDay day: Date, after: Date? = nil, now: Date = Date()) -> Bool {
        guard let idx = workSessions.firstIndex(where: { $0.id == id }), canDragSession(workSessions[idx]) else { return false }
        let session = workSessions[idx]
        let cal = planningCalendar
        guard let start = SessionShifter.slot(for: session, on: day, after: after, sessions: workSessions,
                                              commitments: planningCommitments, preferences: preferences, now: now) else {
            let df = DateFormatter()
            df.dateFormat = "EEEE"
            df.timeZone = preferences.timeZone
            schedulingStatusMessage = "No free time \(after == nil ? "on" : "after that on") \(df.string(from: day)) for this \(session.durationMinutes)m session."
            return false
        }
        guard start != session.startTime else { return true }
        let duration = session.endTime.timeIntervalSince(session.startTime)
        workSessions[idx].startTime = start
        workSessions[idx].endTime = start.addingTimeInterval(duration)
        workSessions[idx].isManuallyAdjusted = true
        // Dragging a task back onto a day you removed it from brings it back there.
        if let taskId = session.taskId {
            declinedSlots.removeAll { $0.taskId == taskId && cal.isDate($0.start, inSameDayAs: start) }
        }
        let df = DateFormatter()
        df.dateFormat = "EEE h:mm a"
        df.timeZone = preferences.timeZone
        generateProposedPlan(isAutomatic: true, keepExistingPlan: true)
        schedulingStatusMessage = "Moved \(session.title.replacingOccurrences(of: "Work Session: ", with: "")) to \(df.string(from: start))."
        saveDatabase()
        return true
    }
}
