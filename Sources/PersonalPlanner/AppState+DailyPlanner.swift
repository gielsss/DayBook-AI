import Foundation
import AppKit
import UserNotifications

/// Daily planner improvements:
/// 1. Keep today steady: once the day has started (8 AM or the morning summary), automatic re-plans from
///    Sync Everything leave today's planned sessions where they are and only use free time.
/// 2. Learn from actual time: finished tasks record estimate vs. time actually spent; new estimates for the
///    same kind of work (and course) are scaled by how far off past ones were.
/// 3. Evening check-in: after the 6 PM sync, a notification per finished session with Done / Not Done Yet.
extension AppState {
    // MARK: - 1. Keep today steady

    /// End of today when today's plan should stay put during a sync re-plan, else nil.
    func keepTodaySteadyUntil(now: Date = Date()) -> Date? {
        guard isSyncReplanning, preferences.keepTodaySteady else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = preferences.timeZone
        let summarySent = preferences.lastMorningSummaryDate.map { cal.isDate($0, inSameDayAs: now) } ?? false
        guard summarySent || cal.component(.hour, from: now) >= 8 else { return nil }
        return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))
    }

    /// A task whose urgency just rose to "Start now" or "Won't fit" and that has nothing planned today:
    /// a steady day gives way for it. Returns its title.
    static func newlyPressingTask(old: SchedulingResult?, new: SchedulingResult, sessions: [WorkSession],
                                  tasks: [DiscoveredTask], now: Date = Date()) -> String? {
        for (id, urgency) in new.urgencyByTaskId where urgency.level <= .startNow {
            if let before = old?.urgencyByTaskId[id], before.level <= .startNow { continue }
            let hasToday = sessions.contains { $0.taskId == id && $0.status == .planned && Calendar.current.isDate($0.startTime, inSameDayAs: now) }
            if !hasToday, let task = tasks.first(where: { $0.id == id }) { return task.displayTitle }
        }
        return nil
    }

    // MARK: - 2. Learn from actual time

    /// Rough kind of work from the title, used to compare like with like.
    public static func workKind(_ title: String) -> String {
        let t = " " + title.lowercased() + " "
        let kinds: [(String, [String])] = [
            ("exam prep", ["exam", "midterm", "test "]),
            ("quiz", ["quiz"]),
            ("problem set", ["problem set", "pset", "homework", " hw", "exercise", "problems"]),
            ("lab", ["lab "]),
            ("project", ["project"]),
            ("essay", ["essay", "paper", "report", "write-up", "writeup", "reflection"]),
            ("reading", ["reading", "read ", "chapter"]),
            ("discussion", ["discussion", "post ", "reply", "forum"])
        ]
        return kinds.first { $0.1.contains(where: { t.contains($0) }) }?.0 ?? "other"
    }

    static func courseKey(_ task: DiscoveredTask) -> String {
        [.canvas, .gradescope].contains(task.sourceEmail.category) ? task.sourceEmail.senderName : ""
    }

    /// A task was just completed: ask how long it really took (Today's "How long did it take?").
    /// The planned time isn't recorded on its own: sessions are usually checked off as planned, which would
    /// teach the planner nothing.
    func recordActualTime(taskId: UUID, now: Date = Date()) {
        guard let task = tasks.first(where: { $0.id == taskId }), !task.sourceEmail.isSimulatedDemo else { return }
        let planned = task.rawEstimateMinutes ?? task.estimatedMinutes
        guard planned > 0, !timeQuestions.contains(where: { $0.taskId == taskId }) else { return }
        let worked = workSessions
            .filter { $0.taskId == taskId && $0.status == .completed && $0.startTime <= now }
            .reduce(0) { $0 + $1.durationMinutes }
        timeQuestions.append(TimeQuestion(taskId: taskId, title: task.displayTitle, plannedMinutes: planned,
                                          suggestedMinutes: worked >= 10 ? worked : task.effectiveDuration, askedAt: now))
    }

    /// Answer to "How long did it take?": recorded for future estimates in the same course and kind of work.
    public func answerTimeQuestion(taskId: UUID, minutes: Int, now: Date = Date()) {
        guard let question = timeQuestions.first(where: { $0.taskId == taskId }) else { return }
        timeQuestions.removeAll { $0.taskId == taskId }
        if let task = tasks.first(where: { $0.id == taskId }), minutes > 0 {
            preferences.estimateHistory.removeAll { $0.title == task.title && $0.course == Self.courseKey(task) }
            preferences.estimateHistory.append(EstimateRecord(kind: Self.workKind(task.title), course: Self.courseKey(task),
                                                              title: task.title, estimatedMinutes: question.plannedMinutes,
                                                              actualMinutes: minutes, date: now))
            if preferences.estimateHistory.count > 80 { preferences.estimateHistory.removeFirst(preferences.estimateHistory.count - 80) }
        }
        saveDatabase()
    }

    /// Questions still worth asking: the task is still completed, newest first.
    public var openTimeQuestions: [TimeQuestion] {
        timeQuestions.filter { q in tasks.contains { $0.id == q.taskId && $0.status == .completed } }
            .sorted { $0.askedAt > $1.askedAt }
    }

    /// "Skip": nothing is recorded.
    public func skipTimeQuestion(taskId: UUID) {
        timeQuestions.removeAll { $0.taskId == taskId }
        saveDatabase()
    }

    /// Drops questions for tasks that were reopened or deleted, and ones older than two weeks.
    func pruneTimeQuestions(now: Date = Date()) {
        let before = timeQuestions.count
        timeQuestions.removeAll { q in
            now.timeIntervalSince(q.askedAt) > 14 * 86400
                || !tasks.contains { $0.id == q.taskId && $0.status == .completed }
        }
        if timeQuestions.count != before { saveDatabase() }
    }

    /// How much to scale an estimate, from finished tasks of the same kind (same course first).
    /// Needs 2 matching tasks in the course or 3 of the kind overall; nil when within ±10%.
    public static func calibration(kind: String, course: String, history: [EstimateRecord]) -> (factor: Double, basis: String)? {
        func median(_ xs: [Double]) -> Double {
            let s = xs.sorted()
            return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        }
        let sameCourse = history.filter { $0.kind == kind && !course.isEmpty && $0.course == course }.suffix(8)
        let sameKind = history.filter { $0.kind == kind }.suffix(10)
        let (records, label): (ArraySlice<EstimateRecord>, String)
        if sameCourse.count >= 2 {
            (records, label) = (sameCourse, "\(course) \(kind == "other" ? "task" : kind)s")
        } else if sameKind.count >= 3, kind != "other" {
            (records, label) = (sameKind, "\(kind)s")
        } else {
            return nil
        }
        let factor = min(2.0, max(0.5, median(records.map { Double($0.actualMinutes) / Double(max(1, $0.estimatedMinutes)) })))
        guard abs(factor - 1) > 0.1 else { return nil }
        return (factor, "your last \(records.count) \(label)")
    }

    /// Scales new estimates by past actual time. Each task is adjusted once; durations you set are never changed.
    /// Canvas/Gradescope tasks wait for their AI estimate first (when AI estimates are on).
    @discardableResult
    public func calibrateEstimates() -> Int {
        guard preferences.learnFromActualTime else { return 0 }
        var changed = 0
        for i in tasks.indices {
            let task = tasks[i]
            guard task.rawEstimateMinutes == nil, task.userOverriddenDuration == nil,
                  task.status != .completed, task.status != .dismissed, !task.isDismissed,
                  !task.sourceEmail.isSimulatedDemo else { continue }
            let isLMS = [.canvas, .gradescope].contains(task.sourceEmail.category)
            if isLMS && preferences.aiTimeEstimatesEnabled && task.estimateNote == nil { continue }
            guard let (factor, basis) = Self.calibration(kind: Self.workKind(task.title), course: Self.courseKey(task),
                                                          history: preferences.estimateHistory) else { continue }
            let raw = task.estimatedMinutes
            let adjusted = min(600, max(15, Int((Double(raw) * factor / 15).rounded()) * 15))
            guard adjusted != raw else { continue }
            tasks[i].rawEstimateMinutes = raw
            tasks[i].estimatedMinutes = adjusted
            let pct = Int(((factor - 1) * 100).rounded())
            tasks[i].calibrationNote = "Adjusted \(pct > 0 ? "+" : "")\(pct)% (\(Self.durationText(raw)) → \(Self.durationText(adjusted))) from \(basis)"
            changed += 1
        }
        return changed
    }

    // MARK: - 3. Evening check-in

    static let checkInCategory = "DAYBOOK_SESSION_CHECKIN"
    static let checkInDoneAction = "DAYBOOK_DONE"
    static let checkInNotDoneAction = "DAYBOOK_NOT_DONE"

    /// Today's work sessions that have ended but were never marked done (what the check-in asks about).
    public func sessionsAwaitingCheckIn(now: Date = Date()) -> [WorkSession] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = preferences.timeZone
        return workSessions
            .filter { cal.isDate($0.startTime, inSameDayAs: now) && $0.status == .planned && $0.taskId != nil
                && !$0.isPaidWork && !$0.isSimulatedDemo && $0.endTime <= now }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Once a day between 6 PM and 11 PM, after the 6 PM sync (or right away when automatic sync is off).
    public func sendEveningCheckInIfDue(now: Date = Date()) {
        guard preferences.eveningCheckInEnabled, !isAnySyncRunning else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = preferences.timeZone
        guard (18..<23).contains(cal.component(.hour, from: now)) else { return }
        if let last = preferences.lastEveningCheckInDate, cal.isDate(last, inSameDayAs: now) { return }
        if preferences.autoSyncEnabled && hasConnectedSources {
            guard let six = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now),
                  let synced = preferences.lastFullSyncDate, synced >= six else { return }
        }
        preferences.lastEveningCheckInDate = now
        saveDatabase()
        let sessions = sessionsAwaitingCheckIn(now: now)
        guard !sessions.isEmpty else { return }
        if let sender = eveningCheckInSender {
            sender(sessions)
        } else {
            Self.postCheckInNotifications(sessions, timeZone: preferences.timeZone)
        }
    }

    static func postCheckInNotifications(_ sessions: [WorkSession], timeZone: TimeZone) {
        let center = UNUserNotificationCenter.current()
        let done = UNNotificationAction(identifier: checkInDoneAction, title: "Done")
        let notDone = UNNotificationAction(identifier: checkInNotDoneAction, title: "Not Done Yet")
        center.setNotificationCategories([UNNotificationCategory(identifier: checkInCategory, actions: [done, notDone],
                                                                 intentIdentifiers: [])])
        let time = DateFormatter()
        time.dateFormat = "h:mm a"
        time.timeZone = timeZone
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            for (i, s) in sessions.prefix(6).enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "Did you finish \(s.title)?"
                content.body = "Planned \(time.string(from: s.startTime))–\(time.string(from: s.endTime)). Not Done Yet moves it to your next workday."
                content.categoryIdentifier = checkInCategory
                content.userInfo = ["sessionId": s.id.uuidString]
                content.sound = i == 0 ? .default : nil
                center.add(UNNotificationRequest(identifier: "daybook-checkin-\(s.id.uuidString)", content: content, trigger: nil))
            }
            if sessions.count > 6 {
                let content = UNMutableNotificationContent()
                content.title = "\(sessions.count - 6) more sessions to review"
                content.body = "Open DayBook AI for the End-of-Day Review."
                center.add(UNNotificationRequest(identifier: "daybook-checkin-more", content: content, trigger: nil))
            }
        }
    }

    /// Done / Not Done Yet from the evening check-in: the same as the Catch Up card on Today.
    /// Not Done Yet keeps the task's estimate and plans the work again in the next free time.
    public func handleCheckIn(sessionId: UUID, done: Bool) {
        guard let session = workSessions.first(where: { $0.id == sessionId }), session.status == .planned else { return }
        answerMissedSession(id: session.id, done: done)
    }
}

extension DayBookNotificationDelegate {
    /// Buttons on the evening check-in; tapping the notification itself opens the End-of-Day Review.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let sessionId = (info["sessionId"] as? String).flatMap(UUID.init)
        Task { @MainActor in
            defer { completionHandler() }
            guard let app = DayBookNotificationDelegate.appState else { return }
            if let sessionId, action == AppState.checkInDoneAction {
                app.handleCheckIn(sessionId: sessionId, done: true)
            } else if let sessionId, action == AppState.checkInNotDoneAction {
                app.handleCheckIn(sessionId: sessionId, done: false)
            } else if sessionId != nil || response.notification.request.identifier == "daybook-checkin-more" {
                NSApp.activate(ignoringOtherApps: true)
                app.selectedTab = .today
                app.showEndOfDayReviewSheet = true
            }
        }
    }
}
