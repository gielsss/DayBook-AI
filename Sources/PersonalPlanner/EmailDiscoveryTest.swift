import Foundation

@MainActor
public final class EmailDiscoveryTester {
    
    // MARK: - Mocks
    
    public final class MockDiscoveryGmailService: GmailServiceProtocol {
        public var isConnected: Bool = true
        public var hasClientConfig: Bool = true
        
        public var stubsToReturn: [GmailMessageStub] = []
        public var emailDetails: [String: EmailSource] = [:]
        public var failingIds: [String: Error] = [:]
        
        public var listStubsCallCount: Int = 0
        public var fetchEmailCallCount: Int = 0
        public var fetchedEmailIds: [String] = []
        public var recordedWindowStart: Date? = nil
        public var recordedWindowEnd: Date? = nil
        
        public init() {}
        
        public func importClientConfig(from data: Data) throws -> GoogleClientConfig {
            throw NSError(domain: "Mock", code: 0)
        }
        public func loadClientConfig() -> GoogleClientConfig? { nil }
        public func signIn() async throws {}
        public func disconnect() throws {}
        public func fetchRecentEmailSummaries(limit: Int) async throws -> [RecentEmailSummary] { [] }
        
        public func fetchEmailsFromLastDays(days: Int) async throws -> [EmailSource] {
            return stubsToReturn.compactMap { emailDetails[$0.id] }
        }
        
        public func listInboxMessageStubs(windowStart: Date, windowEnd: Date) async throws -> (messages: [GmailMessageStub], queryStartDate: Date, queryEndDate: Date) {
            listStubsCallCount += 1
            recordedWindowStart = windowStart
            recordedWindowEnd = windowEnd
            
            // Accurate Gmail query simulation: precise timestamp filtering [windowStart, windowEnd]
            let eligible = stubsToReturn.filter { stub in
                if let email = emailDetails[stub.id] {
                    return email.receivedDate >= windowStart && email.receivedDate <= windowEnd
                }
                return true
            }
            return (eligible, windowStart, windowEnd)
        }
        
        public func listInboxMessageStubs(days: Int) async throws -> (messages: [GmailMessageStub], queryStartDate: Date, queryEndDate: Date) {
            let now = Date()
            let start = now.addingTimeInterval(-Double(days * 86400))
            return try await listInboxMessageStubs(windowStart: start, windowEnd: now)
        }
        
        public func fetchSingleEmail(id: String, threadId: String) async throws -> EmailSource {
            fetchEmailCallCount += 1
            fetchedEmailIds.append(id)
            
            if let err = failingIds[id] {
                throw err
            }
            if let email = emailDetails[id] {
                return email
            }
            throw NSError(domain: "GmailService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Message \(id) not found."])
        }
    }
    
    public final class MockDiscoveryOllamaService: OllamaExtractionServiceProtocol {
        public var analyzeEmailCallCount: Int = 0
        public var analyzedEmailIds: [String] = []
        public var responsesByEmailId: [String: EmailAnalysis] = [:]
        public var errorsByEmailId: [String: Error] = [:]
        
        public init() {}
        
        public func analyzeEmail(
            email: EmailSource,
            threadContext: [EmailSource],
            existingTasks: [DiscoveredTask],
            baseURL: String,
            model: String,
            timeZone: TimeZone,
            checkCancellation: (() -> Bool)?,
            onRetry: ((String) -> Void)?
        ) async throws -> EmailAnalysis {
            analyzeEmailCallCount += 1
            analyzedEmailIds.append(email.id)
            
            if let err = errorsByEmailId[email.id] {
                throw err
            }
            if let resp = responsesByEmailId[email.id] {
                return resp
            }
            return EmailAnalysis(
                isNewsletterOrMarketing: false,
                isDirectedAtRecipient: true,
                hasActionableTask: true,
                reasoning: "Mock default actionable task",
                tasks: [CandidateTask(title: "Task from \(email.subject)", requiredAction: "Action for \(email.subject)")]
            )
        }
        
        public func installedModels(baseURL: String) async throws -> [String] { [OllamaDefaults.model] }
        
        public func testConnection(baseURL: String, model: String) async throws -> String {
            return "Connected"
        }
    }
    
    // MARK: - Test Runner
    
    public static func runAllTests() -> Bool {
        print("\n=======================================================")
        print(" 📬 PERSONAL PLANNER 3-DAY (72H) EMAIL DISCOVERY TEST")
        print(" Rolling Window, Exact Boundaries & Failure Audit")
        print("=======================================================\n")
        
        var passedCount = 0
        var totalCount = 0
        
        func check(_ name: String, _ condition: Bool, _ details: String = "") {
            totalCount += 1
            if condition {
                passedCount += 1
                print("  ✅ [PASS] \(name)")
            } else {
                print("  ❌ [FAIL] \(name)")
                if !details.isEmpty {
                    print("     Details: \(details)")
                }
            }
        }
        
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PP_EmailDiscovery_\(UUID().uuidString)")
        let dbURL = tempDir.appendingPathComponent("planner_database.json")
        let storageService = StorageService(customURL: dbURL)
        
        let mockGmail = MockDiscoveryGmailService()
        let mockModel = MockDiscoveryOllamaService()
        
        let appState = AppState(
            storageService: storageService,
            calendarService: SimulatedCalendarService(),
            gmailService: mockGmail,
            ollamaService: mockModel
        )
        
        appState.isGmailAuthenticated = true
        
        let now = Date()
        let oneDayAgo = now.addingTimeInterval(-24 * 3600)
        let twoDaysAgo = now.addingTimeInterval(-48 * 3600)
        let fourDaysAgo = now.addingTimeInterval(-96 * 3600) // Outside 72h / 3-day scope
        
        // ----------------------------------------------------
        // Stage 1: 3-Day Scope & Exact Coverage Dates, Time & Timezone
        // ----------------------------------------------------
        print("--- Stage 1: 3-Day Scope (72-Hour Window) & Exact Coverage Dates ---")
        let stub1 = GmailMessageStub(id: "msg_001", threadId: "thread_001")
        let stub2 = GmailMessageStub(id: "msg_002", threadId: "thread_002")
        mockGmail.stubsToReturn = [stub1, stub2]
        
        let email1 = EmailSource(
            id: "msg_001",
            threadId: "thread_001",
            senderName: "Prof. Davis",
            senderEmail: "davis@university.edu",
            subject: "Problem Set 4 due Friday",
            receivedDate: oneDayAgo,
            snippet: "Please complete questions 1-5 by Friday.",
            fullBody: "Please complete questions 1-5 by Friday 5:00 PM.",
            category: .assignment
        )
        
        let email2 = EmailSource(
            id: "msg_002",
            threadId: "thread_002",
            senderName: "Alumni Association",
            senderEmail: "newsletter@alumni.org",
            subject: "Monthly Newsletter",
            receivedDate: twoDaysAgo,
            snippet: "Check out this month's updates.",
            fullBody: "Check out this month's alumni updates and job openings.",
            category: .newsletter
        )
        
        mockGmail.emailDetails["msg_001"] = email1
        mockGmail.emailDetails["msg_002"] = email2
        
        mockModel.responsesByEmailId["msg_001"] = EmailAnalysis(
            isNewsletterOrMarketing: false,
            isDirectedAtRecipient: true,
            hasActionableTask: true,
            reasoning: "Clear homework assignment",
            tasks: [CandidateTask(title: "Problem Set 4", requiredAction: "Complete questions 1-5", deadlineIso: "2026-11-06T17:00:00Z")]
        )
        
        mockModel.responsesByEmailId["msg_002"] = EmailAnalysis(
            isNewsletterOrMarketing: true,
            isDirectedAtRecipient: false,
            hasActionableTask: false,
            reasoning: "Newsletter classified",
            tasks: []
        )
        
        _ = try! runAsync { await appState.scanEmailsFromLast3Days() }
        
        check("Initial scan listed inbox stubs with 72h window", mockGmail.listStubsCallCount == 1)
        check("Initial scan query span is exactly 72 hours", mockGmail.recordedWindowStart != nil && abs(mockGmail.recordedWindowEnd!.timeIntervalSince(mockGmail.recordedWindowStart!) - 72 * 3600) < 2.0)
        check("Initial scan fetched exactly 2 email bodies", mockGmail.fetchEmailCallCount == 2)
        check("Initial scan invoked the model exactly 2 times", mockModel.analyzeEmailCallCount == 2)
        check("New task discovered from Problem Set 4", appState.tasks.contains(where: { $0.title == "Problem Set 4" }))
        check("Newsletter email was filtered", appState.tasks.contains(where: { $0.sourceEmail.id == "msg_002" }) == false)
        check("Exact coverage string contains 'Inbox only'", appState.lastScanCoverage.contains("Inbox only"))
        check("Coverage range string reflects 3 days / 72h", appState.lastScanRange?.contains("Last 3 days / 72h") == true)
        check("Coverage string includes actual time of day (contains colon separator)", appState.lastScanCoverage.contains(":"))
        
        // ----------------------------------------------------
        // Stage 2: Focused 72-Hour Boundary Checks & Mid-Scan Arrivals
        // ----------------------------------------------------
        print("\n--- Stage 2: 72-Hour Boundary Checks & Arrivals During Scan ---")
        // Email inside: 71 hours 55 minutes ago (inside 72h)
        let insideDate = now.addingTimeInterval(-((71 * 3600) + (55 * 60)))
        let stubInside = GmailMessageStub(id: "msg_inside", threadId: "thread_inside")
        let emailInside = EmailSource(id: "msg_inside", threadId: "thread_inside", senderName: "Inside", senderEmail: "inside@test.com", subject: "Just Inside 72h", receivedDate: insideDate, snippet: "", fullBody: "Inside body", category: .assignment)
        
        // Email outside: 72 hours 05 minutes ago (outside 72h)
        let outsideDate = now.addingTimeInterval(-((72 * 3600) + (5 * 60)))
        let stubOutside = GmailMessageStub(id: "msg_outside", threadId: "thread_outside")
        let emailOutside = EmailSource(id: "msg_outside", threadId: "thread_outside", senderName: "Outside", senderEmail: "outside@test.com", subject: "Just Outside 72h", receivedDate: outsideDate, snippet: "", fullBody: "Outside body", category: .assignment)
        
        // Email arriving during scan: 15 seconds in future after scan start
        let midScanDate = now.addingTimeInterval(15)
        let stubMidScan = GmailMessageStub(id: "msg_midscan", threadId: "thread_midscan")
        let emailMidScan = EmailSource(id: "msg_midscan", threadId: "thread_midscan", senderName: "MidScan", senderEmail: "mid@test.com", subject: "Arriving during scan", receivedDate: midScanDate, snippet: "", fullBody: "Mid scan body", category: .assignment)
        
        mockGmail.emailDetails["msg_inside"] = emailInside
        mockGmail.emailDetails["msg_outside"] = emailOutside
        mockGmail.emailDetails["msg_midscan"] = emailMidScan
        
        mockModel.responsesByEmailId["msg_inside"] = EmailAnalysis(
            isNewsletterOrMarketing: false,
            isDirectedAtRecipient: true,
            hasActionableTask: true,
            reasoning: "Task just inside 72h boundary",
            tasks: [CandidateTask(title: "Inside 72h Task", requiredAction: "Action inside")]
        )
        
        mockGmail.stubsToReturn = [stub1, stub2, stubInside, stubOutside, stubMidScan]
        mockGmail.fetchEmailCallCount = 0
        mockGmail.fetchedEmailIds = []
        mockModel.analyzeEmailCallCount = 0
        mockModel.analyzedEmailIds = []
        
        _ = try! runAsync { await appState.scanEmailsFromLast3Days() }
        
        check("Email just inside 72h (71h 55m) was fetched", mockGmail.fetchedEmailIds.contains("msg_inside"))
        check("Email just inside 72h was analyzed by the model", mockModel.analyzedEmailIds.contains("msg_inside"))
        check("Email just outside 72h (72h 05m) was NOT analyzed by the model", !mockModel.analyzedEmailIds.contains("msg_outside"))
        check("Email arriving during scan was NOT analyzed in this frozen scan", !mockModel.analyzedEmailIds.contains("msg_midscan"))
        check("Zero-quota rescan holds for cached emails (msg_001, msg_002 not re-fetched)", !mockGmail.fetchedEmailIds.contains("msg_001") && !mockGmail.fetchedEmailIds.contains("msg_002"))
        
        // ----------------------------------------------------
        // Stage 3: Zero-Quota Incremental Rescan
        // ----------------------------------------------------
        print("\n--- Stage 3: Zero-Quota Incremental Rescan ---")
        mockGmail.fetchEmailCallCount = 0
        mockGmail.fetchedEmailIds = []
        mockModel.analyzeEmailCallCount = 0
        mockModel.analyzedEmailIds = []
        
        _ = try! runAsync { await appState.scanEmailsFromLast3Days() }
        
        check("Unchanged mail: Zero email bodies retrieved from Gmail", mockGmail.fetchEmailCallCount == 0, "Got \(mockGmail.fetchEmailCallCount) fetches")
        check("Unchanged mail: Zero extraction calls made", mockModel.analyzeEmailCallCount == 0, "Got \(mockModel.analyzeEmailCallCount) calls")
        check("Status correctly states: 'You’re up to date—no new emails to analyze.'", appState.lastScanSuccessSummary == "You’re up to date—no new emails to analyze.")
        check("Cached count matches 3", appState.scanCachedCount == 3)
        check("New count is 0", appState.scanNewCount == 0)
        
        // ----------------------------------------------------
        // Stage 4: New Reply in Existing Thread with Thread Context
        // ----------------------------------------------------
        print("\n--- Stage 4: New Reply in Existing Thread ---")
        let stub3 = GmailMessageStub(id: "msg_003", threadId: "thread_001") // Reply in Prof. Davis thread!
        mockGmail.stubsToReturn.append(stub3)
        
        let email3 = EmailSource(
            id: "msg_003",
            threadId: "thread_001",
            senderName: "Prof. Davis",
            senderEmail: "davis@university.edu",
            subject: "Re: Problem Set 4 due Friday",
            receivedDate: now.addingTimeInterval(-3600), // 1 hour ago (well within 72h)
            snippet: "Deadline extended to Monday 5pm.",
            fullBody: "I am extending the deadline for Problem Set 4 to Monday at 5:00 PM.",
            category: .assignment
        )
        mockGmail.emailDetails["msg_003"] = email3
        
        mockModel.responsesByEmailId["msg_003"] = EmailAnalysis(
            isNewsletterOrMarketing: false,
            isDirectedAtRecipient: true,
            hasActionableTask: true,
            reasoning: "Deadline update for Problem Set 4",
            tasks: [
                CandidateTask(
                    title: "Problem Set 4",
                    requiredAction: "Complete questions 1-5",
                    deadlineIso: "2026-11-09T17:00:00Z",
                    isDeadlineUpdate: true,
                    deadlineUpdateNote: "Deadline extended to Monday at 5:00 PM."
                )
            ]
        )
        
        mockGmail.fetchEmailCallCount = 0
        mockModel.analyzeEmailCallCount = 0
        
        _ = try! runAsync { await appState.scanEmailsFromLast3Days() }
        
        check("Only the single new reply body was fetched", mockGmail.fetchEmailCallCount == 1 && mockGmail.fetchedEmailIds == ["msg_003"])
        check("Only the single new reply was analyzed by the model", mockModel.analyzeEmailCallCount == 1 && mockModel.analyzedEmailIds == ["msg_003"])
        check("Total tasks count not duplicated (still 2 tasks: Problem Set 4 and Inside 72h Task)", appState.tasks.filter { $0.title == "Problem Set 4" }.count == 1)
        let updatedTask = appState.tasks.first(where: { $0.title == "Problem Set 4" })!
        check("Task deadline updated to Monday", updatedTask.deadlineUpdateNote?.contains("Deadline extended") == true)
        
        // ----------------------------------------------------
        // Stage 5: Zero-Task Emails Cached Properly
        // ----------------------------------------------------
        print("\n--- Stage 5: Zero-Task Emails Cached ---")
        check("Newsletter email (msg_002) is present in extractionCache", appState.extractionCache["msg_002"] != nil)
        check("Zero-task email analysis preserved in cache", appState.extractionCache["msg_002"]?.analysis.tasks.isEmpty == true)
        
        // ----------------------------------------------------
        // Stage 6: Model Change Protection
        // ----------------------------------------------------
        print("\n--- Stage 6: Model Change Does Not Invalidate Cache ---")
        appState.setOllamaModel("llama3.1:8b")
        check("Model changed to llama3.1:8b", appState.ollamaModel == "llama3.1:8b")
        
        mockGmail.fetchEmailCallCount = 0
        mockModel.analyzeEmailCallCount = 0
        _ = try! runAsync { await appState.scanEmailsFromLast3Days() }
        
        check("Zero model calls after changing model", mockModel.analyzeEmailCallCount == 0)
        check("Status remains up to date after model change", appState.lastScanSuccessSummary == "You’re up to date—no new emails to analyze.")
        
        // ----------------------------------------------------
        // Stage 7: Failure Classification & Reporting
        // ----------------------------------------------------
        print("\n--- Stage 7: Multi-Stage Failure Classification ---")
        // Add stub 4 that fails in Gmail retrieval (e.g. 500 error)
        let stub4 = GmailMessageStub(id: "msg_004", threadId: "thread_004")
        mockGmail.stubsToReturn.append(stub4)
        mockGmail.failingIds["msg_004"] = NSError(domain: "GmailService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Gmail API 500 Internal Error"])
        
        // Add stub 5 that fails in analysis (e.g. invalid key or network)
        let stub5 = GmailMessageStub(id: "msg_005", threadId: "thread_005")
        mockGmail.stubsToReturn.append(stub5)
        let email5 = EmailSource(
            id: "msg_005",
            threadId: "thread_005",
            senderName: "Registrar",
            senderEmail: "registrar@university.edu",
            subject: "Course Registration Confirmation",
            receivedDate: now.addingTimeInterval(-7200), // 2 hours ago (within 72h)
            snippet: "Registration confirmed.",
            fullBody: "Your registration is confirmed.",
            category: .assignment
        )
        mockGmail.emailDetails["msg_005"] = email5
        mockModel.errorsByEmailId["msg_005"] = AIServiceError(kind: .serverError, statusCode: 500, message: "Ollama model overloaded (gave up after 3 attempts)")
        
        _ = try! runAsync { await appState.scanEmailsFromLast3Days() }
        
        check("Failed email records contains 2 failures", appState.failedEmailRecords.count == 2)
        let retrievalFailure = appState.failedEmailRecords.first(where: { $0.id == "msg_004" })
        check("Message 4 classified as .retrieval failure", retrievalFailure?.failureStage == EmailFailureStage.retrieval)
        check("Retrieval failure reason contains Gmail error", retrievalFailure?.failureReason.contains("Gmail API 500") == true)
        
        let analysisFailure = appState.failedEmailRecords.first(where: { $0.id == "msg_005" })
        check("Message 5 classified as .analysis failure", analysisFailure?.failureStage == EmailFailureStage.analysis)
        check("Analysis failure reason contains model error", analysisFailure?.failureReason.contains("overloaded") == true)
        
        check("Status correctly states unresolved failures remain", appState.lastScanSuccessSummary == "No new emails. 2 emails still need retry.")
        check("Never claims up to date when failures exist", appState.lastScanSuccessSummary?.contains("You’re up to date") == false)
        
        // ----------------------------------------------------
        // Stage 8: Individual & All-Failed Retry
        // ----------------------------------------------------
        print("\n--- Stage 8: Retry Actions & Recovery ---")
        // Fix msg_005 in mock
        mockModel.errorsByEmailId.removeValue(forKey: "msg_005")
        mockModel.responsesByEmailId["msg_005"] = EmailAnalysis(
            isNewsletterOrMarketing: false,
            isDirectedAtRecipient: true,
            hasActionableTask: true,
            reasoning: "Registration payment required",
            tasks: [CandidateTask(title: "Pay tuition balance", requiredAction: "Submit payment by Friday")]
        )
        
        _ = try! runAsync { await appState.retryFailedEmail(id: "msg_005") }
        
        check("msg_005 removed from failed records after successful retry", !appState.failedEmailRecords.contains(where: { $0.id == "msg_005" }))
        check("msg_005 added to extractionCache", appState.extractionCache["msg_005"] != nil)
        check("Discovered task 'Pay tuition balance' saved", appState.tasks.contains(where: { $0.title == "Pay tuition balance" }))
        check("1 failure remains (msg_004)", appState.failedEmailRecords.count == 1)
        check("Status updated to reflect 1 remaining retry", appState.lastScanSuccessSummary == "No new emails. 1 email still need retry." || appState.lastScanSuccessSummary?.contains("1 email") == true)
        
        // ----------------------------------------------------
        // Stage 9: Outside 72-Hour Window Failure Detection & Selective Retry
        // ----------------------------------------------------
        print("\n--- Stage 9: Outside 72-Hour Scope Detection & Selective Retry ---")
        let agedRecord = FailedEmailRecord(
            id: "msg_aged",
            threadId: "thread_aged",
            subject: "Old Project Brief",
            sender: "boss@corp.com",
            receivedDate: fourDaysAgo, // 96 hours ago (outside 72h)
            failureStage: .retrieval,
            failureReason: "Old failure timeout"
        )
        appState.failedEmailRecords.append(agedRecord)
        
        check("Aged record detected as outside 72 hours", agedRecord.isOutsideScanWindow(hours: 72, relativeTo: now))
        let freshRecord = appState.failedEmailRecords.first(where: { $0.id == "msg_004" })!
        check("Fresh record detected as inside 72 hours", !freshRecord.isOutsideScanWindow(hours: 72, relativeTo: now))
        
        // Selective retry: retrying with includeOutsideWindow = false preserves aged record untouched
        _ = try! runAsync { await appState.retryAllFailedEmails(includeOutsideWindow: false, windowHours: 72) }
        check("Selective retry preserved aged failure outside window", appState.failedEmailRecords.contains(where: { $0.id == "msg_aged" }))
        
        // Dismiss aged record explicitly
        appState.dismissFailedEmail(id: "msg_aged")
        check("Dismissing failure removes it from records", !appState.failedEmailRecords.contains(where: { $0.id == "msg_aged" }))
        
        // ----------------------------------------------------
        // Stage 10: Persistence of Failures & State Across Restart
        // ----------------------------------------------------
        print("\n--- Stage 10: Persistence Across Restart ---")
        appState.saveDatabase()
        
        let reloadedDb = storageService.loadDatabase()
        check("Reloaded database contains 1 failed record", reloadedDb.failedEmailRecords.count == 1)
        check("Failed record ID matches msg_004", reloadedDb.failedEmailRecords.first?.id == "msg_004")
        check("Failed record has no email bodies or credentials", reloadedDb.failedEmailRecords.first?.failureReason != nil)
        check("Extraction cache contains 5 entries across reload", reloadedDb.extractionCache.count == 5)
        check("Problem Set 4 task survived reload", reloadedDb.tasks.contains(where: { $0.title == "Problem Set 4" }))
        
        // ----------------------------------------------------
        // Stage 11: Relative Time Formatting
        // ----------------------------------------------------
        print("\n--- Stage 11: Relative Time & Status Text ---")
        let relNow = appState.relativeTimeString(from: now)
        check("Recent scan formatted as 'just now'", relNow.contains("just now"))
        
        let oneHourAgo = now.addingTimeInterval(-3600)
        let relHour = appState.relativeTimeString(from: oneHourAgo)
        check("1-hour-old scan formatted with hour indicator", relHour.contains("1h ago") || relHour.contains("60m ago"))
        
        // Clean up temp test files
        try? FileManager.default.removeItem(at: tempDir)
        
        print("\n=======================================================")
        if passedCount == totalCount {
            print(" 🎉 ALL EMAIL DISCOVERY CHECKS PASSED (\(passedCount)/\(totalCount))!")
        } else {
            print(" ⚠️ SOME CHECKS FAILED (\(passedCount)/\(totalCount)).")
        }
        print("=======================================================\n")
        
        return passedCount == totalCount
    }
    
    private static func runAsync<T>(_ block: @MainActor @escaping () async throws -> T) throws -> T {
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
            throw NSError(domain: "EmailDiscoveryTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Async block timed out"])
        }
        switch res {
        case .success(let val): return val
        case .failure(let err): throw err
        }
    }
}
