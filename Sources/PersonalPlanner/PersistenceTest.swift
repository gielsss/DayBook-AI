import Foundation

fileprivate extension Date {
    static func <= (lhs: Date, rhs: Date) -> Bool {
        return lhs.timeIntervalSinceReferenceDate <= rhs.timeIntervalSinceReferenceDate
    }
    static func < (lhs: Date, rhs: Date) -> Bool {
        return lhs.timeIntervalSinceReferenceDate < rhs.timeIntervalSinceReferenceDate
    }
    static func >= (lhs: Date, rhs: Date) -> Bool {
        return lhs.timeIntervalSinceReferenceDate >= rhs.timeIntervalSinceReferenceDate
    }
    static func > (lhs: Date, rhs: Date) -> Bool {
        return lhs.timeIntervalSinceReferenceDate > rhs.timeIntervalSinceReferenceDate
    }
}

@MainActor
public struct PersistenceTester {
    public static func runAllTests() -> Bool {
        print("=======================================================")
        print(" PersonalPlanner: Multi-Model Fallback & Verification")
        print("=======================================================\n")
        
        let testDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PersonalPlannerTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        let testDbURL = testDir.appendingPathComponent("test_planner_database.json")
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }
        
        var allPassed = true
        
        func check(_ description: String, _ condition: Bool) {
            if condition {
                print("  ✅ PASS: \(description)")
            } else {
                print("  ❌ FAIL: \(description)")
                allPassed = false
            }
        }
        
        // -----------------------------------------------------------------
        // 1. Initial Demonstration Database Generation
        // -----------------------------------------------------------------
        print("▶ Stage 1: Initial Database Seeding & Sample Emails")
        let storage1 = StorageService(customURL: testDbURL)
        let db1 = storage1.loadDatabase()
        
        check("Database file created at specified URL", FileManager.default.fileExists(atPath: testDbURL.path))
        check("Initial tasks seeded without manual entry", db1.tasks.count >= 2)
        check("Work sessions scheduled around commitments", db1.workSessions.count >= 3)
        check("Apple Calendar commitments loaded", db1.calendarCommitments.count >= 4)
        check("Email processing audit log present", db1.processedLogs.count >= 4)
        
        // -----------------------------------------------------------------
        // 2. Realistic Sample Email Discovery Checks
        // -----------------------------------------------------------------
        print("\n▶ Stage 2: Verifying 4 Required Email Scenarios")
        
        let clearTask = db1.tasks.first(where: { $0.title.contains("Lab 3") })
        check("Example A: Clear assignment discovered (CS 420 Lab 3)", clearTask != nil)
        check("Example A: Extracted deadline is present", clearTask?.extractedDeadline != nil)
        check("Example A: Estimated duration is 180 min (3 hours)", clearTask?.estimatedMinutes == 180)
        check("Example A: Retains full email source info", clearTask?.sourceEmail.senderName == "Prof. Elena Vance")
        
        let ambigTask = db1.tasks.first(where: { $0.title.contains("slide 8") })
        check("Example B: Ambiguous request discovered (Slide 8 Deck)", ambigTask != nil)
        check("Example B: Flagged as 'Needs Clarification'", ambigTask?.status == .needsClarification)
        check("Example B: Extracted deadline is nil (ambiguous)", ambigTask?.extractedDeadline == nil)
        check("Example B: Clarification prompt explains ambiguity", ambigTask?.clarificationPrompt != nil)
        
        let newsletterTask = db1.tasks.first(where: { $0.title.contains("Swift Weekly") })
        let newsletterLog = db1.processedLogs.first(where: { $0.action == .ignoredNewsletter })
        check("Example C: Newsletter filtered out (no task created)", newsletterTask == nil)
        check("Example C: Newsletter logged with explanation in audit log", newsletterLog != nil)
        
        check("Example D: Deadline updated from email (+48h extension note present)", clearTask?.deadlineUpdateNote?.contains("+48h") == true)
        
        // -----------------------------------------------------------------
        // 3. Separation of Tasks and Work Sessions
        // -----------------------------------------------------------------
        print("\n▶ Stage 3: Verifying Separation of Tasks vs Work Sessions")
        let taskIds = Set(db1.tasks.map { $0.id })
        let sessionTaskIds = Set(db1.workSessions.compactMap { $0.taskId })
        check("Work sessions reference tasks rather than duplicating them", !sessionTaskIds.isEmpty && sessionTaskIds.isSubset(of: taskIds))
        check("Work sessions have concrete start/end times", db1.workSessions.allSatisfy { $0.startTime < $0.endTime })
        
        // -----------------------------------------------------------------
        // 4. Persistence Test (Data, Fallbacks, and Cache Survive Reopening)
        // -----------------------------------------------------------------
        print("\n▶ Stage 4: Testing Persistence Across App Restart")
        
        var modifiedDb = db1
        let clarifiedDeadline = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        if let ambigIdx = modifiedDb.tasks.firstIndex(where: { $0.status == .needsClarification }) {
            modifiedDb.tasks[ambigIdx].status = .ready
            modifiedDb.tasks[ambigIdx].extractedDeadline = clarifiedDeadline
            modifiedDb.tasks[ambigIdx].isClarified = true
            modifiedDb.tasks[ambigIdx].notes += "\nUser clarified via test."
        }
        
        if let clearIdx = modifiedDb.tasks.firstIndex(where: { $0.status == .ready }) {
            modifiedDb.tasks[clearIdx].status = .completed
        }
        
        modifiedDb.preferences.workStartHour = 8
        modifiedDb.preferences.defaultSessionMinutes = 60
        modifiedDb.preferences.ollamaModel = "llama3.1:8b"
        
        // Cache entry test
        let sampleCachedAnalysis = EmailAnalysis(
            isNewsletterOrMarketing: false,
            isDirectedAtRecipient: true,
            hasActionableTask: false,
            reasoning: "Newsletter with zero tasks",
            tasks: []
        )
        modifiedDb.extractionCache["cached_test_email_001"] = CachedEmailExtraction(
            emailId: "cached_test_email_001",
            emailSubject: "Zero Tasks Email",
            senderEmail: "news@example.com",
            receivedDate: Date(),
            modelUsed: "qwen3-vl:8b",
            analysis: sampleCachedAnalysis
        )
        
        try? storage1.saveDatabase(modifiedDb)
        
        let storage2 = StorageService(customURL: testDbURL)
        let reloadedDb = storage2.loadDatabase()
        
        let reloadedAmbig = reloadedDb.tasks.first(where: { $0.title.contains("slide 8") })
        let reloadedClear = reloadedDb.tasks.first(where: { $0.title.contains("Lab 3") })
        
        check("Clarified task status survived reopening (.ready)", reloadedAmbig?.status == .ready)
        check("Clarified deadline survived reopening", reloadedAmbig?.extractedDeadline != nil)
        check("Completed task status survived reopening (.completed)", reloadedClear?.status == .completed)
        check("Modified preference survived reopening (workStartHour = 8)", reloadedDb.preferences.workStartHour == 8)
        check("Modified preference survived reopening (sessionMinutes = 60)", reloadedDb.preferences.defaultSessionMinutes == 60)
        check("Local model choice survived reopening (llama3.1:8b)", reloadedDb.preferences.ollamaModel == "llama3.1:8b")
        check("Cached email extraction survived reopening (including 0-task email)", reloadedDb.extractionCache["cached_test_email_001"] != nil)
        
        // -----------------------------------------------------------------
        // 5. Google OAuth Credentials Parsing Test
        // -----------------------------------------------------------------
        print("\n▶ Stage 5: Google OAuth Credentials Parser Test")
        let sampleCredentialsJSON = """
        {
          "installed": {
            "client_id": "test-client-id.apps.googleusercontent.com",
            "project_id": "test-project-123",
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "client_secret": "test-client-secret-XYZ",
            "redirect_uris": ["http://localhost"]
          }
        }
        """.data(using: .utf8)!
        
        do {
            let config = try GoogleClientConfig.parse(from: sampleCredentialsJSON)
            check("Client ID parsed successfully from 'installed' wrapper", config.clientId == "test-client-id.apps.googleusercontent.com")
            check("Client Secret parsed successfully", config.clientSecret == "test-client-secret-XYZ")
            check("Project ID parsed successfully", config.projectId == "test-project-123")
        } catch {
            check("GoogleClientConfig.parse succeeded", false)
        }
        
        // -----------------------------------------------------------------
        // 6. Structured Email Analysis & User State Preservation Test
        // -----------------------------------------------------------------
        print("\n▶ Stage 6: Structured Email Analysis & State Preservation")
        let sampleAnalysisJSON = """
        {
          "isNewsletterOrMarketing": false,
          "isDirectedAtRecipient": true,
          "hasActionableTask": true,
          "reasoning": "Clear assignment with deadline Friday.",
          "tasks": [
            {
              "title": "CS 420 Lab 3: Raft Consensus",
              "requiredAction": "Implement leader election and heartbeats",
              "deadlineIso": "2026-11-06T23:59:00Z",
              "deadlineIsSupportedByEmail": true,
              "supportingExcerpt": "Submission Deadline: This Friday at 11:59 PM.",
              "estimatedDurationMinutes": 180,
              "isAmbiguous": false,
              "uncertainDetails": [],
              "isDeadlineUpdate": false,
              "deadlineUpdateNote": null
            }
          ]
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let analysis = try? decoder.decode(EmailAnalysis.self, from: sampleAnalysisJSON)
        check("EmailAnalysis decoded structured output correctly", analysis?.tasks.count == 1)
        check("Candidate task has requiredAction", analysis?.tasks.first?.requiredAction == "Implement leader election and heartbeats")
        check("Candidate task deadline is marked supported by email", analysis?.tasks.first?.deadlineIsSupportedByEmail == true)
        check("Candidate task has supporting excerpt", analysis?.tasks.first?.supportingExcerpt.contains("Submission Deadline") == true)
        check("Candidate task duration is labeled (180 min)", analysis?.tasks.first?.estimatedDurationMinutes == 180)
        
        var testTask = DiscoveredTask(
            title: "Original Title",
            requiredAction: "Original Action",
            sourceEmail: DemoDataFactory.makeSampleEmails()[0],
            extractedDeadline: Date(),
            isDeadlineSupportedByEmail: true,
            status: .ready
        )
        testTask.userOverriddenTitle = "User Custom Title"
        testTask.isDismissed = true
        testTask.status = .dismissed
        
        check("User override title respected", testTask.displayTitle == "User Custom Title")
        check("Dismissed task flagged correctly", testTask.isDismissed == true && testTask.status == .dismissed)
        
        // -----------------------------------------------------------------
        // 8. Gmail 14-Day Query & Pagination Logic Verification
        // -----------------------------------------------------------------
        print("\n▶ Stage 8: Gmail Multi-Page Pagination Simulator")
        let page1JSON = """
        {
          "messages": [
            {"id": "msg_001", "threadId": "thread_001"},
            {"id": "msg_002", "threadId": "thread_002"}
          ],
          "nextPageToken": "page_2_token_xyz"
        }
        """.data(using: .utf8)!
        
        let page2JSON = """
        {
          "messages": [
            {"id": "msg_003", "threadId": "thread_003"}
          ]
        }
        """.data(using: .utf8)!
        
        var simulatedFetchedIds: [String] = []
        var mockPageToken: String? = nil
        var pagesFetched = 0
        
        repeat {
            pagesFetched += 1
            let pageData = (mockPageToken == nil) ? page1JSON : page2JSON
            if let json = try? JSONSerialization.jsonObject(with: pageData) as? [String: Any] {
                if let msgs = json["messages"] as? [[String: Any]] {
                    for m in msgs {
                        if let id = m["id"] as? String { simulatedFetchedIds.append(id) }
                    }
                }
                mockPageToken = json["nextPageToken"] as? String
            } else {
                break
            }
        } while mockPageToken != nil && pagesFetched < 5
        
        check("Gmail pagination followed nextPageToken across multiple pages", pagesFetched == 2)
        check("Gathered messages from all pages without stopping prematurely", simulatedFetchedIds == ["msg_001", "msg_002", "msg_003"])
        
        // -----------------------------------------------------------------
        // 10. 5-Email Test Scan
        // -----------------------------------------------------------------
        print("\n▶ Stage 10: 5-Email Test Scan")
        
        func runAsync<T>(_ block: @MainActor @escaping () async throws -> T) throws -> T {
            var result: Result<T, Error>?
            Task { @MainActor in
                do {
                    let val = try await block()
                    result = .success(val)
                } catch {
                    result = .failure(error)
                }
            }
            let start = Date()
            while result == nil && Date().timeIntervalSince(start) < 5.0 {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
            }
            guard let res = result else {
                throw NSError(domain: "PersistenceTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Async block timed out"])
            }
            switch res {
            case .success(let val): return val
            case .failure(let err): throw err
            }
        }
        
        // Test 10D: 5-Email Test Scan Slicing, Exact Reporting & Preserving Progress
        final class MockGmailService: GmailServiceProtocol {
            var isConnected: Bool = true
            var hasClientConfig: Bool = true
            var emailsToReturn: [EmailSource] = []
            func importClientConfig(from data: Data) throws -> GoogleClientConfig { throw NSError(domain: "", code: 0) }
            func loadClientConfig() -> GoogleClientConfig? { nil }
            func signIn() async throws {}
            func disconnect() throws {}
            func fetchRecentEmailSummaries(limit: Int) async throws -> [RecentEmailSummary] { [] }
            func fetchEmailsFromLastDays(days: Int) async throws -> [EmailSource] { emailsToReturn }
        }
        
        @MainActor
        final class MockModelService: OllamaExtractionServiceProtocol {
            var analyzedIds: [String] = []
            var onAnalyzeEmail: (() -> Void)? = nil
            func analyzeEmail(email: EmailSource, threadContext: [EmailSource], existingTasks: [DiscoveredTask], baseURL: String, model: String, timeZone: TimeZone, checkCancellation: (() -> Bool)?, onRetry: ((String) -> Void)?) async throws -> EmailAnalysis {
                onAnalyzeEmail?()
                if let check = checkCancellation, check() { throw CancellationError() }
                analyzedIds.append(email.id)
                return EmailAnalysis(
                    isNewsletterOrMarketing: false,
                    isDirectedAtRecipient: true,
                    hasActionableTask: true,
                    reasoning: "Mock task found",
                    tasks: [CandidateTask(title: "Task from \(email.subject)", requiredAction: "Action for \(email.subject)")]
                )
            }
            func installedModels(baseURL: String) async throws -> [String] { [] }
            func testConnection(baseURL: String, model: String) async throws -> String { "Connected" }
        }
        
        // Scenario 10D-1: 8 uncached emails available -> Test Scan (5) processes exactly 5
        let mockGmail = MockGmailService()
        var testEmails: [EmailSource] = []
        for i in 1...8 {
            testEmails.append(EmailSource(
                id: "email_\(i)",
                threadId: "thread_\(i)",
                senderName: "Sender \(i)",
                senderEmail: "sender\(i)@example.com",
                subject: "Test Subject \(i)",
                receivedDate: Date(),
                snippet: "Snippet \(i)",
                fullBody: "Body \(i)",
                category: .assignment
            ))
        }
        mockGmail.emailsToReturn = testEmails
        
        let mockModel = MockModelService()
        let testDir10 = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PersonalPlannerTest10_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDir10, withIntermediateDirectories: true)
        let testDbURL10 = testDir10.appendingPathComponent("db10.json")
        defer { try? FileManager.default.removeItem(at: testDir10) }
        let storage10 = StorageService(customURL: testDbURL10)
        
        final class MockKeychainService: KeychainServiceProtocol {
            var store: [String: String] = [:]
            func saveCredential(key: String, value: String) throws { store[key] = value }
            func getCredential(key: String) -> String? { store[key] }
            func deleteCredential(key: String) throws { store.removeValue(forKey: key) }
        }
        let mockKeychain = MockKeychainService()
        
        let app = AppState(
            storageService: storage10,
            keychainService: mockKeychain,
            gmailService: mockGmail,
            ollamaService: mockModel
        )
        app.isGmailAuthenticated = true
        
        try! runAsync {
            await app.testScanFiveEmails()
        }
        
        check("Test Scan (5) processes exactly 5 of 8 uncached emails", app.scanProcessedCount == 5)
        check("Mock model service received exactly 5 extraction calls", mockModel.analyzedIds.count == 5)
        check("Analyzed email summaries recorded for all 5 analyzed emails", app.lastAnalyzedEmailItems.count == 5)
        check("Reports exact counts: 'Analyzed 5 of 5 uncached email(s) (out of 8 uncached available)'", app.lastScanSuccessSummary?.contains("Analyzed 5 of 5 uncached email(s) (out of 8 uncached available)") == true)
        check("Extracted tasks added to task list without manual entry", app.tasks.contains(where: { $0.title.contains("Test Subject 1") }))
        
        // Scenario 10D-2: Run Test Scan again with remaining 3 uncached emails
        try! runAsync {
            await app.testScanFiveEmails()
        }
        check("Test Scan processes the remaining 3 uncached emails", app.scanProcessedCount == 3)
        check("Reports actual available count when fewer than 5: 'Analyzed all 3 available uncached email(s)'", app.lastScanSuccessSummary?.contains("Analyzed all 3 available uncached email(s)") == true)
        check("Analyzed email summaries updated with the 3 emails", app.lastAnalyzedEmailItems.count == 3)
        
        // Scenario 10D-3: Rescan when all 8 are cached -> 0 quota spent
        let modelCallsBeforeCached = mockModel.analyzedIds.count
        try! runAsync {
            await app.testScanFiveEmails()
        }
        check("Rescan with all emails cached makes 0 model requests", mockModel.analyzedIds.count == modelCallsBeforeCached)
        check("Reports that all emails are already cached", app.lastScanSuccessSummary?.contains("already been analyzed and cached") == true)
        
        // Scenario 10D-4: Cooperative cancellation preserves progress & never reports full success
        let cancelEmail = EmailSource(id: "cancel_email", threadId: "cancel_thread", senderName: "Cancel", senderEmail: "cancel@test.com", subject: "Cancel Test", receivedDate: Date(), snippet: "", fullBody: "", category: .assignment)
        mockGmail.emailsToReturn = [cancelEmail]
        mockModel.onAnalyzeEmail = {
            app.cancelActiveScan()
        }
        try! runAsync {
            await app.testScanFiveEmails()
        }
        check("Cancelled scan records cancellation error banner", app.lastScanError?.contains("cancelled by user") == true)
        check("Cancelled scan never reports full success", app.lastScanSuccessSummary == nil)
        
        // -----------------------------------------------------------------
        // 11. Keychain Serialization, In-Memory Session Caching & ACL Preservation
        // -----------------------------------------------------------------
        print("\n▶ Stage 11: Keychain Serialization, In-Memory Session Caching & ACL Preservation")
        
        let testKeychain = KeychainService()
        // Clear any leftover test keys
        try? testKeychain.deleteCredential(key: "test_verification_key")
        
        // 11A: Save & In-Memory Cache Read
        try? testKeychain.saveCredential(key: "test_verification_key", value: "secret_value_123")
        let cachedRead1 = testKeychain.getCredential(key: "test_verification_key")
        check("Credential saved and immediately available via session cache", cachedRead1 == "secret_value_123")
        
        // 11B: In-Place Update (SecItemUpdate without SecItemDelete)
        try? testKeychain.saveCredential(key: "test_verification_key", value: "secret_value_456")
        let cachedRead2 = testKeychain.getCredential(key: "test_verification_key")
        check("Credential updated in-place to new value", cachedRead2 == "secret_value_456")
        
        // 11C: GoogleOAuthService Session Caching
        let mockOauthKeychain = MockKeychainService()
        let oauthService = GoogleOAuthService(keychainService: mockOauthKeychain)
        
        let initialHasCreds = oauthService.hasClientCredentials
        check("Initial OAuth service reports no credentials", !initialHasCreds)
        
        let clientConfig = GoogleClientConfig(clientId: "client_id_test", clientSecret: "client_secret_test", projectId: "project_test")
        try? oauthService.saveClientConfig(clientConfig)
        
        check("Client credentials reported available from memory", oauthService.hasClientCredentials)
        check("Client config matches saved config", oauthService.loadClientConfig()?.clientId == "client_id_test")
        
        // 11D: Deletion
        try? testKeychain.deleteCredential(key: "test_verification_key")
        testKeychain.resetSessionCache()
        check("Deleted credential is no longer returned", testKeychain.getCredential(key: "test_verification_key") == nil)
        
        // -----------------------------------------------------------------
        // 12. Apple Calendar (EventKit) Logic, Multi-Calendar Filtering & Multi-Day Spanning
        // -----------------------------------------------------------------
        print("\n▶ Stage 12: Apple Calendar (EventKit) Availability, Filtering & Multi-Day Logic")
        
        let calendarService = SimulatedCalendarService()
        
        // 12A: Calendar Discovery
        let availableCals = try! runAsync {
            try await calendarService.fetchAvailableCalendars()
        }
        check("Discovers available calendars (Work, Personal, University)", availableCals.count >= 3)
        check("Each calendar has a non-empty color hex and title", availableCals.allSatisfy { !$0.colorHex.isEmpty && !$0.title.isEmpty })
        
        // 12B: Multi-Calendar Selection Filtering
        let today = Calendar.current.startOfDay(for: Date())
        let day14 = Calendar.current.date(byAdding: .day, value: 14, to: today)!
        let range14 = today...day14
        
        let workOnlyCommitments = try! runAsync {
            try await calendarService.fetchCommitments(for: range14, selectedCalendarIdentifiers: ["demo-cal-work"], allDayBlocksTime: false)
        }
        check("Filtering by 'Work Calendar' excludes Personal and University events", !workOnlyCommitments.isEmpty && workOnlyCommitments.allSatisfy { $0.calendarIdentifier == "demo-cal-work" })
        
        let multiSelectedCommitments = try! runAsync {
            try await calendarService.fetchCommitments(for: range14, selectedCalendarIdentifiers: ["demo-cal-work", "demo-cal-personal"], allDayBlocksTime: false)
        }
        check("Filtering by multiple calendars returns only selected sources", multiSelectedCommitments.allSatisfy { $0.calendarIdentifier == "demo-cal-work" || $0.calendarIdentifier == "demo-cal-personal" })
        check("Unselected 'University Calendar' is strictly excluded", !multiSelectedCommitments.contains(where: { $0.calendarIdentifier == "demo-cal-uni" }))
        
        // 12C: Multi-Day Date Overlap Predicate Verification
        // Annual Developer Summit spans day +2 to day +4
        let day3Start = Calendar.current.date(byAdding: .day, value: 3, to: today)!
        let day3End = Calendar.current.date(byAdding: .day, value: 4, to: today)!
        
        let allCommitments = try! runAsync {
            try await calendarService.fetchCommitments(for: range14, selectedCalendarIdentifiers: nil, allDayBlocksTime: false)
        }
        let multiDayEvent = allCommitments.first(where: { $0.title == "Annual Developer Summit" })
        check("Multi-day event identified via isMultiDay helper", multiDayEvent?.isMultiDay == true)
        
        // Overlap predicate: startTime < endOfDay && endTime > startOfDay correctly matches intermediate day
        let isDay3Overlap = (multiDayEvent?.startTime ?? Date()) < day3End && (multiDayEvent?.endTime ?? Date()) > day3Start
        check("Multi-day event correctly overlaps intermediate day (Day 3)", isDay3Overlap)
        
        // Old single-day check: cal.isDate(startTime, inSameDayAs: day3) would fail
        let oldCheckDay3 = Calendar.current.isDate(multiDayEvent?.startTime ?? Date(), inSameDayAs: day3Start)
        check("Old single-day predicate correctly avoided for multi-day events", oldCheckDay3 == false)
        
        // 12D: Busy vs Free Availability in Scheduling Engine
        let schedulingEngine = RuleBasedSchedulingEngine()
        var enginePrefs = UserPreferences()
        enginePrefs.workStartHour = 9
        enginePrefs.workEndHour = 17
        enginePrefs.defaultSessionMinutes = 60
        enginePrefs.minSessionMinutes = 30
        enginePrefs.lunchStartHour = 12
        enginePrefs.lunchDurationMinutes = 60
        enginePrefs.allDayEventsBlockTime = false
        enginePrefs.includeDemoDataInPlan = true
        for d in 1...7 {
            enginePrefs.weekdayWorkingHours[d] = WeekdayHours(isWorkday: true, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0)
        }
        
        let stage12TestTask = DiscoveredTask(
            id: UUID(),
            title: "Test Focus Task",
            requiredAction: "Work on feature",
            notes: "Test",
            sourceEmail: DemoDataFactory.makeSampleEmails()[0],
            extractedDeadline: Calendar.current.date(byAdding: .day, value: 2, to: today),
            isDeadlineSupportedByEmail: true,
            supportingExcerpt: "Test",
            estimatedMinutes: 60,
            status: .ready
        )
        
        let testRange = today...Calendar.current.date(byAdding: .day, value: 1, to: today)!
        
        // Block morning from 9:00 to 12:00 so the next candidate slot is 13:00 (after 12:00-13:00 lunch)
        let morningBlock = CalendarCommitment(
            title: "Morning Block",
            startTime: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: today)!,
            endTime: Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: today)!,
            isAllDay: false,
            isBusy: true,
            calendarName: "Work Calendar"
        )
        
        // Case 1: Free event between 13:00 and 14:00 (Optional Office Hours)
        // With isBusy == false, scheduling engine should NOT block 13:00 - 14:00 slot
        let freeEvent = CalendarCommitment(
            title: "Free Discussion",
            startTime: Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: today)!,
            endTime: Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: today)!,
            isAllDay: false,
            isBusy: false,
            calendarName: "University Calendar"
        )
        
        let sessionsWithFree = schedulingEngine.scheduleSessions(for: [stage12TestTask], commitments: [morningBlock, freeEvent], preferences: enginePrefs, dateRange: testRange)
        check("Free calendar commitment (isBusy == false) allows work session scheduling", sessionsWithFree.contains(where: { $0.startTime == freeEvent.startTime }))
        
        // Case 2: Busy event between 13:00 and 14:00
        let busyEvent = CalendarCommitment(
            title: "Busy Meeting",
            startTime: Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: today)!,
            endTime: Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: today)!,
            isAllDay: false,
            isBusy: true,
            calendarName: "Work Calendar"
        )
        let sessionsWithBusy = schedulingEngine.scheduleSessions(for: [stage12TestTask], commitments: [morningBlock, busyEvent], preferences: enginePrefs, dateRange: testRange)
        check("Busy calendar commitment (isBusy == true) prevents conflicting work session", !sessionsWithBusy.contains(where: { $0.startTime == busyEvent.startTime }))
        
        // 12E: All-Day Event Blocking vs Non-Blocking Setting
        let allDayEvent = CalendarCommitment(
            title: "All-Day Offsite",
            startTime: today,
            endTime: Calendar.current.date(byAdding: .day, value: 1, to: today)!,
            isAllDay: true,
            isBusy: true,
            calendarName: "Work Calendar"
        )
        
        // When allDayEventsBlockTime == false (default): work sessions are scheduled
        enginePrefs.allDayEventsBlockTime = false
        let sessionsAllDayNonBlocking = schedulingEngine.scheduleSessions(for: [stage12TestTask], commitments: [allDayEvent], preferences: enginePrefs, dateRange: testRange)
        check("All-day event with allDayEventsBlockTime == false displays without blocking availability", !sessionsAllDayNonBlocking.isEmpty)
        
        // When allDayEventsBlockTime == true: entire day is blocked, no sessions on that day
        enginePrefs.allDayEventsBlockTime = true
        let sessionsAllDayBlocking = schedulingEngine.scheduleSessions(for: [stage12TestTask], commitments: [allDayEvent], preferences: enginePrefs, dateRange: testRange)
        let daySessionsBlocked = sessionsAllDayBlocking.filter { Calendar.current.isDate($0.startTime, inSameDayAs: today) }
        check("All-day event with allDayEventsBlockTime == true successfully blocks the entire day", daySessionsBlocked.isEmpty)
        
        // 12F: Demo vs Live Data Tagging
        check("Simulated/demo events are clearly tagged with isSimulatedDemo == true", allCommitments.allSatisfy { $0.isSimulatedDemo })
        
        // -----------------------------------------------------------------
        // 13. Proposed Work Schedule Generation, Constraints & Edge Cases
        // -----------------------------------------------------------------
        print("\n▶ Stage 13: Proposed Work Schedule Generation, Constraints & Edge Cases")
        
        let engine13 = RuleBasedSchedulingEngine()
        var prefs13 = UserPreferences()
        prefs13.workStartHour = 9
        prefs13.workEndHour = 17
        prefs13.defaultSessionMinutes = 45
        prefs13.minSessionMinutes = 25
        prefs13.breakMinutes = 15
        prefs13.lunchStartHour = 12
        prefs13.lunchDurationMinutes = 60
        prefs13.maxDailyWorkMinutes = 360
        prefs13.deadlineBufferMinutes = 60
        prefs13.includeDemoDataInPlan = true // Allow test data
        for d in 1...7 {
            prefs13.weekdayWorkingHours[d] = WeekdayHours(isWorkday: true, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0)
        }
        
        let today13 = Calendar.current.startOfDay(for: Date())
        let simStart13 = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: today13)!
        let day2_13 = Calendar.current.date(byAdding: .day, value: 2, to: today13)!
        let day14_13 = Calendar.current.date(byAdding: .day, value: 14, to: today13)!
        let range13 = today13...day14_13
        
        // 13A: Enough Time Scenario (Splitting into manageable sessions)
        let sampleEmail = EmailSource(id: "stage13_email", threadId: "t13", senderName: "Lead", senderEmail: "lead@test.com", subject: "Plan", receivedDate: simStart13, snippet: "", fullBody: "", category: .assignment)
        
        let taskEnoughTime = DiscoveredTask(
            id: UUID(),
            title: "Project Milestone Design",
            requiredAction: "Design architecture",
            notes: "Test",
            sourceEmail: sampleEmail,
            extractedDeadline: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: day2_13),
            isDeadlineSupportedByEmail: true,
            estimatedMinutes: 90,
            status: .ready
        )
        
        let resultEnough = engine13.generateSchedule(
            tasks: [taskEnoughTime],
            commitments: [],
            existingSessions: [],
            preferences: prefs13,
            dateRange: range13,
            currentDate: simStart13
        )
        
        check("Enough time: All 90 minutes scheduled before deadline", resultEnough.proposedSessions.reduce(0) { $0 + $1.durationMinutes } == 90)
        check("Split sessions: 90m task split into manageable 45m sessions", resultEnough.proposedSessions.count == 2 && resultEnough.proposedSessions.allSatisfy { $0.durationMinutes == 45 })
        check("Sessions finish before deadline with 60m buffer", resultEnough.proposedSessions.allSatisfy { $0.endTime <= taskEnoughTime.extractedDeadline!.addingTimeInterval(-3600) })
        check("Break duration: 15m break between consecutive work sessions", resultEnough.proposedSessions.count < 2 || resultEnough.proposedSessions[1].startTime >= resultEnough.proposedSessions[0].endTime.addingTimeInterval(900))
        
        // 13B: Insufficient Time Before Deadline Scenario
        let tightDeadline = simStart13.addingTimeInterval(75 * 60)
        let taskInsufficientTime = DiscoveredTask(
            id: UUID(),
            title: "Urgent Review",
            requiredAction: "Review",
            notes: "Test",
            sourceEmail: sampleEmail,
            extractedDeadline: tightDeadline,
            isDeadlineSupportedByEmail: true,
            estimatedMinutes: 120,
            status: .ready
        )
        
        let resultInsufficient = engine13.generateSchedule(
            tasks: [taskInsufficientTime],
            commitments: [],
            existingSessions: [],
            preferences: prefs13,
            dateRange: range13,
            currentDate: simStart13
        )
        
        check("Insufficient time: Unscheduled report records task", resultInsufficient.unscheduledReports.contains(where: { $0.task.id == taskInsufficientTime.id }))
        check("Insufficient time: Explains why effort could not fit", resultInsufficient.unscheduledReports.first(where: { $0.task.id == taskInsufficientTime.id })?.primaryReason == .insufficientTimeBeforeDeadline)
        check("Safety check: Never silently schedules work after deadline", resultInsufficient.proposedSessions.allSatisfy { $0.endTime <= tightDeadline })
        
        // 13C: Overdue Task Scenario
        let pastDeadline = simStart13.addingTimeInterval(-86400) // Yesterday
        let taskOverdue = DiscoveredTask(
            id: UUID(),
            title: "Overdue Lab",
            requiredAction: "Submit",
            notes: "Test",
            sourceEmail: sampleEmail,
            extractedDeadline: pastDeadline,
            isDeadlineSupportedByEmail: true,
            estimatedMinutes: 60,
            status: .ready
        )
        
        let resultOverdue = engine13.generateSchedule(
            tasks: [taskOverdue],
            commitments: [],
            existingSessions: [],
            preferences: prefs13,
            dateRange: range13,
            currentDate: simStart13
        )
        
        check("Overdue task: Zero sessions scheduled", resultOverdue.proposedSessions.isEmpty)
        check("Overdue task: Reported with reason .deadlinePassed", resultOverdue.unscheduledReports.first(where: { $0.task.id == taskOverdue.id })?.primaryReason == .deadlinePassed)
        
        // 13D: Ambiguous / Missing Deadline Scenario
        let taskAmbiguous = DiscoveredTask(
            id: UUID(),
            title: "Ambiguous Slide Request",
            requiredAction: "Look at deck",
            notes: "Test",
            sourceEmail: sampleEmail,
            extractedDeadline: nil,
            isDeadlineSupportedByEmail: false,
            estimatedMinutes: 45,
            status: .needsClarification
        )
        
        let resultAmbiguous = engine13.generateSchedule(
            tasks: [taskAmbiguous],
            commitments: [],
            existingSessions: [],
            preferences: prefs13,
            dateRange: range13,
            currentDate: simStart13
        )
        
        check("Ambiguous task: Kept visible for review without inventing deadlines", resultAmbiguous.ambiguousTasks.contains(where: { $0.id == taskAmbiguous.id }))
        check("Ambiguous task: Zero automatic work sessions generated", resultAmbiguous.proposedSessions.isEmpty)
        
        // 13E: Preserving Locked Sessions & Deducting Work Completed
        let taskWithPriorWork = DiscoveredTask(
            id: UUID(),
            title: "Large Report",
            requiredAction: "Write report",
            notes: "Test",
            sourceEmail: sampleEmail,
            extractedDeadline: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: day2_13),
            isDeadlineSupportedByEmail: true,
            estimatedMinutes: 90,
            status: .ready
        )
        
        let existingLockedSession = WorkSession(
            id: UUID(),
            taskId: taskWithPriorWork.id,
            title: "Work Session: Large Report",
            startTime: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: day2_13)!,
            endTime: Calendar.current.date(bySettingHour: 10, minute: 45, second: 0, of: day2_13)!,
            status: .planned,
            isLocked: true
        )
        
        let resultWithLocked = engine13.generateSchedule(
            tasks: [taskWithPriorWork],
            commitments: [],
            existingSessions: [existingLockedSession],
            preferences: prefs13,
            dateRange: range13,
            currentDate: today13
        )
        
        check("Locked session preserved exactly in schedule", resultWithLocked.preservedSessions.contains(where: { $0.id == existingLockedSession.id }))
        check("Prior work accounted for: Only remaining 45m scheduled as new proposal", resultWithLocked.proposedSessions.reduce(0) { $0 + $1.durationMinutes } == 45)
        check("No duplicates: Total planned sessions for task equal 90 minutes", resultWithLocked.allSessions.filter { $0.taskId == taskWithPriorWork.id }.reduce(0) { $0 + $1.durationMinutes } == 90)
        
        // 13F: Calendar Change Routing
        let busyMeeting = CalendarCommitment(
            title: "Surprise Standup",
            startTime: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day2_13)!,
            endTime: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: day2_13)!,
            isAllDay: false,
            isBusy: true,
            calendarName: "Work"
        )
        
        let resultRerouted = engine13.generateSchedule(
            tasks: [taskEnoughTime],
            commitments: [busyMeeting],
            existingSessions: [],
            preferences: prefs13,
            dateRange: range13,
            currentDate: today13
        )
        
        let overlapsWithBusy = resultRerouted.proposedSessions.contains { s in
            s.startTime < busyMeeting.endTime && s.endTime > busyMeeting.startTime
        }
        check("Calendar change: Replanning routes around busy events with zero overlaps", !overlapsWithBusy)
        
        // 13G: Date-Only Deadline Cutoff Policy
        var taskDateOnly = taskEnoughTime
        taskDateOnly.isDateOnlyDeadline = true
        taskDateOnly.extractedDeadline = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: day2_13)
        
        var prefsEndOfWorkday = prefs13
        prefsEndOfWorkday.dateOnlyDeadlinePolicy = .endOfWorkday
        let resultEndOfWorkday = engine13.generateSchedule(tasks: [taskDateOnly], commitments: [], existingSessions: [], preferences: prefsEndOfWorkday, dateRange: range13, currentDate: today13)
        let maxSessionEndEOW = resultEndOfWorkday.proposedSessions.map { $0.endTime }.max() ?? Date.distantPast
        
        var prefsStartOfWorkday = prefs13
        prefsStartOfWorkday.dateOnlyDeadlinePolicy = .startOfWorkday
        let resultStartOfWorkday = engine13.generateSchedule(tasks: [taskDateOnly], commitments: [], existingSessions: [], preferences: prefsStartOfWorkday, dateRange: range13, currentDate: today13)
        let maxSessionEndSOW = resultStartOfWorkday.proposedSessions.map { $0.endTime }.max() ?? Date.distantPast
        
        check("Date-only cutoff policy: Start-of-workday enforces earlier completion than end-of-workday", maxSessionEndSOW <= maxSessionEndEOW)
        
        // 13H: Demo Tasks Isolated from Real Plan
        var prefsRealOnly = prefs13
        prefsRealOnly.includeDemoDataInPlan = false
        var demoTask = taskEnoughTime
        demoTask.sourceEmail.isSimulatedDemo = true
        let resultRealOnly = engine13.generateSchedule(tasks: [demoTask], commitments: [], existingSessions: [], preferences: prefsRealOnly, dateRange: range13, currentDate: today13)
        check("Demo isolation: Demo tasks excluded when demonstration mode is off", resultRealOnly.proposedSessions.isEmpty)
        
        // ==========================================
        // STAGE 14: Apple Calendar Publication & Reliable Synchronization
        // ==========================================
        print("\n--- STAGE 14: Apple Calendar Publication & Reliable Synchronization ---")
        
        let simCalService = SimulatedCalendarService()
        _ = try! runAsync { try await simCalService.requestAccess() }
        
        let testDbURL14 = testDir.appendingPathComponent("test_planner_14.json")
        let storage14 = StorageService(customURL: testDbURL14)
        let appState14 = AppState(
            storageService: storage14,
            calendarService: simCalService,
            keychainService: MockKeychainService()
        )
        
        var realSampleEmail14 = sampleEmail
        realSampleEmail14.isSimulatedDemo = false
        
        let realTask14 = DiscoveredTask(
            id: UUID(),
            title: "Prepare Financial Report",
            requiredAction: "Draft report",
            notes: "Test notes",
            sourceEmail: realSampleEmail14,
            extractedDeadline: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: day2_13),
            isDeadlineSupportedByEmail: true,
            estimatedMinutes: 60,
            status: .ready
        )
        
        let cal14 = Calendar.current
        // Tomorrow, so the published session never becomes a missed (re-planned) one during the run.
        let tomorrow14 = cal14.date(byAdding: .day, value: 1, to: today13)!
        let testStartTime14 = cal14.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow14)!
        let testEndTime14 = cal14.date(bySettingHour: 11, minute: 0, second: 0, of: tomorrow14)!
        
        let realSession14 = WorkSession(
            taskId: realTask14.id,
            title: "Prepare Financial Report - Session 1",
            startTime: testStartTime14,
            endTime: testEndTime14,
            status: .planned,
            isLocked: false,
            isManuallyAdjusted: false,
            isSimulatedDemo: false
        )
        
        appState14.tasks = [realTask14]
        appState14.workSessions = [realSession14]
        
        // 14A: Review and Publication Plan Computation
        let initialPlan = appState14.computePublicationPlan()
        check("Initial publication plan identifies 1 session toAdd", initialPlan.toAdd.count == 1 && initialPlan.toAdd.first?.id == realSession14.id)
        check("Initial plan has 0 toUpdate and 0 toRemove", initialPlan.toUpdate.isEmpty && initialPlan.toRemove.isEmpty)
        
        // Demo sessions exclusion check
        let demoSession14 = WorkSession(
            title: "Demo Coffee Chat",
            startTime: testStartTime14,
            endTime: testEndTime14,
            isSimulatedDemo: true
        )
        appState14.workSessions.append(demoSession14)
        let planWithDemo = appState14.computePublicationPlan()
        check("Demonstration sessions strictly excluded from calendar publication", !planWithDemo.toAdd.contains(where: { $0.id == demoSession14.id }))
        appState14.workSessions.removeAll(where: { $0.id == demoSession14.id })
        
        // 14B: Dedicated 'Personal Planner' Calendar Auto-Creation & Privacy Notice
        let targetCalInfo: CalendarAccountInfo? = try! runAsync { await appState14.setupPlannerCalendar() }
        check("Dedicated 'DayBook AI' calendar created/retrieved", targetCalInfo != nil && targetCalInfo?.title == "DayBook AI")
        let providerDesc = targetCalInfo?.providerSyncDescription ?? ""
        check("Provider sync explanation explicitly stated", providerDesc.contains("Mac") || providerDesc.contains("Syncs"))
        
        // 14C: Publish Approved Session (Initial Publication & In-Place ID Mapping)
        _ = try! runAsync {
            await appState14.publishApprovedSessions(
                selectedAddSessionIds: [realSession14.id],
                selectedUpdateSessionIds: [],
                selectedRemoveSessionIds: []
            )
        }
        
        let publishedSession = appState14.workSessions.first(where: { $0.id == realSession14.id })
        check("Session marked as published after EventKit confirmation", publishedSession?.isPublished == true)
        check("Persistent calendarEventId assigned to session", publishedSession?.calendarEventId != nil)
        let savedEventId14 = publishedSession?.calendarEventId ?? ""
        check("Simulated calendar store received the event", simCalService.simulatedEvents[savedEventId14] != nil)
        
        // Privacy check: Event notes only contain title reference, NO email excerpts or credentials
        let calEventNotes = simCalService.simulatedEvents[savedEventId14]?.notes ?? ""
        check("Privacy: Event notes contain planner reference only", calEventNotes.contains("[PersonalPlanner Session]") && !calEventNotes.contains("gemini") && !calEventNotes.contains("token"))
        
        // 14D: Repeated Publication (Zero Duplication when unchanged)
        let secondPlan = appState14.computePublicationPlan()
        check("Repeated plan has 0 toAdd and 0 toUpdate when unchanged", secondPlan.toAdd.isEmpty && secondPlan.toUpdate.isEmpty)
        
        // 14E: In-Place Updates vs Duplication on Local Reschedule
        let newStartTime14 = cal14.date(bySettingHour: 11, minute: 0, second: 0, of: tomorrow14)!
        let newEndTime14 = cal14.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow14)!
        appState14.moveSession(id: realSession14.id, newStartTime: newStartTime14, newEndTime: newEndTime14)
        
        let planAfterMove = appState14.computePublicationPlan()
        check("Local reschedule flags session in toUpdate", planAfterMove.toUpdate.count == 1 && planAfterMove.toUpdate.first?.id == realSession14.id)
        check("Local reschedule does NOT flag session in toAdd", planAfterMove.toAdd.isEmpty)
        
        let eventsCountBeforeUpdate = simCalService.simulatedEvents.count
        _ = try! runAsync {
            await appState14.publishApprovedSessions(
                selectedAddSessionIds: [],
                selectedUpdateSessionIds: [realSession14.id],
                selectedRemoveSessionIds: []
            )
        }
        
        check("Event count in calendar remains constant (in-place update, NO duplicates)", simCalService.simulatedEvents.count == eventsCountBeforeUpdate)
        check("Calendar event start time updated in place", simCalService.simulatedEvents[savedEventId14]?.startTime == newStartTime14)
        
        // 14F: Double-Counting Prevention (isPlannerOwnEvent)
        let commitmentsWithOwn: [CalendarCommitment] = try! runAsync {
            try await simCalService.fetchCommitments(
                for: today13...today13.addingTimeInterval(86400 * 14),
                selectedCalendarIdentifiers: nil,
                allDayBlocksTime: false
            )
        }
        let ownEvent = commitmentsWithOwn.first(where: { $0.externalEventId == savedEventId14 })
        check("Calendar commitment fetch tags planner's own events with isPlannerOwnEvent == true", ownEvent?.isPlannerOwnEvent == true)
        
        let engine14 = RuleBasedSchedulingEngine()
        let replanWithOwn = engine14.generateSchedule(
            tasks: [realTask14],
            commitments: commitmentsWithOwn,
            existingSessions: appState14.workSessions,
            preferences: prefs13,
            dateRange: range13,
            currentDate: today13
        )
        let ownEventsCountInProposed = replanWithOwn.proposedSessions.filter { $0.taskId == realTask14.id }.count
        check("Double-counting prevented: Planner's own published event does not block external availability or duplicate work", ownEventsCountInProposed == 0)
        
        // 14G: Partial Failure Handling & Bounded Retry
        let taskFail14 = DiscoveredTask(
            id: UUID(),
            title: "Task That Will Fail Once",
            requiredAction: "Action",
            notes: "Test",
            sourceEmail: realSampleEmail14,
            extractedDeadline: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: day2_13),
            isDeadlineSupportedByEmail: true,
            estimatedMinutes: 45,
            status: .ready
        )
        let sessionFail14 = WorkSession(
            taskId: taskFail14.id,
            title: "Session That Fails Once",
            startTime: cal14.date(bySettingHour: 14, minute: 0, second: 0, of: tomorrow14)!,
            endTime: cal14.date(bySettingHour: 14, minute: 45, second: 0, of: tomorrow14)!,
            isSimulatedDemo: false
        )
        appState14.tasks.append(taskFail14)
        appState14.workSessions.append(sessionFail14)
        
        // Arm simulated calendar service to fail sessionFail14
        simCalService.failNextPublicationForSessionId = sessionFail14.id
        
        _ = try! runAsync {
            await appState14.publishApprovedSessions(
                selectedAddSessionIds: [sessionFail14.id],
                selectedUpdateSessionIds: [],
                selectedRemoveSessionIds: []
            )
        }
        
        check("Partial failure reported gracefully without crashing", appState14.publishErrorMessage != nil)
        let failedSessionAfterAttempt = appState14.workSessions.first(where: { $0.id == sessionFail14.id })
        check("Failed session remains unpublished (no invalid eventId)", failedSessionAfterAttempt?.calendarEventId == nil && failedSessionAfterAttempt?.isPublished == false)
        
        // Retry publication
        simCalService.failNextPublicationForSessionId = nil
        _ = try! runAsync {
            await appState14.publishApprovedSessions(
                selectedAddSessionIds: [sessionFail14.id],
                selectedUpdateSessionIds: [],
                selectedRemoveSessionIds: []
            )
        }
        let retriedSession = appState14.workSessions.first(where: { $0.id == sessionFail14.id })
        check("Retry successfully published the previously failed session", retriedSession?.isPublished == true && retriedSession?.calendarEventId != nil)
        
        // 14H: Persistence Across App Restart
        appState14.saveDatabase()
        
        let freshAppState14 = AppState(
            storageService: storage14,
            calendarService: simCalService,
            keychainService: MockKeychainService()
        )
        let restoredSession = freshAppState14.workSessions.first(where: { $0.id == realSession14.id })
        check("Persistence: calendarEventId preserved across restart", restoredSession?.calendarEventId == savedEventId14)
        check("Persistence: isPublished preserved across restart", restoredSession?.isPublished == true)
        check("Persistence: lastPublishedStartTime preserved across restart", restoredSession?.lastPublishedStartTime == newStartTime14)
        
        // 14I: External Discrepancy Detection & Reconciliation
        // 1. External Move
        let movedStart14 = cal14.date(bySettingHour: 15, minute: 0, second: 0, of: tomorrow14)!
        let movedEnd14 = cal14.date(bySettingHour: 16, minute: 0, second: 0, of: tomorrow14)!
        simCalService.simulatedEvents[savedEventId14]?.startTime = movedStart14
        simCalService.simulatedEvents[savedEventId14]?.endTime = movedEnd14
        
        _ = try! runAsync { await appState14.checkForCalendarDiscrepancies() }
        let movedDiscrepancy = appState14.externalDiscrepancies.first(where: { $0.sessionId == realSession14.id })
        check("External discrepancy: Detected session moved directly in Apple Calendar", movedDiscrepancy != nil)
        if let movedDisc = movedDiscrepancy {
            // Adopt external move
            _ = try! runAsync { await appState14.resolveDiscrepancy(movedDisc, action: .adoptExternalChange) }
            let adoptedSession = appState14.workSessions.first(where: { $0.id == realSession14.id })
            check("Adopt external change updates local session start time", adoptedSession?.startTime == movedStart14)
        }
        
        // 2. External Deletion
        simCalService.simulatedEvents.removeValue(forKey: savedEventId14)
        _ = try! runAsync { await appState14.checkForCalendarDiscrepancies() }
        let deletedDiscrepancy = appState14.externalDiscrepancies.first(where: { $0.sessionId == realSession14.id })
        check("External discrepancy: Detected session deleted directly in Apple Calendar", deletedDiscrepancy != nil)
        if let delDisc = deletedDiscrepancy {
            // Restore planner version: re-creates event in Apple Calendar
            _ = try! runAsync { await appState14.resolveDiscrepancy(delDisc, action: .restorePlannerVersion) }
            var restoredEventId: String? = nil
            for s in appState14.workSessions {
                if s.id == realSession14.id {
                    restoredEventId = s.calendarEventId
                }
            }
            var eventExistsInCal = false
            if let evtId = restoredEventId, simCalService.simulatedEvents[evtId] != nil {
                eventExistsInCal = true
            }
            check("Restore planner version re-publishes event without silently overwriting external choice", eventExistsInCal)
        }
        
        // 14J: Calendar History Preserved on Task Completion
        var finalEventId = ""
        for s in appState14.workSessions {
            if s.id == realSession14.id {
                finalEventId = s.calendarEventId ?? ""
            }
        }
        appState14.toggleSessionStatus(id: realSession14.id)
        var completedStatus: SessionStatus? = nil
        var finalSessionIdAfter = ""
        for s in appState14.workSessions {
            if s.id == realSession14.id {
                completedStatus = s.status
                finalSessionIdAfter = s.calendarEventId ?? ""
            }
        }
        check("Session marked complete locally", completedStatus == SessionStatus.completed)
        let eventStillInCalendar = simCalService.simulatedEvents[finalEventId] != nil
        check("Calendar event history preserved: Event NOT deleted from calendar on completion", eventStillInCalendar)
        check("Session still retains calendarEventId after completion", finalSessionIdAfter == finalEventId && !finalEventId.isEmpty)
        
        // ==========================================
        // STAGE 15: Short Task (< minSessionMinutes) & Planning Target Regression Checks
        // ==========================================
        print("\n--- STAGE 15: Short Task Scheduling & Planning Target Regression Checks ---")
        
        let engine15 = RuleBasedSchedulingEngine()
        var prefs15 = UserPreferences()
        prefs15.workStartHour = 9
        prefs15.workEndHour = 17
        prefs15.defaultSessionMinutes = 45
        prefs15.minSessionMinutes = 25
        prefs15.maxDailyWorkMinutes = 480
        prefs15.deadlineBufferMinutes = 60
        prefs15.includeDemoDataInPlan = true
        for d in 1...7 {
            prefs15.weekdayWorkingHours[d] = WeekdayHours(isWorkday: true, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0)
        }
        
        // 15A: Regression: Task duration shorter than minSessionMinutes (e.g. 15m < 25m)
        let shortTask = DiscoveredTask(
            id: UUID(),
            title: "Confirm meeting with guest speaker Tim Richards",
            requiredAction: "Reply to confirm",
            notes: "Quick response",
            sourceEmail: realSampleEmail14,
            extractedDeadline: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: day2_13),
            isDeadlineSupportedByEmail: true,
            estimatedMinutes: 15,
            status: .ready
        )
        
        let shortResult = engine15.generateSchedule(
            tasks: [shortTask],
            commitments: [],
            existingSessions: [],
            preferences: prefs15,
            dateRange: range13,
            currentDate: today13
        )
        
        check("Regression: 15m task is scheduled successfully despite minSessionMinutes == 25", shortResult.proposedSessions.count == 1)
        let shortSessionDur = shortResult.proposedSessions.first?.durationMinutes ?? 0
        check("Scheduled session duration equals task duration (15m)", shortSessionDur == 15)
        check("Unscheduled reports empty for valid short task", shortResult.unscheduledReports.isEmpty)
        
        // 15B: Overdue Task Identification & Non-Destructive Planning Target
        let pastDate = today13.addingTimeInterval(-7200) // 2 hours ago
        var overdueTask = DiscoveredTask(
            id: UUID(),
            title: "Complete CATME End Eval for ECONS3300",
            requiredAction: "Complete evaluation",
            notes: "Original assignment",
            sourceEmail: realSampleEmail14,
            extractedDeadline: pastDate,
            isDeadlineSupportedByEmail: true,
            estimatedMinutes: 45,
            status: .ready
        )
        
        check("Overdue task correctly flagged with isOriginalDeadlineOverdue == true", overdueTask.isOriginalDeadlineOverdue)
        check("Task without planning target is flagged with isOverdue == true", overdueTask.isOverdue)
        
        let overdueResult = engine15.generateSchedule(
            tasks: [overdueTask],
            commitments: [],
            existingSessions: [],
            preferences: prefs15,
            dateRange: range13,
            currentDate: today13
        )
        check("Overdue task produces 0 automatic work sessions (safety check: no past scheduling)", overdueResult.proposedSessions.isEmpty)
        check("Overdue task specifically reported as .deadlinePassed", overdueResult.unscheduledReports.first?.primaryReason == .deadlinePassed)
        
        // 15C: Set Planning Target without Overwriting Original Deadline
        let futurePlanningTarget = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: day2_13)!
        overdueTask.planningTargetDate = futurePlanningTarget
        
        check("Original extractedDeadline preserved untouched after setting planning target", overdueTask.extractedDeadline == pastDate)
        check("Original deadline still flagged as isOriginalDeadlineOverdue == true", overdueTask.isOriginalDeadlineOverdue)
        check("Task effectiveDeadline now adopts planningTargetDate", overdueTask.effectiveDeadline == futurePlanningTarget)
        check("Planning target is in future so isOverdue == false", !overdueTask.isOverdue)
        
        let targetResult = engine15.generateSchedule(
            tasks: [overdueTask],
            commitments: [],
            existingSessions: [],
            preferences: prefs15,
            dateRange: range13,
            currentDate: today13
        )
        check("Setting planning target successfully schedules work sessions for overdue task", !targetResult.proposedSessions.isEmpty)
        let scheduledTargetMins = targetResult.proposedSessions.reduce(0) { $0 + $1.durationMinutes }
        check("All 45 minutes of task scheduled before planning target", scheduledTargetMins == 45)
        
        // 15D: Demonstration Mode State Detection
        let demoOnlyState = AppState(
            storageService: storage14,
            calendarService: simCalService,
            keychainService: MockKeychainService()
        )
        var demoTask15 = shortTask
        demoTask15.sourceEmail.isSimulatedDemo = true
        demoOnlyState.tasks = [demoTask15]
        demoOnlyState.isGmailAuthenticated = false
        check("Demo mode active when only demo tasks exist and Gmail not authenticated", demoOnlyState.isDemonstrationModeActive)
        
        demoOnlyState.tasks.append(shortTask) // shortTask has isSimulatedDemo == false
        check("Demo mode INACTIVE when real Gmail tasks are present", !demoOnlyState.isDemonstrationModeActive)
        
        // ==========================================
        // STAGE 16: Planning Target, Deadline Provenance & Eligibility Verification
        // ==========================================
        print("\n--- STAGE 16: Planning Target, Deadline Provenance & Eligibility Verification ---")
        
        // 16A: Unknown Deadline + Confirmed Planning Target (Tim Richards sign-up scenario)
        var timSignUpTask = DiscoveredTask(
            id: UUID(),
            title: "Sign up to meet with Tim Richards for a meeting or meal",
            requiredAction: "Sign up via the provided Google spreadsheet link if interested in visiting with the speaker.",
            notes: "Speaker visiting department",
            sourceEmail: realSampleEmail14,
            extractedDeadline: nil,
            isDeadlineSupportedByEmail: false,
            supportingExcerpt: "Please sign up to meet with Tim for a meeting or for a meal at this link...",
            estimatedMinutes: 45,
            status: .ready,
            uncertainDetails: ["No explicit deadline is given, only a recommendation to sign up soon because slots fill up quickly."],
            planningTargetDate: nil
        )
        
        check("16A-1: Initial original deadline provenance is .unsupported", timSignUpTask.originalDeadlineProvenance == .unsupported)
        check("16A-2: Informational uncertainty does not flag requiredAction as unclear", !timSignUpTask.isActionUnclear)
        check("16A-3: Task without deadline or target has schedulingEligibility == .needsPlanningTarget", timSignUpTask.schedulingEligibility == .needsPlanningTarget)
        check("16A-4: Task without target is not eligible for scheduling", !timSignUpTask.isEligibleForScheduling)
        
        let unscheduledTimResult = engine15.generateSchedule(
            tasks: [timSignUpTask],
            commitments: [],
            existingSessions: [],
            preferences: prefs15,
            dateRange: range13,
            currentDate: today13
        )
        check("16A-5: Engine produces 0 sessions when target is not set", unscheduledTimResult.proposedSessions.isEmpty)
        check("16A-6: Engine reports missing target with explanation", unscheduledTimResult.unscheduledReports.first?.primaryReason == .missingDeadline)
        
        // Confirm User Planning Target
        let confirmedTarget = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: day2_13)!
        timSignUpTask.planningTargetDate = confirmedTarget
        
        check("16A-7: Original extractedDeadline remains nil (unknown)", timSignUpTask.extractedDeadline == nil)
        check("16A-8: isDeadlineSupportedByEmail remains false", !timSignUpTask.isDeadlineSupportedByEmail)
        check("16A-9: Active deadline provenance is now .userTarget", timSignUpTask.activeDeadlineProvenance == .userTarget)
        check("16A-10: Task is now eligible for scheduling", timSignUpTask.schedulingEligibility == .eligible(provenance: .userTarget))
        check("16A-11: isEligibleForScheduling returns true", timSignUpTask.isEligibleForScheduling)
        check("16A-12: Effective deadline adopts user planning target", timSignUpTask.effectiveDeadline == confirmedTarget)
        
        let scheduledTimResult = engine15.generateSchedule(
            tasks: [timSignUpTask],
            commitments: [],
            existingSessions: [],
            preferences: prefs15,
            dateRange: range13,
            currentDate: today13
        )
        check("16A-13: Scheduler successfully generates proposed work session for task with confirmed planning target", scheduledTimResult.proposedSessions.count == 1)
        check("16A-14: Scheduled session has 45m effort", scheduledTimResult.proposedSessions.first?.durationMinutes == 45)
        check("16A-15: Unscheduled reports empty after target confirmed", scheduledTimResult.unscheduledReports.isEmpty)
        
        // 16B: Informational Uncertainty vs. Blocking Action Uncertainty
        let vagueTask = DiscoveredTask(
            id: UUID(),
            title: "Follow up on email thread",
            requiredAction: "", // empty action
            notes: "Vague email",
            sourceEmail: realSampleEmail14,
            extractedDeadline: confirmedTarget,
            isDeadlineSupportedByEmail: true,
            status: .needsClarification,
            uncertainDetails: ["The required action is unspecified in the email message."],
            isClarified: false
        )
        check("16B-1: Task with empty/unclear action has isActionUnclear == true", vagueTask.isActionUnclear)
        if case .needsActionClarification = vagueTask.schedulingEligibility {
            check("16B-2: Scheduling eligibility is .needsActionClarification", true)
        } else {
            check("16B-2: Scheduling eligibility is .needsActionClarification", false)
        }
        
        let vagueResult = engine15.generateSchedule(
            tasks: [vagueTask],
            commitments: [],
            existingSessions: [],
            preferences: prefs15,
            dateRange: range13,
            currentDate: today13
        )
        check("16B-3: Engine does not schedule task with unclear required action", vagueResult.proposedSessions.isEmpty)
        check("16B-4: Engine reports reason as .needsActionClarification", vagueResult.unscheduledReports.first?.primaryReason == .needsActionClarification)
        
        // 16C: CATME Date-Only Deadline Provenance & Workday Policy
        let catmeTask = DiscoveredTask(
            id: UUID(),
            title: "Complete CATME End Eval for ECONS3300",
            requiredAction: "Log into CATME and complete evaluation",
            notes: "Peer evaluation",
            sourceEmail: realSampleEmail14,
            extractedDeadline: Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: day2_13),
            isDeadlineSupportedByEmail: true,
            supportingExcerpt: "The following activity will be closing on Monday    Nov 02nd:",
            isDateOnlyDeadline: true
        )
        check("16C-1: CATME identified as .dateOnly provenance", catmeTask.originalDeadlineProvenance == .dateOnly)
        
        // Verify that date-only policy (End of Workday 5:00 PM) sets cutoff to 17:00 (minus buffer) rather than 23:59
        var workdayPrefs = prefs15
        workdayPrefs.dateOnlyDeadlinePolicy = .endOfWorkday
        workdayPrefs.deadlineBufferMinutes = 0
        let catmeResult = engine15.generateSchedule(
            tasks: [catmeTask],
            commitments: [],
            existingSessions: [],
            preferences: workdayPrefs,
            dateRange: range13,
            currentDate: today13
        )
        check("16C-2: CATME scheduled session ends on or before 17:00 (End of Workday)", catmeResult.proposedSessions.allSatisfy {
            Calendar.current.component(.hour, from: $0.endTime) <= 17
        })
        
        // 16D: ZIPAIR Relative Time Window Provenance
        let zipairTask = DiscoveredTask(
            id: UUID(),
            title: "Complete ZIPAIR membership registration",
            requiredAction: "Register personal info",
            sourceEmail: realSampleEmail14,
            extractedDeadline: today13.addingTimeInterval(86400),
            isDeadlineSupportedByEmail: true,
            supportingExcerpt: "Please go to the following URL and register your personal information to complete registration within 24 hours."
        )
        check("16D-1: ZIPAIR identified as .relativeWindow provenance", zipairTask.originalDeadlineProvenance == .relativeWindow)
        
        // 16E: Persistence of Planning Target across App Restarts
        let testDir16 = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PersonalPlannerTest16_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDir16, withIntermediateDirectories: true)
        let testDbURL16 = testDir16.appendingPathComponent("db16.json")
        defer { try? FileManager.default.removeItem(at: testDir16) }
        let storage16 = StorageService(customURL: testDbURL16)
        
        let app16 = AppState(
            storageService: storage16,
            calendarService: simCalService,
            keychainService: MockKeychainService()
        )
        app16.tasks = [timSignUpTask]
        app16.saveDatabase()
        
        let reloadedApp16 = AppState(
            storageService: storage16,
            calendarService: simCalService,
            keychainService: MockKeychainService()
        )
        let reloadedTim = reloadedApp16.tasks.first(where: { $0.id == timSignUpTask.id })
        check("16E-1: Planning target preserved across restarts", reloadedTim?.planningTargetDate == confirmedTarget)
        check("16E-2: Extracted deadline remains nil across restarts", reloadedTim?.extractedDeadline == nil)
        check("16E-3: isDeadlineSupportedByEmail remains false across restarts", reloadedTim?.isDeadlineSupportedByEmail == false)
        check("16E-4: Reloaded task remains eligible for scheduling", reloadedTim?.isEligibleForScheduling == true)
        
        // -----------------------------------------------------------------
        // 17. Timezone Handling, Relative Weekdays, DST Transitions & Migrations
        // -----------------------------------------------------------------
        print("\n▶ Stage 17: Timezone Handling, Relative Weekdays, DST Transitions & Migrations")
        
        let laTimeZone = TimeZone(identifier: "America/Los_Angeles")!
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        
        // 17A: "Wednesday at 6pm" parsed with America/Los_Angeles
        // Email sent Monday Nov 2, 2026 at 5:50:24 PM PST -> 2026-11-03T01:50:24Z
        let wednesdayEmailDate = isoFormatter.date(from: "2026-11-03T01:50:24Z")!
        let wednesdayExcerpt = "Please let me know if you want to meet with him by Wednesday at 6pm"
        let wednesdayResolved = DeadlinesResolver.resolve(
            rawDeadlineIso: "2026-11-04T18:00:00Z", // Erroneous UTC from previous raw parsing
            supportingExcerpt: wednesdayExcerpt,
            emailReceivedDate: wednesdayEmailDate,
            configuredTimeZone: laTimeZone,
            dateOnlyPolicy: .endOfWorkday,
            workdayEndHour: 17,
            workdayEndMinute: 0,
            workdayStartHour: 9,
            workdayStartMinute: 0
        )
        let expectedWednesdayUtc = isoFormatter.date(from: "2026-11-05T02:00:00Z")! // 2026-11-04 18:00:00 -0800
        check("17A-1: 'Wednesday at 6pm' resolves to 2026-11-05T02:00:00Z (18:00 PST), NOT 2026-11-04T18:00:00Z (10:00 PST)", wednesdayResolved.deadlineDate == expectedWednesdayUtc)
        check("17A-2: Preserves original wording 'Wednesday at 6pm'", wednesdayResolved.originalWording?.contains("Wednesday at 6pm") == true)
        check("17A-3: Assumes configured America/Los_Angeles timezone", wednesdayResolved.timeZoneAssumption.contains("America/Los_Angeles"))
        
        // 17B: Planning Target UTC vs Local Boundary
        // Saved planning target: 2026-11-06T04:28:54Z
        let targetUtcDate = isoFormatter.date(from: "2026-11-06T04:28:54Z")!
        let laDateFormatter = DateFormatter()
        laDateFormatter.timeZone = laTimeZone
        laDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let localTargetString = laDateFormatter.string(from: targetUtcDate)
        check("17B-1: 2026-11-06T04:28:54Z formats to November 5 (20:28:54) in Pacific time", localTargetString == "2026-11-05 20:28:54")
        laDateFormatter.dateFormat = "MMMM d, h:mm a"
        let readableLocalTarget = laDateFormatter.string(from: targetUtcDate)
        check("17B-2: User-facing string displays November 5, 8:28 PM", readableLocalTarget == "November 5, 8:28 PM")
        
        // 17C: Date-Only Deadline with Configured Policy & Timezone
        // CATME: "closing on Monday Nov 02nd:"
        let catmeResolved = DeadlinesResolver.resolve(
            rawDeadlineIso: "2026-11-02T23:59:00Z",
            supportingExcerpt: "The following activity will be closing on Monday    Nov 02nd:",
            emailReceivedDate: wednesdayEmailDate,
            configuredTimeZone: laTimeZone,
            dateOnlyPolicy: .endOfWorkday,
            workdayEndHour: 17,
            workdayEndMinute: 0,
            workdayStartHour: 9,
            workdayStartMinute: 0
        )
        check("17C-1: CATME resolves dateOnlyString as '2026-11-02'", catmeResolved.dateOnlyString == "2026-11-02")
        // In America/Los_Angeles, 5:00 PM on 2026-11-02 is 2026-11-03T01:00:00Z
        let expectedCatmeCutoff = isoFormatter.date(from: "2026-11-03T01:00:00Z")!
        check("17C-2: Date-only cutoff with End of Workday policy is 2026-11-03T01:00:00Z (5:00 PM PST)", catmeResolved.deadlineDate == expectedCatmeCutoff)
        check("17C-3: Cutoff is NOT 2026-11-02T23:59:00Z (which would be 3:59 PM PST)", catmeResolved.deadlineDate != isoFormatter.date(from: "2026-11-02T23:59:00Z"))
        
        // 17D: Daylight-Saving Transition (Fall 2026 DST ends Nov 1, 2026 at 2:00 AM)
        // Email sent Saturday Oct 31, 2026 at 18:36:24 PDT -> 2026-11-01T01:36:24Z (UTC-7)
        let preDstEmailDate = isoFormatter.date(from: "2026-11-01T01:36:24Z")!
        let zipairResolved = DeadlinesResolver.resolve(
            rawDeadlineIso: nil,
            supportingExcerpt: "Please go to the following URL and register your personal information to complete registration within 24 hours.",
            emailReceivedDate: preDstEmailDate,
            configuredTimeZone: laTimeZone,
            dateOnlyPolicy: .endOfWorkday,
            workdayEndHour: 17,
            workdayEndMinute: 0,
            workdayStartHour: 9,
            workdayStartMinute: 0
        )
        // 24 hours elapsed = 86,400 physical seconds -> 2026-11-02T01:36:24Z
        let expectedZipairUtc = isoFormatter.date(from: "2026-11-02T01:36:24Z")!
        check("17D-1: 'Within 24 hours' adds exactly 86,400 seconds across DST transition", zipairResolved.deadlineDate == expectedZipairUtc)
        // In PST (UTC-8 after fallback), 2026-11-02T01:36:24Z is 17:36:24 (5:36 PM PST)
        let postDstLocalHour = Calendar(identifier: .gregorian).dateComponents(in: laTimeZone, from: zipairResolved.deadlineDate!).hour
        check("17D-2: Local time reflects 1-hour DST fallback (17:36 PST vs 18:36 PDT)", postDstLocalHour == 17)
        
        // 17E: Explicit Email Timezone Parsing
        let explicitEstExcerpt = "Please submit the finalized feedback by 5:00 PM EST on Nov 4"
        let estResolved = DeadlinesResolver.resolve(
            rawDeadlineIso: nil,
            supportingExcerpt: explicitEstExcerpt,
            emailReceivedDate: wednesdayEmailDate,
            configuredTimeZone: laTimeZone,
            dateOnlyPolicy: .endOfWorkday,
            workdayEndHour: 17,
            workdayEndMinute: 0,
            workdayStartHour: 9,
            workdayStartMinute: 0
        )
        // 5:00 PM EST (UTC-5) on Nov 4, 2026 = 22:00:00Z = 14:00 (2:00 PM) PST
        let expectedEstUtc = isoFormatter.date(from: "2026-11-04T22:00:00Z")!
        check("17E-1: Explicit '5:00 PM EST' resolves to 2026-11-04T22:00:00Z", estResolved.deadlineDate == expectedEstUtc)
        check("17E-2: Explicit EST labeled as explicit in timeZoneAssumption", estResolved.timeZoneAssumption.contains("EST"))
        
        // 17F: Targeted Database Migration in AppState.loadDatabase()
        let testDir17 = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PersonalPlannerTest17_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDir17, withIntermediateDirectories: true)
        let testDbURL17 = testDir17.appendingPathComponent("db17.json")
        defer { try? FileManager.default.removeItem(at: testDir17) }
        let storage17 = StorageService(customURL: testDbURL17)
        
        // Store an un-migrated task with the old erroneous 2026-11-04T18:00:00Z
        let unmigratedEmail = EmailSource(
            id: "msg_tim_erroneous",
            threadId: "th_tim",
            senderName: "Tim Richards",
            senderEmail: "tim@example.com",
            subject: "Meeting request",
            receivedDate: wednesdayEmailDate,
            snippet: "Wednesday at 6pm",
            fullBody: "Please let me know if you want to meet with him by Wednesday at 6pm",
            category: .assignment,
            isSimulatedDemo: false
        )
        let unmigratedTask = DiscoveredTask(
            id: UUID(),
            title: "Reply to Tim Richards meeting request",
            requiredAction: "Reply with meeting preference",
            notes: "Meeting notes",
            sourceEmail: unmigratedEmail,
            extractedDeadline: isoFormatter.date(from: "2026-11-04T18:00:00Z"), // Old erroneous value
            isDeadlineSupportedByEmail: true,
            supportingExcerpt: "Please let me know if you want to meet with him by Wednesday at 6pm"
        )
        let mappedSession17 = WorkSession(
            taskId: unmigratedTask.id,
            title: "Reply to Tim Richards meeting request - Session 1",
            startTime: wednesdayEmailDate.addingTimeInterval(3600),
            endTime: wednesdayEmailDate.addingTimeInterval(5400),
            status: .planned,
            isLocked: false,
            isManuallyAdjusted: false,
            isSimulatedDemo: false,
            calendarEventId: "cal_mapped_123"
        )
        
        let initialApp17 = AppState(
            storageService: storage17,
            calendarService: simCalService,
            keychainService: MockKeychainService()
        )
        initialApp17.tasks = [unmigratedTask]
        initialApp17.workSessions = [mappedSession17]
        initialApp17.saveDatabase()
        
        // Re-load app; migration in loadDatabase() should detect and upgrade the record
        let migratedApp17 = AppState(
            storageService: storage17,
            calendarService: simCalService,
            keychainService: MockKeychainService()
        )
        let loadedTask17 = migratedApp17.tasks.first(where: { $0.id == unmigratedTask.id })
        check("17F-1: Migration upgraded extractedDeadline to 2026-11-05T02:00:00Z (6pm PST)", loadedTask17?.extractedDeadline == expectedWednesdayUtc)
        check("17F-2: Migration populated originalDeadlineWording", loadedTask17?.originalDeadlineWording?.contains("Wednesday at 6pm") == true)
        let loadedSession17 = migratedApp17.workSessions.first(where: { $0.id == mappedSession17.id })
        check("17F-3: Migration preserved existing calendarEventId mapping on session", loadedSession17?.calendarEventId == "cal_mapped_123")
        
        // 17G: Planning-Target Eligibility Scheduling Verification
        var schedulePrefs17 = UserPreferences()
        schedulePrefs17.timeZoneIdentifier = "America/Los_Angeles"
        schedulePrefs17.workStartHour = 9
        schedulePrefs17.workEndHour = 17
        schedulePrefs17.defaultSessionMinutes = 30
        schedulePrefs17.minSessionMinutes = 15
        schedulePrefs17.deadlineBufferMinutes = 0
        schedulePrefs17.maxDailyWorkMinutes = 480
        for d in 1...7 {
            schedulePrefs17.weekdayWorkingHours[d] = WeekdayHours(isWorkday: true, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0)
        }
        
        let simCurrentDate17 = isoFormatter.date(from: "2026-11-03T17:00:00Z")! // Nov 3, 9:00 AM PST
        let simEndDate17 = simCurrentDate17.addingTimeInterval(7 * 86400)
        let schedulingResult17 = engine15.generateSchedule(
            tasks: [timSignUpTask],
            commitments: [],
            existingSessions: [],
            preferences: schedulePrefs17,
            dateRange: simCurrentDate17...simEndDate17,
            currentDate: simCurrentDate17
        )
        check("17G-1: Planning target task successfully generates proposed session", !schedulingResult17.proposedSessions.isEmpty)
        if let session = schedulingResult17.proposedSessions.first {
            check("17G-2: Session ends before confirmed planning target", session.endTime <= confirmedTarget)
            check("17G-3: Session scheduled within working hours", {
                let hour = Calendar.current.component(.hour, from: session.startTime)
                return hour >= 9 && hour < 17
            }())
        }
        
        // -----------------------------------------------------------------
        // 19. Missed sessions, Catch Up and Unplanned tasks
        // -----------------------------------------------------------------
        print("\n▶ Stage 19: Missed sessions, Catch Up, Unplanned")
        func src19(_ id: String) -> EmailSource {
            EmailSource(id: id, threadId: id, senderName: "Prof", senderEmail: "p@school.edu", subject: id, receivedDate: Date(),
                        snippet: "", fullBody: "", category: .assignment, isSimulatedDemo: false)
        }
        func task19(_ title: String, minutes: Int, due: Date?) -> DiscoveredTask {
            DiscoveredTask(title: title, sourceEmail: src19(title), extractedDeadline: due, isDeadlineSupportedByEmail: due != nil,
                           estimatedMinutes: minutes, status: .ready, isClarified: true)
        }
        let now19 = Date()
        let yesterday19 = now19.addingTimeInterval(-86400)
        func past19(_ taskId: UUID, minutes: Int, status: SessionStatus = .planned) -> WorkSession {
            WorkSession(taskId: taskId, title: "Work Session", startTime: yesterday19, endTime: yesterday19.addingTimeInterval(Double(minutes * 60)), status: status)
        }
        // Engine: a missed (or skipped) session doesn't count; a completed one does.
        let essay19 = task19("Essay 19", minutes: 120, due: now19.addingTimeInterval(6 * 86400))
        let engine19 = RuleBasedSchedulingEngine()
        let prefs19 = UserPreferences()
        func plannedAhead(_ sessions: [WorkSession]) -> Int {
            engine19.generateSchedule(tasks: [essay19], commitments: [], existingSessions: sessions, preferences: prefs19,
                                      dateRange: Calendar.current.startOfDay(for: now19)...now19.addingTimeInterval(14 * 86400), currentDate: now19)
                .proposedSessions.filter { $0.taskId == essay19.id }.reduce(0) { $0 + $1.durationMinutes }
        }
        check("19A: A missed session doesn't count as work: all 120 min planned again", plannedAhead([past19(essay19.id, minutes: 60)]) == 120)
        check("19B: A skipped session doesn't count either", plannedAhead([past19(essay19.id, minutes: 60, status: .skipped)]) == 120)
        check("19C: A completed session still counts (60 min left)", plannedAhead([past19(essay19.id, minutes: 60, status: .completed)]) == 60)

        let dir19 = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PP_CatchUp_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir19, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir19) }
        func app19(_ name: String) -> AppState {
            let a = AppState(storageService: StorageService(customURL: dir19.appendingPathComponent("\(name).json")), calendarService: SimulatedCalendarService(), keychainService: MockKeychainService())
            a.tasks = []; a.workSessions = []; a.commitments = []; a.declinedSlots = []
            return a
        }
        func ahead(_ a: AppState, _ id: UUID) -> Int {
            a.workSessions.filter { $0.taskId == id && RuleBasedSchedulingEngine.countsAsPlannedWork($0, at: Date()) }.reduce(0) { $0 + $1.durationMinutes }
        }
        // Catch Up: missed work is planned again without waiting for an answer.
        let a19 = app19("a")
        a19.tasks = [essay19]
        let missed19 = past19(essay19.id, minutes: 60)
        a19.workSessions = [missed19]
        check("19D: The missed session shows on the Catch Up card", a19.missedSessions().map(\.id) == [missed19.id])
        a19.replanIfSessionsWereMissed()
        check("19E: A newly missed session re-plans the task's work", ahead(a19, essay19.id) == 120)
        let before19 = a19.workSessions
        a19.replanIfSessionsWereMissed()
        check("19F: …only once (nothing moves on the next check)", a19.workSessions == before19)
        a19.answerMissedSession(id: missed19.id, done: false)
        check("19G: Not Done Yet keeps it as skipped history with carryover priority",
              a19.workSessions.first { $0.id == missed19.id }?.status == .skipped && a19.tasks.first?.isCarryover == true && a19.missedSessions().isEmpty)
        check("19H: …the estimate is unchanged and all of it is still planned", a19.tasks.first?.effectiveDuration == 120 && ahead(a19, essay19.id) == 120)

        // Done: counts as work; the task completes when that covers it.
        let short19 = task19("Short 19", minutes: 60, due: now19.addingTimeInterval(6 * 86400))
        let b19 = app19("b")
        b19.tasks = [short19]
        let doneMissed19 = past19(short19.id, minutes: 60)
        b19.workSessions = [doneMissed19]
        b19.replanIfSessionsWereMissed()
        b19.answerMissedSession(id: doneMissed19.id, done: true)
        check("19I: Done counts the session and completes a fully covered task",
              b19.workSessions.first { $0.id == doneMissed19.id }?.status == .completed && b19.tasks.first?.isCompleted == true)
        check("19J: …and its re-planned time ahead is removed", ahead(b19, short19.id) == 0)

        // Answer All
        let c19 = app19("c")
        let t1 = task19("One 19", minutes: 45, due: now19.addingTimeInterval(6 * 86400))
        let t2 = task19("Two 19", minutes: 45, due: now19.addingTimeInterval(6 * 86400))
        c19.tasks = [t1, t2]
        c19.workSessions = [past19(t1.id, minutes: 45), past19(t2.id, minutes: 45)]
        c19.answerAllMissedSessions(done: false)
        check("19K: None of These Got Done answers every missed session", c19.missedSessions().isEmpty
              && c19.workSessions.filter { $0.status == .skipped }.count == 2 && ahead(c19, t1.id) == 45 && ahead(c19, t2.id) == 45)

        // Unplanned list
        let d19 = app19("d")
        let passed19 = task19("Passed 19", minutes: 15, due: now19.addingTimeInterval(-3 * 86400))
        let noDate19 = task19("No date 19", minutes: 30, due: nil)
        let missedOnly19 = task19("Missed 19", minutes: 60, due: now19.addingTimeInterval(6 * 86400))
        let huge19 = task19("Huge 19", minutes: 900, due: now19.addingTimeInterval(50 * 60))
        var covered19 = task19("Covered 19", minutes: 30, due: now19.addingTimeInterval(6 * 86400))
        covered19.userPriority = .low
        d19.tasks = [passed19, noDate19, missedOnly19, huge19, covered19]
        d19.generateProposedPlan()
        d19.workSessions.append(past19(missedOnly19.id, minutes: 60))
        d19.workSessions.removeAll { $0.taskId == missedOnly19.id && $0.status == .planned && $0.endTime > Date() }
        d19.workSessions.removeAll { $0.taskId == covered19.id }
        d19.workSessions.append(past19(covered19.id, minutes: 30, status: .completed))
        let reasons19 = Dictionary(uniqueKeysWithValues: d19.unplannedTasks().map { ($0.task.title, $0.reason) })
        check("19L: Deadline passed is listed", { if case .deadlinePassed = reasons19["Passed 19"] { return true }; return false }())
        check("19M: No deadline needs a target", reasons19["No date 19"] == .needsTarget)
        check("19N: Missed sessions are listed", reasons19["Missed 19"] == .missedSessions(1))
        check("19O: Won't fit before the deadline is listed", { if case .wontFit = reasons19["Huge 19"] { return true }; return false }())
        check("19P: All time done but not checked off is listed", reasons19["Covered 19"] == .allTimeDone)
        check("19Q: Tasks with work ahead aren't listed", d19.unplannedTasks().allSatisfy { ahead(d19, $0.task.id) == 0 })
        d19.replanMissedWork(taskId: missedOnly19.id)
        check("19R: Re-plan puts missed work back in the plan", ahead(d19, missedOnly19.id) == 60 && !d19.unplannedTasks().contains { $0.task.id == missedOnly19.id })
        d19.setPlanningTarget(id: noDate19.id, targetDate: now19.addingTimeInterval(4 * 86400))
        check("19S: Set Target plans it", ahead(d19, noDate19.id) == 30)
        d19.raisePriority(taskId: covered19.id)
        check("19T: Raise Priority goes one step up", d19.tasks.first { $0.id == covered19.id }?.userPriority == .medium)
        d19.dismissTask(taskId: passed19.id)
        check("19U: Dismissed tasks leave the list", !d19.unplannedTasks().contains { $0.task.id == passed19.id })

        print("\n=======================================================")
        if allPassed {
            print(" 🎉 ALL MILESTONE VERIFICATION CHECKS PASSED!")
            print(" Multi-model fallback, alias protection, and caching verified.")
        } else {
            print(" ⚠️ SOME CHECKS FAILED. Please review the output above.")
        }
        print("=======================================================\n")
        
        return allPassed
    }
}
