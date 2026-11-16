import Foundation
import AppKit
import UserNotifications

/// One line of the Sync Everything summary ("Canvas: 2 new tasks", "Email: Ollama isn't running").
public struct SyncSourceResult: Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let succeeded: Bool
    public let detail: String
}

/// Sync Everything: Apple Calendar, Canvas, Gradescope and email in one go, from the Today page,
/// the toolbar, or automatically three times a day (8 AM, 1 PM, 6 PM) while DayBook AI is open.
/// Canvas and Gradescope tabs are opened in the background when none is open, and closed again after.
extension AppState {
    /// Whether any real (non-demo) source is connected.
    public var hasConnectedSources: Bool {
        calendarService.authorizationStatus == .authorized || isCanvasConnected || isGradescopeConnected
            || (isGmailAuthenticated && isEmailExtractionConfigured)
    }

    public var isAnySyncRunning: Bool {
        isSyncingAll || isScanningEmails || isSyncing || isSyncingCanvas || isSyncingGradescope
    }

    public func syncEverything(automatic: Bool = false, now: Date = Date()) async {
        guard !isSyncingAll else { return }
        let tracking = beginNewTaskTracking()
        defer { endNewTaskTracking(tracking, automatic: automatic) }
        isSyncingAll = true
        defer {
            isSyncingAll = false
            syncAllProgress = nil
        }
        var results: [SyncSourceResult] = []
        let planBefore = workSessions
        isSyncReplanning = true
        defer { isSyncReplanning = false }

        // 1. Apple Calendar (fast, and Canvas/email scheduling depends on it).
        if calendarService.authorizationStatus == .authorized {
            syncAllProgress = "Refreshing Apple Calendar..."
            await refreshCalendarCommitments(isAutomatic: true)
            if let error = calendarErrorMessage {
                results.append(SyncSourceResult(name: "Calendar", succeeded: false, detail: error))
            } else {
                let today = commitments.filter { Calendar.current.isDate($0.startTime, inSameDayAs: now) }.count
                results.append(SyncSourceResult(name: "Calendar", succeeded: true,
                                                detail: "\(today) event\(today == 1 ? "" : "s") today"))
            }
        }

        // 2. Canvas (before email: its due dates keep email tasks from duplicating).
        if isCanvasConnected {
            syncAllProgress = "Reading Canvas..."
            var prep: (CanvasBrowser, [String], BrowserTabOpener.Preparation)? = nil
            if let browser = preferences.canvasBrowser, let base = canvasBaseURL, let host = base.host {
                let prefixes = CanvasBrowserTransport(browser: browser, canvasHost: host).prefixes
                let p = await prepareTab(browser, url: base.appendingPathComponent("dashboard"), prefixes: prefixes, site: "Canvas")
                prep = (browser, prefixes, p)
            }
            if let problem = prep?.2.problem {
                results.append(SyncSourceResult(name: "Canvas", succeeded: false, detail: problem))
            } else {
                await syncCanvas(now: now)
                results.append(Self.result("Canvas", error: canvasErrorMessage, status: canvasStatusMessage))
            }
            if var prep {
                // Leave the tab open when Canvas failed (for example to sign in again).
                if results.last?.succeeded == false, prep.2.problem == nil { prep.2.problem = results.last?.detail }
                tidyUpTab(prep.0, prefixes: prep.1, preparation: prep.2)
            }
        }

        // 3. Gradescope.
        if let browser = preferences.gradescopeBrowser {
            syncAllProgress = "Reading Gradescope..."
            let prefixes = ["https://\(GradescopeReader.host)/", "https://gradescope.com/"]
            var p = await prepareTab(browser, url: URL(string: "https://\(GradescopeReader.host)/account")!, prefixes: prefixes, site: "Gradescope")
            if let problem = p.problem {
                results.append(SyncSourceResult(name: "Gradescope", succeeded: false, detail: problem))
            } else {
                await syncGradescope(now: now)
                results.append(Self.result("Gradescope", error: gradescopeErrorMessage, status: gradescopeStatusMessage))
                // Leave the tab open when Gradescope failed (for example to sign in again).
                if results.last?.succeeded == false { p.problem = results.last?.detail }
            }
            tidyUpTab(browser, prefixes: prefixes, preparation: p)
        }

        // 4. Email (last 72 hours, through the local model).
        if isGmailAuthenticated && isEmailExtractionConfigured {
            syncAllProgress = "Scanning email..."
            await scanEmailsFromLast3Days()
            results.append(Self.result("Email", error: lastScanError, status: lastScanSuccessSummary ?? "Scanned the last 3 days."))
        } else if !automatic && isDemonstrationModeActive {
            syncAllProgress = "Scanning the sample inbox..."
            await runSimulatedEmailDiscovery()
            results.append(SyncSourceResult(name: "Email", succeeded: true, detail: lastSyncMessage ?? "Sample inbox scanned."))
        }

        if results.isEmpty {
            results.append(SyncSourceResult(name: "Nothing connected", succeeded: false,
                                            detail: "Connect Apple Calendar, Canvas, Gradescope or Gmail in Settings."))
        } else {
            preferences.lastFullSyncDate = now
        }
        // Re-plan with everything new, then show only what changed.
        recalculateSchedule()
        saveDatabase()
        lastSyncPlanChanges = Self.describePlanChanges(before: planBefore, after: workSessions, tasks: tasks,
                                                       now: Date(), timeZone: preferences.timeZone)
        lastSyncAllResults = results
        isSyncingAll = false
        sendMorningSummaryIfDue()
        sendEveningCheckInIfDue()
    }

    static func result(_ name: String, error: String?, status: String?) -> SyncSourceResult {
        if let error, !error.isEmpty {
            return SyncSourceResult(name: name, succeeded: false, detail: error)
        }
        var detail = status ?? "Up to date."
        if detail.hasPrefix(name + ": ") { detail = String(detail.dropFirst(name.count + 2)) }
        return SyncSourceResult(name: name, succeeded: true, detail: detail)
    }

    private func prepareTab(_ browser: CanvasBrowser, url: URL, prefixes: [String], site: String) async -> BrowserTabOpener.Preparation {
        if let override = browserTabPreparerOverride { return await override(browser, url, prefixes) }
        return await BrowserTabOpener.prepare(browser: browser, url: url, prefixes: prefixes, siteName: site)
    }

    private func tidyUpTab(_ browser: CanvasBrowser, prefixes: [String], preparation: BrowserTabOpener.Preparation) {
        guard browserTabPreparerOverride == nil else { return }
        BrowserTabOpener.tidyUp(browser: browser, prefixes: prefixes, preparation: preparation)
    }

    /// Hides a task's "Updated" reminder.
    public func acknowledgeTaskUpdate(taskId: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[idx].syncUpdate?.isSeen = true
        saveDatabase()
    }

    // MARK: - Automatic sync (8 AM, 1 PM, 6 PM)

    /// The scheduled time that is due now, or nil. A slot is due when it has passed and no full sync
    /// has run since; a slot missed while the Mac was asleep runs once on wake (never several at once).
    public static func dueAutoSyncSlot(now: Date, lastSync: Date?, hours: [Int] = UserPreferences.autoSyncHours,
                                       calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        let slots = hours.sorted().compactMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: today) }
        let latest: Date?
        if let passed = slots.last(where: { $0 <= now }) {
            latest = passed
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), let lastHour = hours.max() {
            latest = calendar.date(bySettingHour: lastHour, minute: 0, second: 0, of: yesterday)
        } else {
            latest = nil
        }
        guard let slot = latest else { return nil }
        if let lastSync, lastSync >= slot { return nil }
        return slot
    }

    /// Next scheduled time after `now` (for "Next sync at 1:00 PM").
    public static func nextAutoSyncTime(after now: Date, hours: [Int] = UserPreferences.autoSyncHours,
                                        calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        for day in 0...1 {
            guard let base = calendar.date(byAdding: .day, value: day, to: today) else { continue }
            for hour in hours.sorted() {
                if let t = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base), t > now { return t }
            }
        }
        return nil
    }

    func startAutoSync() {
        autoSyncTimer?.invalidate()
        // Checks every 5 minutes; a slot runs at most once.
        UNUserNotificationCenter.current().delegate = DayBookNotificationDelegate.shared
        DayBookNotificationDelegate.appState = self
        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.runAutoSyncIfDue()
                self?.sendMorningSummaryIfDue()
                self?.sendEveningCheckInIfDue()
                self?.runDailyBackupIfDue()
                self?.replanIfSessionsWereMissed()
            }
        }
        // After waking from sleep, give the network a moment, then catch up on a missed slot.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await self?.runAutoSyncIfDue()
            }
        }
        // Shortly after launch.
        replanIfSessionsWereMissed()
        pruneTimeQuestions()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            await self?.runAutoSyncIfDue()
        }
    }

    public func runAutoSyncIfDue(now: Date = Date()) async {
        guard preferences.autoSyncEnabled, hasConnectedSources, !isAnySyncRunning,
              Self.dueAutoSyncSlot(now: now, lastSync: preferences.lastFullSyncDate) != nil else { return }
        await syncEverything(automatic: true, now: now)
    }
}
