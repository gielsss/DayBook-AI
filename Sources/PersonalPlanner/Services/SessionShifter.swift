import Foundation

/// Moves planned sessions within one day without re-planning anything else:
/// - `shiftForward`: after a session is deleted, later sessions that day move up into the freed time,
///   in the same order, never earlier than now, around events, lunch and fixed sessions.
/// - `slot`: the first free time on a day where a dragged session fits (used by drag and drop).
public enum SessionShifter {
    typealias Interval = (start: Date, end: Date)

    static func calendar(_ preferences: UserPreferences) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = preferences.timeZone
        return cal
    }

    /// Working hours of the day containing `day`, or nil on a day off.
    static func workingWindow(on day: Date, preferences: UserPreferences) -> Interval? {
        let cal = calendar(preferences)
        let hours = preferences.workingHours(for: cal.component(.weekday, from: day))
        guard hours.isWorkday,
              let start = cal.date(bySettingHour: hours.startHour, minute: hours.startMinute, second: 0, of: day),
              let end = cal.date(bySettingHour: hours.endHour, minute: hours.endMinute, second: 0, of: day),
              start < end else { return nil }
        return (start, end)
    }

    /// Now rounded up to the next 5 minutes, so moved sessions start on tidy times.
    static func roundedUp(_ date: Date) -> Date {
        let step = 300.0
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / step).rounded(.up) * step)
    }

    /// Busy time on a day: before now, blocking events, lunch and the given sessions.
    static func busyIntervals(in window: Interval, sessions: [WorkSession], commitments: [CalendarCommitment],
                              preferences: UserPreferences, now: Date) -> [Interval] {
        let cal = calendar(preferences)
        var busy: [Interval] = []
        if now > window.start { busy.append((window.start, min(window.end, roundedUp(now)))) }
        for c in commitments where c.blocksScheduling && c.endTime > window.start && c.startTime < window.end {
            if c.isAllDay && !preferences.allDayEventsBlockTime { continue }
            if c.isSimulatedDemo && !preferences.includeDemoDataInPlan { continue }
            busy.append((max(window.start, c.startTime), min(window.end, c.endTime)))
        }
        if let lunchStart = cal.date(bySettingHour: preferences.lunchStartHour, minute: 0, second: 0, of: window.start),
           let lunchEnd = cal.date(byAdding: .minute, value: preferences.lunchDurationMinutes, to: lunchStart),
           lunchStart < window.end && lunchEnd > window.start {
            busy.append((max(window.start, lunchStart), min(window.end, lunchEnd)))
        }
        for s in sessions where s.endTime > window.start && s.startTime < window.end {
            busy.append((max(window.start, s.startTime), min(window.end, s.endTime)))
        }
        return busy.sorted { $0.start < $1.start }
    }

    /// Earliest start at or after `from` where `duration` fits before `until` without touching `busy`.
    static func earliestStart(duration: TimeInterval, from: Date, until: Date, busy: [Interval]) -> Date? {
        var cursor = from
        for b in busy where b.end > cursor {
            if b.start >= cursor.addingTimeInterval(duration) { break }
            cursor = max(cursor, b.end)
        }
        return cursor.addingTimeInterval(duration) <= until ? cursor : nil
    }

    /// Sessions that may slide up after a deletion: planned task work the planner owns (not locked, moved
    /// by you, published, paid work or already started).
    static func canShift(_ s: WorkSession, now: Date) -> Bool {
        s.status == .planned && s.taskId != nil && !s.isLocked && !s.isManuallyAdjusted
            && !s.isPaidWork && !s.isPublished && s.startTime >= now
    }

    /// Moves the sessions after `freedFrom` on that day up into free time, keeping their order and length.
    /// A session never moves later than where it was. Returns the full session list.
    public static func shiftForward(sessions: [WorkSession], freedFrom: Date, commitments: [CalendarCommitment],
                                    preferences: UserPreferences, now: Date) -> [WorkSession] {
        guard let window = workingWindow(on: freedFrom, preferences: preferences) else { return sessions }
        let cal = calendar(preferences)
        let sameDay = { (s: WorkSession) in cal.isDate(s.startTime, inSameDayAs: freedFrom) }
        let movableIds = Set(sessions.filter { sameDay($0) && $0.startTime >= freedFrom && canShift($0, now: now) }.map(\.id))
        guard !movableIds.isEmpty else { return sessions }

        let fixed = sessions.filter { !movableIds.contains($0.id) && $0.status != .skipped }
        var busy = busyIntervals(in: window, sessions: fixed, commitments: commitments, preferences: preferences, now: now)
        let breakTime = TimeInterval(max(0, preferences.breakMinutes) * 60)
        var cursor = max(freedFrom, window.start)
        var result = sessions
        for idx in result.indices.filter({ movableIds.contains(result[$0].id) }).sorted(by: { result[$0].startTime < result[$1].startTime }) {
            let s = result[idx]
            let duration = s.endTime.timeIntervalSince(s.startTime)
            var start = s.startTime
            if let earlier = earliestStart(duration: duration, from: cursor, until: window.end, busy: busy), earlier < s.startTime {
                start = earlier
                result[idx].startTime = earlier
                result[idx].endTime = earlier.addingTimeInterval(duration)
            }
            let end = start.addingTimeInterval(duration)
            busy.append((start, end))
            busy.sort { $0.start < $1.start }
            cursor = end.addingTimeInterval(breakTime)
        }
        return result
    }

    /// First free start on `day` for `session` (same length), at or after `after` when given, within working
    /// hours, around events, lunch and every other session (with a break after a session it follows).
    public static func slot(for session: WorkSession, on day: Date, after: Date?, sessions: [WorkSession],
                            commitments: [CalendarCommitment], preferences: UserPreferences, now: Date) -> Date? {
        guard let window = workingWindow(on: day, preferences: preferences) else { return nil }
        let breakTime = TimeInterval(max(0, preferences.breakMinutes) * 60)
        let others = sessions.filter { $0.id != session.id && $0.status != .skipped }
        // Other planner sessions keep a break around them.
        let padded = others.map { s -> WorkSession in
            var p = s
            p.startTime = s.startTime.addingTimeInterval(-breakTime)
            p.endTime = s.endTime.addingTimeInterval(breakTime)
            return p
        }
        let busy = busyIntervals(in: window, sessions: padded, commitments: commitments, preferences: preferences, now: now)
        let from = max(window.start, after ?? window.start)
        return earliestStart(duration: session.endTime.timeIntervalSince(session.startTime), from: from,
                             until: window.end, busy: busy)
    }
}
