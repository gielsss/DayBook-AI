import Foundation
import UserNotifications

/// Smoother planning around Sync Everything:
/// - AI time estimates for Canvas/Gradescope assignments (asked once per assignment),
/// - "what changed" in the plan after a sync re-plans,
/// - a morning summary notification built from today's sessions, deadlines and open questions.
extension AppState {
    // MARK: - AI time estimates

    /// Asks the local model how long each Canvas/Gradescope assignment takes: once per task, and again only
    /// when what Canvas says about it changes (new instructions, rubric or attached files).
    /// Never overrides a duration the user set. Returns how many estimates changed.
    @discardableResult
    public func estimateLMSTaskTimes(now: Date = Date(), limit: Int = 12) async -> Int {
        guard preferences.aiTimeEstimatesEnabled else { return 0 }
        let pending = tasks.filter { task in
            [.canvas, .gradescope].contains(task.sourceEmail.category)
                && (task.estimateNote == nil || task.estimateInputKey != estimateInputKey(for: task))
                && task.userOverriddenDuration == nil
                && task.status != .completed && task.status != .dismissed && !task.isDismissed
                && (task.effectiveDeadline ?? task.extractedDeadline ?? .distantFuture) > now
        }
        .sorted { ($0.effectiveDeadline ?? .distantFuture) < ($1.effectiveDeadline ?? .distantFuture) }
        .prefix(limit)

        var changed = 0
        for task in pending {
            if isSyncingCanvas { canvasStatusMessage = "Estimating time for \(task.title) with \(ollamaModel)..." }
            if isSyncingGradescope { gradescopeStatusMessage = "Estimating time for \(task.title) with \(ollamaModel)..." }
            do {
                guard let estimate = try await ollamaService.estimateTaskMinutes(
                    title: task.title, context: estimateContext(for: task), baseURL: ollamaBaseURL, model: ollamaModel
                ), let idx = tasks.firstIndex(where: { $0.id == task.id }) else { continue }
                // With nothing beyond a title the estimate is a guess whatever the model says: it's marked for
                // checking and never goes below the built-in rule of thumb (models give tiny numbers here).
                let hasInstructions = Self.instructionText(of: task).count >= 50
                var minutes = estimate.plannedMinutes
                if !hasInstructions { minutes = max(minutes, Self.ruleOfThumbMinutes(for: task)) }
                let reason = estimate.reason.trimmingCharacters(in: .whitespacesAndNewlines)
                let why = !hasInstructions ? "from the title only" : reason
                tasks[idx].estimateNote = "AI estimate: \(Self.durationText(minutes))" + (why.isEmpty ? "" : " — \(why)")
                tasks[idx].estimateInputKey = estimateInputKey(for: task)
                tasks[idx].estimateConfidence = hasInstructions ? (estimate.confidence ?? "medium") : "low"
                if tasks[idx].userOverriddenDuration == nil, tasks[idx].estimatedMinutes != minutes {
                    // A fresh AI estimate replaces any earlier adjustment from your history (it's applied again below).
                    tasks[idx].estimatedMinutes = minutes
                    tasks[idx].rawEstimateMinutes = nil
                    tasks[idx].calibrationNote = nil
                    changed += 1
                }
            } catch let error as AIServiceError where error.isFatalForScan {
                break // Ollama not running / model missing: try again next sync
            } catch {
                continue // left as it was, so it's retried next sync
            }
        }
        if !pending.isEmpty {
            calibrateEstimates()
            recalculateSchedule()
            saveDatabase()
        }
        return changed
    }

    /// Built-in estimate for a task (kind read back from its required action).
    static func ruleOfThumbMinutes(for task: DiscoveredTask) -> Int {
        let action = task.requiredAction
        let kind = action.hasPrefix("Complete quiz") ? "quiz" : action.hasPrefix("Post in discussion") ? "discussion_topic" : "assignment"
        return ruleOfThumbMinutes(title: task.title, kind: kind, points: points(in: task.notes), instructionLength: instructionText(of: task).count)
    }

    /// "Looks Right" on an estimate marked Check Estimate.
    public func confirmEstimate(taskId: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[idx].estimateConfidence = "confirmed"
        saveDatabase()
    }

    /// Instructions the estimate can go on: Canvas details, or the description saved in the notes.
    static func instructionText(of task: DiscoveredTask) -> String {
        if let details = task.assignmentDetails, !details.isEmpty { return details }
        // Notes hold "Course:", "Points:", the link, then the description after a blank line.
        let parts = task.notes.components(separatedBy: "\n\n")
        return parts.count > 1 ? parts.dropFirst().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    /// Changes whenever what the estimate is based on changes.
    func estimateInputKey(for task: DiscoveredTask) -> String {
        CanvasText.fingerprint(task.title + "\u{1F}" + Self.instructionText(of: task))
    }

    /// What the model is told about an assignment besides its title.
    func estimateContext(for task: DiscoveredTask) -> String {
        let service = task.sourceEmail.category == .gradescope ? "Gradescope" : "Canvas"
        let course = Self.courseKey(task)
        var lines = ["Course: \(task.sourceEmail.senderName)", "From: \(service)"]
        if let points = Self.points(in: task.notes) {
            let others = tasks.filter { $0.id != task.id && Self.courseKey($0) == course && !course.isEmpty }
                .compactMap { Self.points(in: $0.notes) }.sorted()
            var line = "Points: \(Self.pointsText(points))"
            if others.count >= 2 { line += " (other assignments in this course: typically \(Self.pointsText(others[others.count / 2])) points)" }
            lines.append(line)
        }
        let history = preferences.estimateHistory.filter { !course.isEmpty && $0.course == course }.suffix(5)
        if !history.isEmpty {
            lines.append("Your recorded times in this course: " + history.map {
                "\"\($0.title)\" planned \(Self.durationText($0.estimatedMinutes)), took \(Self.durationText($0.actualMinutes))"
            }.joined(separator: "; "))
        }
        let instructions = Self.instructionText(of: task)
        lines.append(instructions.isEmpty ? "No instructions available (title only)." : "\n" + instructions)
        return lines.joined(separator: "\n")
    }

    static func points(in notes: String) -> Double? {
        guard let line = notes.components(separatedBy: "\n").first(where: { $0.hasPrefix("Points: ") }) else { return nil }
        return Double(line.dropFirst("Points: ".count).trimmingCharacters(in: .whitespaces))
    }

    static func pointsText(_ p: Double) -> String {
        p.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(p)) : String(p)
    }

    static func durationText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    // MARK: - What the re-plan changed

    /// Compares planned (not completed, not paid-work) sessions in the coming two weeks before and after a
    /// re-plan, per task: "Essay Draft added (Tue 2:00 PM)", "Problem Set 6 moved to Wed 10:00 AM",
    /// "Lab Report no longer planned".
    public static func describePlanChanges(before: [WorkSession], after: [WorkSession], tasks: [DiscoveredTask],
                                           now: Date, timeZone: TimeZone = .current) -> [String] {
        let horizon = now.addingTimeInterval(14 * 86400)
        func planned(_ sessions: [WorkSession]) -> [UUID: [Date]] {
            var byTask: [UUID: [Date]] = [:]
            for s in sessions where s.status == .planned && !s.isPaidWork && s.endTime > now && s.startTime < horizon {
                guard let id = s.taskId else { continue }
                byTask[id, default: []].append(s.startTime)
            }
            return byTask.mapValues { $0.sorted() }
        }
        let old = planned(before), new = planned(after)
        let df = DateFormatter()
        df.dateFormat = "EEE h:mm a"
        df.timeZone = timeZone
        func name(_ id: UUID) -> String {
            tasks.first { $0.id == id }?.displayTitle ?? after.first { $0.taskId == id }?.title ?? before.first { $0.taskId == id }?.title ?? "A task"
        }
        var changes: [(Date, String)] = []
        for (id, starts) in new {
            guard let first = starts.first else { continue }
            if let previous = old[id] {
                if previous != starts { changes.append((first, "\(name(id)) moved to \(df.string(from: first))")) }
            } else {
                let extra = starts.count > 1 ? " +\(starts.count - 1) more" : ""
                changes.append((first, "\(name(id)) added (\(df.string(from: first))\(extra))"))
            }
        }
        for (id, starts) in old where new[id] == nil {
            changes.append((starts.first ?? now, "\(name(id)) no longer planned"))
        }
        return changes.sorted { $0.0 < $1.0 }.map(\.1)
    }

    // MARK: - Morning summary

    /// The morning notification text, or nil when there's nothing at all today.
    /// e.g. "3 work sessions (first at 9:00 AM) · CS 420 Lab 3 due 11:59 PM · 1 task needs clarification"
    public static func morningSummary(tasks: [DiscoveredTask], sessions: [WorkSession], commitments: [CalendarCommitment],
                                      now: Date, timeZone: TimeZone = .current) -> (title: String, body: String)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let time = DateFormatter()
        time.dateFormat = "h:mm a"
        time.timeZone = timeZone
        var parts: [String] = []

        let todaysSessions = sessions
            .filter { cal.isDate($0.startTime, inSameDayAs: now) && $0.status == .planned }
            .sorted { $0.startTime < $1.startTime }
        if let first = todaysSessions.first {
            let n = todaysSessions.count
            parts.append("\(n) work session\(n == 1 ? "" : "s") (first at \(time.string(from: first.startTime)))")
        }

        let open = tasks.filter { $0.status != .completed && $0.status != .dismissed && !$0.isDismissed && !$0.sourceEmail.isSimulatedDemo }
        let dueToday = open
            .compactMap { t -> (DiscoveredTask, Date)? in
                guard let d = t.effectiveDeadline ?? t.extractedDeadline, cal.isDate(d, inSameDayAs: now) else { return nil }
                return (t, d)
            }
            .sorted { $0.1 < $1.1 }
        if let (task, due) = dueToday.first {
            var text = "\(task.displayTitle) due \(time.string(from: due))"
            if dueToday.count > 1 { text += " (+\(dueToday.count - 1) more due today)" }
            parts.append(text)
        }

        let events = commitments.filter { cal.isDate($0.startTime, inSameDayAs: now) && !$0.isAllDay && !$0.isSimulatedDemo }.count
        if events > 0 { parts.append("\(events) event\(events == 1 ? "" : "s")") }

        let unclear = open.filter { $0.status == .needsClarification }.count
        if unclear > 0 { parts.append("\(unclear) task\(unclear == 1 ? " needs" : "s need") clarification") }

        let updated = open.filter(\.hasUnseenUpdate).count
        if updated > 0 { parts.append("\(updated) task\(updated == 1 ? " was" : "s were") updated") }

        guard !parts.isEmpty else { return nil }
        return ("Today in DayBook AI", parts.joined(separator: " · "))
    }

    /// Sends the morning summary once a day between 8 AM and noon, after the 8 AM sync has run
    /// (or right away when automatic sync is off or nothing is connected).
    public func sendMorningSummaryIfDue(now: Date = Date()) {
        guard preferences.morningSummaryEnabled, !isAnySyncRunning else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = preferences.timeZone
        let hour = cal.component(.hour, from: now)
        guard (8..<12).contains(hour) else { return }
        if let last = preferences.lastMorningSummaryDate, cal.isDate(last, inSameDayAs: now) { return }
        if preferences.autoSyncEnabled && hasConnectedSources {
            guard let eight = cal.date(bySettingHour: 8, minute: 0, second: 0, of: now),
                  let synced = preferences.lastFullSyncDate, synced >= eight else { return }
        }
        preferences.lastMorningSummaryDate = now
        saveDatabase()
        guard let summary = Self.morningSummary(tasks: tasks, sessions: workSessions, commitments: commitments,
                                                now: now, timeZone: preferences.timeZone) else { return }
        if let sender = morningSummarySender {
            sender(summary.title, summary.body)
        } else {
            Self.postNotification(title: summary.title, body: summary.body)
        }
    }

    static func postNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "daybook-morning-\(UUID().uuidString)", content: content, trigger: nil))
        }
    }
}

/// Shows DayBook AI's notifications even while the app is in front.
final class DayBookNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = DayBookNotificationDelegate()
    /// The app's state, for handling Done / Not Done Yet taps.
    nonisolated(unsafe) static weak var appState: AppState?
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
