import Foundation
import CryptoKit

/// Canvas LMS integration: connect (in-app sign-in or token), then turn Canvas content into tasks.
///
/// - Items with due dates become tasks directly (no AI), keyed by their Canvas ID so re-syncs update
///   instead of duplicating, and submitted work is marked done.
/// - Free text (announcements, inbox, discussions, feedback, syllabi) goes through the local model,
///   cached by content fingerprint so unchanged items are never analyzed twice.
/// - Course events become local timeline commitments.
extension AppState {
    static let kCanvasCookies = "canvas_session_cookies"
    static let kCanvasToken = "canvas_access_token"
    static let canvasCalendarPrefix = "Canvas · "

    // MARK: - Connection

    public var canvasBaseURL: URL? { CanvasClient.normalizedBaseURL(preferences.canvasBaseURL) }

    public func setCanvasAddress(_ address: String) {
        let normalized = CanvasClient.normalizedBaseURL(address)?.absoluteString ?? address.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized != preferences.canvasBaseURL {
            preferences.canvasBaseURL = normalized
            disconnectCanvas()
        }
        saveDatabase()
    }

    /// Finds the Canvas site for what the user typed. Checks that the address really is Canvas
    /// (its API answers "user authorization required" when signed out) and, for a school's main
    /// domain such as "www.stateu.edu", tries "canvas.stateu.edu". Saves and returns the address that works.
    @discardableResult
    public func resolveCanvasAddress(_ input: String) async -> URL? {
        guard let typed = CanvasClient.normalizedBaseURL(input), let host = typed.host else {
            canvasErrorMessage = "Enter your school's Canvas address, for example canvas.yourschool.edu."
            return nil
        }
        var candidates = [typed]
        if !host.hasPrefix("canvas.") {
            let schoolDomain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            if let guess = CanvasClient.normalizedBaseURL("canvas." + schoolDomain) { candidates.append(guess) }
        }
        for candidate in candidates where await CanvasClient.looksLikeCanvas(candidate, session: canvasURLSession) {
            setCanvasAddress(candidate.absoluteString)
            canvasErrorMessage = nil
            if candidate != typed {
                canvasStatusMessage = "\(host) isn't Canvas; using \(candidate.host ?? "") instead."
            }
            return candidate
        }
        canvasErrorMessage = "\(host) doesn't look like a Canvas site. Use the address you see in your browser when Canvas is open (often canvas.yourschool.edu)."
        return nil
    }

    /// Restores the saved Canvas connection at launch (not verified until the next sync).
    public func loadCanvasConnection() {
        isCanvasConnected = canvasAuth() != nil && canvasBaseURL != nil
    }

    func canvasAuth() -> CanvasAuth? {
        if let browser = preferences.canvasBrowser {
            return .browser(browser)
        }
        if let token = keychainService.getCredential(key: Self.kCanvasToken), !token.isEmpty {
            return .token(token)
        }
        if let json = keychainService.getCredential(key: Self.kCanvasCookies),
           let cookies = try? JSONDecoder().decode([StoredCookie].self, from: Data(json.utf8)),
           !cookies.isEmpty {
            return .session(cookies: cookies)
        }
        return nil
    }

    func makeCanvasClient(auth: CanvasAuth) -> CanvasClient? {
        guard let base = canvasBaseURL else { return nil }
        if case .browser(let browser) = auth, let host = base.host {
            let transport = canvasBrowserTransportFactory?(browser, host) ?? { req in try await CanvasBrowserTransport(browser: browser, canvasHost: host).send(req) }
            return CanvasClient(baseURL: base, auth: auth, session: canvasURLSession, transport: transport)
        }
        if case .session(let cookies) = auth, canvasUsesBrowserEngine {
            let fetcher = CanvasWebFetcher(baseURL: base, cookies: cookies)
            return CanvasClient(baseURL: base, auth: auth, session: canvasURLSession, transport: { try await fetcher.send($0) })
        }
        return CanvasClient(baseURL: base, auth: auth, session: canvasURLSession)
    }

    /// Called by the sign-in window once Canvas, asked from inside the signed-in page, answered
    /// /api/v1/users/self with 200. Saves the window's whole sign-in (all cookies, including the
    /// school's SSO ones) to Keychain. `host` is where Canvas actually is (may differ from what was typed).
    public func completeCanvasSignInFromWindow(cookies: [HTTPCookie], host: String, userName: String) {
        if let actual = CanvasClient.normalizedBaseURL(host), actual != canvasBaseURL {
            setCanvasAddress(actual.absoluteString)
        }
        let stored = cookies.map(StoredCookie.init)
        guard let data = try? JSONEncoder().encode(stored), let json = String(data: data, encoding: .utf8) else { return }
        try? keychainService.saveCredential(key: Self.kCanvasCookies, value: json)
        try? keychainService.deleteCredential(key: Self.kCanvasToken)
        canvasUserName = userName
        preferences.canvasBrowser = nil
        isCanvasConnected = true
        canvasErrorMessage = nil
        canvasSignInDetail = nil
        canvasStatusMessage = "Connected to Canvas\(userName.isEmpty ? "" : " as \(userName)")."
    }

    /// Called by the sign-in window with the cookies it holds. Returns true once Canvas accepts them.
    @discardableResult
    public func completeCanvasSignIn(cookies: [HTTPCookie]) async -> Bool {
        guard let host = canvasBaseURL?.host else { return false }
        let stored = cookies.map(StoredCookie.init).filter { $0.applies(to: host) }
        guard !stored.isEmpty else {
            canvasSignInDetail = "No Canvas sign-in found in the window yet (\(cookies.count) cookies, none for \(host))."
            return false
        }
        let ok = await verifyAndSaveCanvas(auth: .session(cookies: stored))
        if !ok {
            // Names only (never values), to diagnose which session cookie Canvas expects.
            let names = stored.map(\.name).sorted().joined(separator: ", ")
            canvasSignInDetail = "Canvas didn't accept the copied sign-in yet: \(canvasLastVerifyReply ?? "no reply"). Cookies: \(names)."
        }
        return ok
    }

    public func connectCanvas(token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !(await verifyAndSaveCanvas(auth: .token(trimmed))) && canvasErrorMessage == nil {
            canvasErrorMessage = "Canvas didn't accept that token."
        }
    }

    private func verifyAndSaveCanvas(auth: CanvasAuth) async -> Bool {
        guard let client = makeCanvasClient(auth: auth) else {
            canvasErrorMessage = "Enter your school's Canvas address first."
            return false
        }
        do {
            let me = try await client.get("/api/v1/users/self") as? [String: Any]
            canvasUserName = (me?["short_name"] as? String) ?? (me?["name"] as? String) ?? ""
            switch auth {
            case .token(let token):
                try? keychainService.saveCredential(key: Self.kCanvasToken, value: token)
                try? keychainService.deleteCredential(key: Self.kCanvasCookies)
            case .session(let cookies):
                if let data = try? JSONEncoder().encode(cookies), let json = String(data: data, encoding: .utf8) {
                    try? keychainService.saveCredential(key: Self.kCanvasCookies, value: json)
                }
                try? keychainService.deleteCredential(key: Self.kCanvasToken)
            case .browser:
                break
            }
            if case .browser = auth {} else { preferences.canvasBrowser = nil }
            isCanvasConnected = true
            canvasErrorMessage = nil
            canvasStatusMessage = "Connected to Canvas\(canvasUserName.isEmpty ? "" : " as \(canvasUserName)")."
            return true
        } catch {
            // During sign-in this is expected until the login finishes; the sheet keeps trying.
            canvasLastVerifyReply = error.localizedDescription
            canvasErrorMessage = (error as? CanvasError)?.kind == .signInRequired ? nil : error.localizedDescription
            return false
        }
    }

    // MARK: - Browser-tab mode

    /// Connects through a Canvas tab the user already has open (and signed in to) in `browser`.
    /// Pass nil to search the running browsers for a Canvas tab.
    public func connectCanvasThroughBrowser(_ browser: CanvasBrowser?) async {
        canvasErrorMessage = nil
        guard let host = canvasBaseURL?.host else {
            canvasErrorMessage = "Enter your school's Canvas address first."
            return
        }
        var chosen = browser
        if chosen == nil {
            canvasStatusMessage = "Looking for a Canvas tab in your browsers..."
            let (found, problem) = await CanvasBrowserTransport.findBrowserWithCanvasTab(canvasHost: host)
            chosen = found
            if found == nil {
                canvasStatusMessage = nil
                canvasErrorMessage = problem?.message ?? "No open browser (Safari, Chrome or Arc) has a \(host) tab. Open Canvas in your browser and sign in, then try again."
                return
            }
        }
        guard let target = chosen else { return }
        guard let client = makeCanvasClient(auth: .browser(target)) else { return }
        canvasStatusMessage = "Checking Canvas in \(target.displayName)..."
        do {
            let me = try await client.get("/api/v1/users/self") as? [String: Any]
            canvasUserName = (me?["short_name"] as? String) ?? (me?["name"] as? String) ?? ""
            preferences.canvasBrowser = target
            try? keychainService.deleteCredential(key: Self.kCanvasCookies)
            try? keychainService.deleteCredential(key: Self.kCanvasToken)
            isCanvasConnected = true
            canvasStatusMessage = "Connected through \(target.displayName)\(canvasUserName.isEmpty ? "" : " as \(canvasUserName)"). Keep a Canvas tab open there when you sync."
            saveDatabase()
        } catch let error as CanvasError {
            canvasStatusMessage = nil
            if error.kind == .signInRequired {
                canvasErrorMessage = "The Canvas tab in \(target.displayName) isn't signed in. Sign in there, then try again."
            } else if error.message.contains("JavaScript from Apple Events") {
                canvasErrorMessage = error.message + " " + target.enableJavaScriptHint
            } else {
                canvasErrorMessage = error.message
            }
        } catch {
            canvasStatusMessage = nil
            canvasErrorMessage = error.localizedDescription
        }
    }

    /// Forgets the Canvas login. Tasks already imported are kept.
    public func disconnectCanvas() {
        try? keychainService.deleteCredential(key: Self.kCanvasCookies)
        try? keychainService.deleteCredential(key: Self.kCanvasToken)
        if preferences.canvasBrowser != nil {
            preferences.canvasBrowser = nil
            saveDatabase()
        }
        isCanvasConnected = false
        canvasUserName = ""
        canvasStatusMessage = nil
    }

    // MARK: - Sync

    public func cancelCanvasSync() {
        if isSyncingCanvas { isCanvasSyncCancelled = true }
    }

    /// Reads Canvas and updates tasks and course events.
    public func syncCanvas(now: Date = Date()) async {
        let tracking = beginNewTaskTracking()
        defer { endNewTaskTracking(tracking) }
        guard !isSyncingCanvas else { return }
        guard let auth = canvasAuth(), let client = makeCanvasClient(auth: auth) else {
            canvasErrorMessage = "Canvas isn't connected. Connect it in Settings."
            return
        }
        isSyncingCanvas = true
        isCanvasSyncCancelled = false
        canvasErrorMessage = nil
        canvasStatusMessage = "Reading Canvas..."
        defer { isSyncingCanvas = false }

        let snapshot: CanvasSnapshot
        do {
            snapshot = try await canvasReader.readEverything(client: client, now: now)
        } catch let error as CanvasError where error.kind == .signInRequired {
            if let browser = preferences.canvasBrowser {
                // The browser holds the sign-in: just ask the user to sign in there again.
                canvasErrorMessage = "The Canvas tab in \(browser.displayName) is signed out. Sign in to Canvas there, then sync again."
            } else {
                isCanvasConnected = false
                canvasErrorMessage = error.message
            }
            canvasStatusMessage = nil
            return
        } catch let error as CanvasError where error.message.contains("JavaScript from Apple Events") {
            canvasErrorMessage = error.message + " " + (preferences.canvasBrowser?.enableJavaScriptHint ?? "")
            canvasStatusMessage = nil
            return
        } catch {
            canvasErrorMessage = "Canvas sync failed: \(error.localizedDescription)"
            canvasStatusMessage = nil
            return
        }
        if !snapshot.userName.isEmpty { canvasUserName = snapshot.userName }

        let counts = importCanvasDueItems(snapshot.dueItems, now: now)
        let eventCount = importCanvasEvents(snapshot.events, now: now)
        recalculateSchedule()
        saveDatabase()

        let (analyzed, fromText, stoppedReason) = await analyzeCanvasText(snapshot.textItems)
        let estimated = await estimateLMSTaskTimes(now: now)

        lastCanvasSyncDate = now
        preferences.lastCanvasSyncDate = now
        recalculateSchedule()
        saveDatabase()

        var parts = ["\(counts.created) new task\(counts.created == 1 ? "" : "s")"]
        if counts.updated > 0 { parts.append("\(counts.updated) due date\(counts.updated == 1 ? "" : "s") updated") }
        if counts.completed > 0 { parts.append("\(counts.completed) marked done (submitted)") }
        if fromText > 0 { parts.append("\(fromText) from announcements/messages") }
        parts.append("\(analyzed) new item\(analyzed == 1 ? "" : "s") read")
        if eventCount > 0 { parts.append("\(eventCount) course event\(eventCount == 1 ? "" : "s")") }
        if estimated > 0 { parts.append("\(estimated) time estimate\(estimated == 1 ? "" : "s") from AI") }
        canvasStatusMessage = "Canvas: " + parts.joined(separator: ", ") + "."
        var problems = snapshot.problems
        if let reason = stoppedReason { problems.insert(reason, at: 0) }
        canvasErrorMessage = problems.isEmpty ? nil : problems.joined(separator: "\n")
    }

    // MARK: Due items → tasks

    struct CanvasImportCounts { var created = 0; var updated = 0; var completed = 0 }

    func importCanvasDueItems(_ items: [CanvasDueItem], now: Date, from service: EmailCategory = .canvas) -> CanvasImportCounts {
        let serviceName = service == .gradescope ? "Gradescope" : "Canvas"
        var counts = CanvasImportCounts()
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        df.timeZone = preferences.timeZone

        for item in items {
            let sourceId = service == .gradescope ? item.key : "canvas-\(item.key)"
            if clearedDismissedTasks.contains(where: { $0.sourceEmailId == sourceId }) { continue }

            if let idx = tasks.firstIndex(where: { $0.sourceEmail.id == sourceId }) {
                let task = tasks[idx]
                // Keep the page link current (older tasks were saved without one).
                if let link = Self.absoluteLink(item.htmlURL, service: service, canvasBase: canvasBaseURL),
                   task.sourceEmail.webLink != link {
                    tasks[idx].sourceEmail.webLink = link
                }
                // Instructions, rubric and attached files can change or be added later; a change means a new estimate.
                if let details = Self.assignmentDetails(for: item), details != task.assignmentDetails {
                    tasks[idx].assignmentDetails = details
                }
                guard task.status != .dismissed else { continue }
                if item.isSubmitted && task.status != .completed {
                    completeTask(taskId: task.id) // same as checking it off by hand
                    counts.completed += 1
                    appendLog(EmailProcessingLog(emailId: sourceId, sender: serviceName, subject: item.title, timestamp: now, action: .taskUpdated,
                                                 explanation: "Submitted in \(serviceName): marked '\(item.title)' done.", extractedTaskId: task.id))
                    continue
                }
                if let due = item.dueAt, task.userOverriddenDeadline == nil, task.status != .completed,
                   abs((task.extractedDeadline ?? .distantPast).timeIntervalSince(due)) > 60 {
                    tasks[idx].extractedDeadline = due
                    tasks[idx].originalDeadlineWording = df.string(from: due)
                    tasks[idx].deadlineUpdateNote = "Due date changed in \(serviceName) to \(df.string(from: due))"
                    tasks[idx].updatedAt = now
                    tasks[idx].syncUpdate = TaskSyncUpdate(date: now, summary: "Due date moved to \(df.string(from: due))", source: serviceName)
                    counts.updated += 1
                    appendLog(EmailProcessingLog(emailId: sourceId, sender: serviceName, subject: item.title, timestamp: now, action: .taskUpdated,
                                                 explanation: "\(serviceName) due date changed to \(df.string(from: due)).", extractedTaskId: task.id))
                }
                continue
            }

            // New item: only if it still needs doing and isn't long past.
            guard !item.isSubmitted, let due = item.dueAt else { continue }
            guard due >= now.addingTimeInterval(-86400) || item.isMissing else { continue }
            // Never bring back something the user dismissed and cleared, under any source.
            if TaskMemory.matchesDismissed(title: item.title, in: clearedDismissedTasks) { continue }
            // The same assignment is often posted on both Canvas and Gradescope: keep one task.
            if let twin = Self.matchingTask(for: item, due: due, in: tasks.filter { $0.sourceEmail.category != service }) {
                appendLog(EmailProcessingLog(emailId: sourceId, sender: serviceName, subject: item.title, timestamp: now, action: .taskUpdated,
                                             explanation: "Already tracked as '\(twin.title)' (same assignment in \(twin.sourceEmail.category.rawValue)).", extractedTaskId: twin.id))
                continue
            }
            // Task memory: already found elsewhere (e.g. from an email)? Update that task instead.
            if let idx = TaskMemory.findMatch(title: item.title, deadline: due, in: tasks) {
                var existing = tasks[idx]
                let changes = TaskMemory.merge(into: &existing, deadline: due, details: "", source: serviceName, now: now, timeZone: preferences.timeZone)
                if !changes.isEmpty {
                    tasks[idx] = existing
                    counts.updated += 1
                }
                appendLog(EmailProcessingLog(emailId: sourceId, sender: serviceName, subject: item.title, timestamp: now, action: .taskUpdated,
                                             explanation: changes.isEmpty ? "Already tracked as '\(existing.displayTitle)'."
                                                : "Updated existing task '\(existing.displayTitle)': \(changes.joined(separator: "; ")).",
                                             extractedTaskId: existing.id))
                continue
            }

            let task = Self.makeCanvasTask(item, sourceId: sourceId, due: due, dueText: df.string(from: due), now: now, category: service, canvasBase: canvasBaseURL)
            tasks.append(task)
            counts.created += 1
            appendLog(EmailProcessingLog(emailId: sourceId, sender: item.courseName.isEmpty ? "Canvas" : item.courseName, subject: item.title, timestamp: now,
                                         action: .taskCreated, explanation: "Imported from \(serviceName): due \(df.string(from: due)).", extractedTaskId: task.id))
        }
        return counts
    }

    /// An existing (not dismissed) Canvas or Gradescope task that is clearly the same assignment:
    /// same title once punctuation/case are ignored, or one title containing the other, due within a day.
    static func matchingTask(for item: CanvasDueItem, due: Date, in tasks: [DiscoveredTask]) -> DiscoveredTask? {
        func norm(_ s: String) -> String {
            s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        let title = norm(item.title)
        guard title.count >= 3 else { return nil }
        return tasks.first { task in
            guard [.canvas, .gradescope].contains(task.sourceEmail.category), task.status != .dismissed,
                  let other = task.extractedDeadline, abs(other.timeIntervalSince(due)) <= 86400 else { return false }
            let t = norm(task.title)
            return t == title || (t.count >= 6 && title.contains(t)) || (title.count >= 6 && t.contains(title))
        }
    }

    static func makeCanvasTask(_ item: CanvasDueItem, sourceId: String, due: Date, dueText: String, now: Date, category: EmailCategory = .canvas,
                               canvasBase: URL? = nil) -> DiscoveredTask {
        let serviceName = category == .gradescope ? "Gradescope" : "Canvas"
        let action: String
        switch item.kind {
        case "gradescope": action = "Submit on Gradescope"
        case "quiz": action = "Complete quiz"
        case "discussion_topic": action = "Post in discussion"
        case "wiki_page": action = "Review page"
        case "planner_note": action = "To-do"
        default: action = "Submit assignment"
        }
        var notes: [String] = []
        if !item.courseName.isEmpty { notes.append("Course: \(item.courseName)") }
        if let points = item.pointsPossible, points > 0 { notes.append("Points: \(points.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(points)) : String(points))") }
        if item.isMissing { notes.append("\(serviceName) marks this as missing.") }
        if let url = Self.absoluteLink(item.htmlURL, service: category, canvasBase: canvasBase) { notes.append(url) }
        if !item.descriptionText.isEmpty { notes.append("\n" + String(item.descriptionText.prefix(2000))) }

        let source = EmailSource(
            id: sourceId,
            threadId: sourceId,
            senderName: item.courseName.isEmpty ? serviceName : item.courseName,
            senderEmail: category == .gradescope ? "gradescope@local" : "canvas@local",
            subject: item.title,
            receivedDate: now,
            snippet: "\(action), due \(dueText).",
            fullBody: item.descriptionText,
            category: category,
            isSimulatedDemo: false,
            webLink: Self.absoluteLink(item.htmlURL, service: category, canvasBase: canvasBase)
        )
        var task = DiscoveredTask(
            title: item.title,
            requiredAction: "\(action): \(item.title)",
            notes: notes.joined(separator: "\n"),
            sourceEmail: source,
            extractedDeadline: due,
            isDeadlineSupportedByEmail: true,
            supportingExcerpt: "Due \(dueText) in \(serviceName)\(item.courseName.isEmpty ? "" : " (\(item.courseName))").",
            estimatedMinutes: estimateCanvasMinutes(item),
            status: .ready,
            isClarified: true,
            userPriority: item.isMissing ? .high : .medium,
            originalDeadlineWording: dueText,
            timeZoneAssumption: "\(serviceName) due time",
            createdAt: now,
            updatedAt: now
        )
        task.assignmentDetails = assignmentDetails(for: item)
        return task
    }

    /// Everything Canvas says about what the assignment asks for, for the time estimate.
    /// Nil when there's nothing beyond the title.
    static func assignmentDetails(for item: CanvasDueItem) -> String? {
        var parts: [String] = []
        if !item.descriptionText.isEmpty { parts.append("Instructions:\n" + String(item.descriptionText.prefix(4000))) }
        let handIn = item.submissionTypes.map { $0.replacingOccurrences(of: "online_", with: "").replacingOccurrences(of: "_", with: " ") }
        if !handIn.isEmpty { parts.append("Handed in as: " + handIn.joined(separator: ", ")) }
        if !item.rubricText.isEmpty { parts.append("Rubric:\n" + String(item.rubricText.prefix(1500))) }
        if !item.attachmentText.isEmpty { parts.append(item.attachmentText) }
        if !item.unreadableAttachments.isEmpty {
            parts.append("Attached files that couldn't be read: " + item.unreadableAttachments.joined(separator: ", "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// Rough work estimate from the item type, title and instructions (adjustable on the task).
    static func estimateCanvasMinutes(_ item: CanvasDueItem) -> Int {
        ruleOfThumbMinutes(title: item.title, kind: item.kind, points: item.pointsPossible, instructionLength: item.descriptionText.count)
    }

    /// The built-in estimate: also the floor for an AI estimate made from a title alone.
    static func ruleOfThumbMinutes(title rawTitle: String, kind: String, points: Double?, instructionLength: Int) -> Int {
        let title = rawTitle.lowercased()
        if ["exam", "midterm", "final exam"].contains(where: { title.contains($0) }) { return 180 }
        if ["project", "paper", "essay", "report", "presentation"].contains(where: { title.contains($0) }) { return 240 }
        switch kind {
        case "quiz": return 45
        case "discussion_topic", "wiki_page", "planner_note": return 30
        default:
            if (points ?? 0) >= 50 || instructionLength > 1500 { return 180 }
            return 90
        }
    }

    // MARK: Course events → timeline

    func importCanvasEvents(_ events: [CanvasEvent], now: Date) -> Int {
        // Replace upcoming Canvas events each sync (they're re-read in full); past ones stay as history.
        commitments.removeAll { $0.calendarName.hasPrefix(Self.canvasCalendarPrefix) && $0.isLocalOnly && $0.endTime >= now }
        for event in events where event.end >= now {
            commitments.append(CalendarCommitment(
                id: Self.stableUUID("canvas-\(event.key)"),
                title: event.title,
                location: event.location,
                startTime: event.start,
                endTime: event.end,
                isAllDay: event.isAllDay,
                isBusy: !event.isAllDay,
                calendarName: Self.canvasCalendarPrefix + (event.courseName.isEmpty ? "Canvas" : event.courseName),
                colorHex: "#E13B30"
            ))
        }
        return events.filter { $0.end >= now }.count
    }

    static func stableUUID(_ text: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: Free text → tasks (local model)

    /// Returns (items analyzed, tasks created, reason analysis stopped early).
    func analyzeCanvasText(_ items: [CanvasTextItem]) async -> (Int, Int, String?) {
        // Newest first, so the most relevant items are read first on a long first sync.
        let pending = items
            .filter { !$0.body.isEmpty && extractionCache[Self.canvasCacheId($0)] == nil }
            .sorted { $0.postedAt > $1.postedAt }
        var analyzed = 0
        var created = 0
        for (index, item) in pending.enumerated() {
            if isCanvasSyncCancelled { return (analyzed, created, "Canvas sync was cancelled; the rest will be read next time.") }
            canvasStatusMessage = "Reading Canvas \(item.kind.lowercased()) \(index + 1) of \(pending.count) with \(ollamaModel): \(item.title)..."

            let email = Self.canvasEmailSource(for: item, canvasBase: canvasBaseURL)
            let courseTasks = tasks.filter { $0.sourceEmail.category == .canvas && $0.sourceEmail.senderName == email.senderName && $0.status != .dismissed }
            do {
                let analysis = try await ollamaService.analyzeEmail(
                    email: email,
                    threadContext: [],
                    existingTasks: courseTasks,
                    baseURL: ollamaBaseURL,
                    model: ollamaModel,
                    timeZone: preferences.timeZone,
                    checkCancellation: { [weak self] in self?.isCanvasSyncCancelled == true },
                    onRetry: nil
                )
                // Task memory in applyAnalysis updates the matching task (e.g. the Canvas assignment an
                // announcement is about) instead of adding a duplicate.
                extractionCache[email.id] = CachedEmailExtraction(
                    emailId: email.id, emailSubject: email.subject, senderEmail: email.senderEmail,
                    receivedDate: email.receivedDate, analyzedDate: Date(), modelUsed: ollamaModel, analysis: analysis)
                var d = 0, u = 0, n = 0, r = 0
                applyAnalysis(analysis, for: email, discoveredCount: &d, updatedCount: &u, newslettersFiltered: &n, nonRecipientFiltered: &r)
                created += d
                analyzed += 1
                saveDatabase()
            } catch is CancellationError {
                return (analyzed, created, "Canvas sync was cancelled; the rest will be read next time.")
            } catch let error as AIServiceError where error.isFatalForScan {
                return (analyzed, created, "Couldn't read Canvas announcements and messages: \(error.message)")
            } catch {
                // Not cached, so it's retried on the next sync.
                continue
            }
        }
        return (analyzed, created, nil)
    }

    static func canvasCacheId(_ item: CanvasTextItem) -> String { "canvas-\(item.key)@\(item.version)" }

    /// Full page address for a Canvas/Gradescope link that may be saved as a path.
    static func absoluteLink(_ link: String?, service: EmailCategory, canvasBase: URL?) -> String? {
        let base = service == .gradescope ? URL(string: "https://www.gradescope.com") : canvasBase
        return TaskSourceLink.resolve(link, base: base)?.absoluteString
    }

    static func canvasEmailSource(for item: CanvasTextItem, canvasBase: URL? = nil) -> EmailSource {
        let header = [item.kind, item.courseName.isEmpty ? nil : "Course: \(item.courseName)", item.author.isEmpty ? nil : "From: \(item.author)"]
            .compactMap { $0 }.joined(separator: " · ")
        return EmailSource(
            id: canvasCacheId(item),
            threadId: "canvas-\(item.key)",
            senderName: item.courseName.isEmpty ? "Canvas" : item.courseName,
            senderEmail: "canvas@local",
            subject: "[Canvas \(item.kind)] \(item.title)",
            receivedDate: item.postedAt,
            snippet: String(item.body.prefix(200)),
            fullBody: header + "\n\n" + item.body,
            category: .canvas,
            isSimulatedDemo: false,
            webLink: absoluteLink(item.htmlURL, service: .canvas, canvasBase: canvasBase)
        )
    }
}
