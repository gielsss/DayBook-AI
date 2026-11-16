import Foundation
import Combine
import AppKit

public enum AppTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case tasks = "Tasks"
    case week = "Week"
    case settings = "Settings"
    
    public var id: String { rawValue }
    
    public var systemImage: String {
        switch self {
        case .today: return "calendar.day.timeline.left"
        case .tasks: return "checklist"
        case .week: return "calendar"
        case .settings: return "gearshape"
        }
    }
}


public struct ScheduleUndoSnapshot {
    public let tasks: [DiscoveredTask]
    public let workSessions: [WorkSession]
    public let deletedProposedMinutesByTaskId: [String: Int]
    public let description: String
    public let timestamp: Date
    
    public init(
        tasks: [DiscoveredTask],
        workSessions: [WorkSession],
        deletedProposedMinutesByTaskId: [String: Int],
        description: String,
        timestamp: Date = Date()
    ) {
        self.tasks = tasks
        self.workSessions = workSessions
        self.deletedProposedMinutesByTaskId = deletedProposedMinutesByTaskId
        self.description = description
        self.timestamp = timestamp
    }
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var selectedTab: AppTab = .today
    @Published public var tasks: [DiscoveredTask] = []
    @Published public var workSessions: [WorkSession] = []
    @Published public var commitments: [CalendarCommitment] = []
    @Published public var logs: [EmailProcessingLog] = []
    @Published public var preferences: UserPreferences = UserPreferences()
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncMessage: String? = nil
    @Published public var selectedTaskId: UUID? = nil
    @Published public var showDiscoveryLogSheet: Bool = false
    @Published public var clearedDismissedTasks: [DismissedTaskRecord] = []
    
    // Live Gmail Connection state
    @Published public var isGmailAuthenticated: Bool = false
    @Published public var hasGmailClientConfig: Bool = false
    @Published public var recentGmailEmails: [RecentEmailSummary] = []
    @Published public var isAuthenticatingGmail: Bool = false
    @Published public var isFetchingRecentEmails: Bool = false
    @Published public var gmailStatusMessage: String? = nil
    @Published public var gmailErrorMessage: String? = nil
    
    // Local AI (Ollama) state — used for email scanning, Quick Capture and receipts
    @Published public var currentActiveProcessingModel: String? = nil
    @Published public var extractionCache: [String: CachedEmailExtraction] = [:]
    @Published public var ollamaModel: String = OllamaDefaults.model
    @Published public var ollamaBaseURL: String = OllamaDefaults.baseURL
    @Published public var ollamaInstalledModels: [String] = []
    @Published public var isTestingOllama: Bool = false
    @Published public var ollamaTestSuccessMessage: String? = nil
    @Published public var ollamaTestErrorMessage: String? = nil
    
    // Canvas LMS
    @Published public var isCanvasConnected: Bool = false
    @Published public var canvasUserName: String = ""
    @Published public var isSyncingCanvas: Bool = false
    @Published public var isCanvasSyncCancelled: Bool = false
    @Published public var canvasStatusMessage: String? = nil
    @Published public var canvasErrorMessage: String? = nil
    @Published public var lastCanvasSyncDate: Date? = nil
    @Published public var showCanvasSignInSheet: Bool = false
    
    // Gradescope (read through a signed-in browser tab)
    @Published public var isSyncingGradescope: Bool = false
    // Sync Everything
    @Published public var isSyncingAll: Bool = false
    @Published public var syncAllProgress: String? = nil
    @Published public var lastSyncAllResults: [SyncSourceResult] = []
    /// What the automatic re-plan after Sync Everything changed ("Essay Draft added Tue 2:00 PM").
    @Published public var lastSyncPlanChanges: [String] = []
    /// True while Sync Everything runs: its re-plans keep today's sessions in place (see keepTodaySteadyUntil).
    public var isSyncReplanning: Bool = false
    /// Test seam: receives the evening check-in sessions instead of posting notifications.
    public var eveningCheckInSender: (([WorkSession]) -> Void)? = nil
    /// Test seam: receives the morning summary instead of posting a notification.
    public var morningSummarySender: ((String, String) -> Void)? = nil
    /// Test seam: replaces opening Canvas / Gradescope tabs in a real browser.
    public var browserTabPreparerOverride: ((CanvasBrowser, URL, [String]) async -> BrowserTabOpener.Preparation)? = nil
    var autoSyncTimer: Timer? = nil
    var wakeObserver: NSObjectProtocol? = nil
    @Published public var gradescopeStatusMessage: String? = nil
    @Published public var gradescopeErrorMessage: String? = nil
    /// Test hook: replaces reading the real browser tab.
    public var gradescopeReadOverride: ((CanvasBrowser) async throws -> [GradescopeAssignment])? = nil
    /// Live status shown inside the sign-in window (diagnostics only; never contains secrets).
    @Published public var canvasSignInDetail: String? = nil
    var canvasLastVerifyReply: String? = nil
    
    // Scan Counters & Countdown State
    @Published public var scanTotalInboxCount: Int = 0
    @Published public var scanNewCount: Int = 0
    @Published public var scanProcessedCount: Int = 0
    @Published public var scanCachedCount: Int = 0
    @Published public var scanPendingCount: Int = 0
    @Published public var scanFailedCount: Int = 0
    @Published public var isScanCancelled: Bool = false
    @Published public var lastAnalyzedEmailItems: [AnalyzedEmailSummaryItem] = []
    @Published public var showAnalyzedEmailsSheet: Bool = false
    @Published public var failedEmailRecords: [FailedEmailRecord] = []
    @Published public var showFailedEmailsSheet: Bool = false
    
    @Published public var isScanningEmails: Bool = false
    @Published public var scanProgressText: String? = nil
    @Published public var lastScanDate: Date? = nil
    @Published public var lastScanError: String? = nil
    @Published public var lastScanRange: String? = nil
    @Published public var lastScanCoverage: String = "Analyzing inbox emails from the last 3 days (72h) (attachments are not analyzed)."
    @Published public var lastScanSuccessSummary: String? = nil
    
    // Apple Calendar (EventKit) Live Integration State
    @Published public var calendarAuthorizationStatus: CalendarAuthorizationStatus = .notDetermined
    @Published public var availableCalendars: [CalendarAccountInfo] = []
    @Published public var selectedCalendarIds: Set<String> = []
    @Published public var allDayEventsBlockTime: Bool = false
    @Published public var isRefreshingCalendar: Bool = false
    @Published public var calendarStatusMessage: String? = nil
    @Published public var calendarErrorMessage: String? = nil
    @Published public var lastCalendarRefreshDate: Date? = nil
    
    // Work Schedule Generation & Management State
    @Published public var lastSchedulingResult: SchedulingResult? = nil
    @Published public var isGeneratingSchedule: Bool = false
    @Published public var schedulingStatusMessage: String? = nil
    @Published public var showUnscheduledSheet: Bool = false
    @Published public var sessionBeingEdited: WorkSession? = nil
    @Published public var deletedProposedMinutesByTaskId: [String: Int] = [:]
    /// Times where you deleted planned work; the planner won't use them again.
    @Published public var declinedSlots: [DeclinedSlot] = []
    /// Tasks a sync found for the first time, not looked at yet (see AppState+NewTasks.swift).
    @Published public var newlyFoundTaskIds: [UUID] = []
    /// Finished tasks waiting for "How long did it take?" (Today).
    @Published public var timeQuestions: [TimeQuestion] = []
    /// The on-screen "New tasks found" panel.
    @Published public var showNewTasksPanel: Bool = false
    /// Missed sessions already re-planned for (see AppState+CatchUp.swift); not saved.
    var knownMissedSessionIds: Set<UUID> = []
    /// Nesting depth of syncs, so a sync inside Sync Everything doesn't report separately.
    var newTaskTrackingDepth = 0
    /// Test seam: receives the system notification for new tasks instead of posting it.
    public var newTasksNotificationSender: ((String, String) -> Void)? = nil
    @Published public var lastBackupDate: Date? = nil
    @Published public var backupErrorMessage: String? = nil
    /// Test seam: tests delete their temporary files instead of filling the user's Trash.
    public var receiptCleanupUsesTrash: Bool = true
    
    // Carryover & Same-Day Replan State
    @Published public var lastUndoSnapshot: ScheduleUndoSnapshot? = nil
    @Published public var replanExplanation: String? = nil
    @Published public var sessionForCarryover: WorkSession? = nil
    @Published public var showCarryoverSheet: Bool = false
    @Published public var showEndOfDayReviewSheet: Bool = false
    @Published public var showCreateActivitySheet: Bool = false
    
    // Apple Calendar Publishing & Discrepancy State
    @Published public var publicationCalendarInfo: CalendarAccountInfo? = nil
    @Published public var isPublishingCalendar: Bool = false
    @Published public var publishStatusMessage: String? = nil
    @Published public var publishErrorMessage: String? = nil
    @Published public var externalDiscrepancies: [ExternalDiscrepancy] = []
    @Published public var showReviewAndPublishSheet: Bool = false
    @Published public var showDiscrepancySheet: Bool = false
    @Published public var lastPublishedDate: Date? = nil
    @Published public var pendingRemovalSessions: [WorkSession] = []
    
    
    // Quick Capture State
    @Published public var quickCaptureDraft: QuickCaptureDraft = QuickCaptureDraft()
    @Published public var quickCaptureProposals: [QuickCaptureProposal] = []
    @Published public var isAnalyzingQuickCapture: Bool = false
    @Published public var quickCaptureError: String? = nil
    @Published public var quickCaptureActiveModel: String? = nil
    @Published public var showQuickCaptureSheet: Bool = false
    
    public let quickCaptureService: QuickCaptureService
    public let quickCaptureStorageService: QuickCaptureStorageService
    
    public let storageService: StorageServiceProtocol
    public let emailService: EmailRetrievalServiceProtocol
    public let extractionService: TaskExtractionServiceProtocol
    public let calendarService: CalendarServiceProtocol
    public let schedulingEngine: SchedulingEngineProtocol
    public let keychainService: KeychainServiceProtocol
    public let gmailService: GmailServiceProtocol
    public let ollamaService: OllamaExtractionServiceProtocol
    public let canvasReader: CanvasReading
    let canvasURLSession: URLSession
    /// Session sign-ins are replayed through a hidden WebKit page in the app; test runs use URLSession stubs.
    let canvasUsesBrowserEngine: Bool
    /// Test hook: replaces the browser-tab transport (production talks to the real browser).
    public var canvasBrowserTransportFactory: ((CanvasBrowser, String) -> CanvasTransport)? = nil
    
    private var retryStoppedByFatalError = false
    
    public init(
        storageService: StorageServiceProtocol = StorageService(),
        emailService: EmailRetrievalServiceProtocol = SimulatedEmailRetrievalService(),
        extractionService: TaskExtractionServiceProtocol = SimulatedTaskExtractionService(),
        calendarService: CalendarServiceProtocol? = nil,
        schedulingEngine: SchedulingEngineProtocol = RuleBasedSchedulingEngine(),
        keychainService: KeychainServiceProtocol = KeychainService(),
        gmailService: GmailServiceProtocol? = nil,
        ollamaService: OllamaExtractionServiceProtocol? = nil,
        canvasReader: CanvasReading? = nil,
        canvasURLSession: URLSession = .shared,
        addOns: AddOnServices = AddOnServices(),
        quickCaptureService: QuickCaptureService? = nil,
        quickCaptureStorageService: QuickCaptureStorageService? = nil
    ) {
        self.storageService = storageService
        self.emailService = emailService
        self.extractionService = extractionService
        let isTesting = CommandLine.arguments.contains("--test-persistence") ||
                        CommandLine.arguments.contains("--test-finances") ||  // Finances add-on suite
                        CommandLine.arguments.contains("--test-quick-capture") ||
                        CommandLine.arguments.contains("--test-email-discovery") ||
                        CommandLine.arguments.contains("--test-ollama") ||
                        CommandLine.arguments.contains("--test-canvas") ||
                        CommandLine.arguments.contains("--test-milestone-improvements") ||
                        CommandLine.arguments.contains("--demo-carryover") ||
                        CommandLine.arguments.contains("--render-ui") ||
                        CommandLine.arguments.contains("--eval-estimates")
        let resolvedCalendar: CalendarServiceProtocol = calendarService ?? (isTesting ? SimulatedCalendarService() : EventKitCalendarService())
        self.calendarService = resolvedCalendar
        self.schedulingEngine = schedulingEngine
        // Test runs never touch the real Keychain (no prompts, no access to real credentials).
        let resolvedKeychain: KeychainServiceProtocol = (isTesting && keychainService is KeychainService) ? InMemoryKeychainService() : keychainService
        self.keychainService = resolvedKeychain
        let resolvedGmail = gmailService ?? GmailService(oauthService: GoogleOAuthService(keychainService: resolvedKeychain))
        self.gmailService = resolvedGmail
        let ollamaClient = OllamaClient()
        self.ollamaService = ollamaService ?? OllamaExtractionService(client: ollamaClient)
        self.canvasReader = canvasReader ?? CanvasReader(attachmentReader: CanvasAttachmentReader(session: isTesting ? canvasURLSession : URLSession(configuration: .ephemeral)))
        self.canvasURLSession = canvasURLSession
        self.canvasUsesBrowserEngine = !isTesting
        self.quickCaptureService = quickCaptureService ?? QuickCaptureService(client: ollamaClient)
        self.quickCaptureStorageService = quickCaptureStorageService ?? QuickCaptureStorageService()
        
        loadDatabase()
        checkGmailStatus()
        loadCanvasConnection()
        self.lastCanvasSyncDate = self.preferences.lastCanvasSyncDate
        
        self.calendarAuthorizationStatus = resolvedCalendar.authorizationStatus
        self.allDayEventsBlockTime = self.preferences.allDayEventsBlockTime
        self.selectedCalendarIds = Set(self.preferences.selectedCalendarIdentifiers)
        
        self.calendarService.onCalendarStoreChanged = { [weak self] in
            Task { @MainActor in
                await self?.refreshCalendarCommitments(isAutomatic: true)
            }
        }
        
        if !isTesting && self.calendarAuthorizationStatus == .authorized {
            Task {
                await self.loadAvailableCalendars()
                await self.refreshCalendarCommitments(isAutomatic: true)
            }
        }
        
        if !isTesting && self.isGmailAuthenticated {
            Task {
                await self.fetchRecentGmailEmails()
            }
        }
        
        if !isTesting {
            runDailyBackupIfDue()
            startAutoSync()
        }
        self.lastBackupDate = backupService.latestBackupDate
    }
    
    public func loadDatabase() {
        let db = storageService.loadDatabase()
        self.tasks = db.tasks
        self.workSessions = db.workSessions
        self.commitments = db.calendarCommitments
        self.logs = db.processedLogs
        self.preferences = db.preferences
        self.ollamaModel = db.preferences.ollamaModel
        self.ollamaBaseURL = db.preferences.ollamaBaseURL
        self.extractionCache = db.extractionCache
        self.failedEmailRecords = db.failedEmailRecords
        self.scanFailedCount = self.failedEmailRecords.count
        self.lastScanDate = db.lastScanDate
        self.lastScanError = db.lastScanError
        self.lastScanRange = db.lastScanRange
        self.pendingRemovalSessions = db.pendingRemovalSessions
        self.clearedDismissedTasks = db.clearedDismissedTasks
        // Deleting a session no longer takes its minutes off the task (the work is re-planned elsewhere and
        // only the deleted time is avoided), so minutes subtracted by earlier deletions are given back.
        self.deletedProposedMinutesByTaskId = [:]
        self.declinedSlots = db.declinedSlots
        pruneDeclinedSlots()
        self.newlyFoundTaskIds = db.newlyFoundTaskIds
        self.timeQuestions = db.timeQuestions
        if let cov = db.lastScanCoverage, !cov.isEmpty {
            self.lastScanCoverage = cov
        }
        
        // Migrate & clean task provenance, timezones, wording & planning targets
        var dbNeedsMigrationSave = false
        
        // Automatically purge demonstration data if real discovered tasks exist
        let hasRealTasks = self.tasks.contains { !$0.sourceEmail.isSimulatedDemo }
        if hasRealTasks {
            let initialCount = self.tasks.count
            self.tasks.removeAll { $0.sourceEmail.isSimulatedDemo }
            self.workSessions.removeAll { $0.isSimulatedDemo }
            self.commitments.removeAll { $0.isSimulatedDemo }
            if self.tasks.count != initialCount {
                dbNeedsMigrationSave = true
            }
        }
        for i in self.tasks.indices {
            let task = self.tasks[i]
            let lower = task.supportingExcerpt.lowercased()
            
            // 1. Check CATME date-only deadline
            if lower.contains("closing on monday") {
                self.tasks[i].isDateOnlyDeadline = true
                self.tasks[i].dateOnlyDeadlineString = "2026-11-02"
                self.tasks[i].originalDeadlineWording = "closing on Monday Nov 02nd:"
                self.tasks[i].timeZoneAssumption = "\(self.preferences.timeZoneIdentifier) (Evaluated with \(self.preferences.dateOnlyDeadlinePolicy.shortTitle) policy)"
                
                let cutoff = DeadlinesResolver.calculateDateOnlyCutoff(
                    dateStr: "2026-11-02",
                    timeZone: self.preferences.timeZone,
                    policy: self.preferences.dateOnlyDeadlinePolicy,
                    endHour: self.preferences.workEndHour,
                    endMinute: self.preferences.workEndMinute,
                    startHour: self.preferences.workStartHour,
                    startMinute: self.preferences.workStartMinute
                )
                self.tasks[i].extractedDeadline = cutoff
                self.tasks[i].isDeadlineSupportedByEmail = true
                dbNeedsMigrationSave = true
            }
            // 2. Check "Wednesday at 6pm" (Tim Richards meeting response)
            else if lower.contains("wednesday at 6pm") {
                let resolved = DeadlinesResolver.resolve(
                    rawDeadlineIso: nil,
                    supportingExcerpt: task.supportingExcerpt,
                    emailReceivedDate: task.sourceEmail.receivedDate,
                    configuredTimeZone: self.preferences.timeZone,
                    dateOnlyPolicy: self.preferences.dateOnlyDeadlinePolicy,
                    workdayEndHour: self.preferences.workEndHour,
                    workdayEndMinute: self.preferences.workEndMinute,
                    workdayStartHour: self.preferences.workStartHour,
                    workdayStartMinute: self.preferences.workStartMinute
                )
                if let newDate = resolved.deadlineDate {
                    self.tasks[i].extractedDeadline = newDate
                    self.tasks[i].isDeadlineSupportedByEmail = true
                    self.tasks[i].originalDeadlineWording = resolved.originalWording ?? "Wednesday at 6pm"
                    self.tasks[i].timeZoneAssumption = resolved.timeZoneAssumption
                    dbNeedsMigrationSave = true
                }
            }
            // 3. Check "This Friday at 11:59 PM" (CS 420 Lab 3)
            else if lower.contains("this friday at 11:59 pm") {
                let resolved = DeadlinesResolver.resolve(
                    rawDeadlineIso: nil,
                    supportingExcerpt: task.supportingExcerpt,
                    emailReceivedDate: task.sourceEmail.receivedDate,
                    configuredTimeZone: self.preferences.timeZone,
                    dateOnlyPolicy: self.preferences.dateOnlyDeadlinePolicy,
                    workdayEndHour: self.preferences.workEndHour,
                    workdayEndMinute: self.preferences.workEndMinute,
                    workdayStartHour: self.preferences.workStartHour,
                    workdayStartMinute: self.preferences.workStartMinute
                )
                if let newDate = resolved.deadlineDate {
                    self.tasks[i].extractedDeadline = newDate
                    self.tasks[i].isDeadlineSupportedByEmail = true
                    self.tasks[i].originalDeadlineWording = resolved.originalWording ?? "This Friday at 11:59 PM"
                    self.tasks[i].timeZoneAssumption = resolved.timeZoneAssumption
                    dbNeedsMigrationSave = true
                }
            }
            // 4. Check "within 24 hours" (ZIPAIR)
            else if lower.contains("within 24 hours") {
                self.tasks[i].originalDeadlineWording = "within 24 hours"
                self.tasks[i].timeZoneAssumption = "Elapsed 24 hours from email receipt timestamp"
                let elapsed = task.sourceEmail.receivedDate.addingTimeInterval(24 * 3600)
                self.tasks[i].extractedDeadline = elapsed
                self.tasks[i].isDeadlineSupportedByEmail = true
                dbNeedsMigrationSave = true
            }
            // 5. Tim Richards sign up (no deadline in email)
            else if lower.contains("meet with tim for a meeting or for a meal") {
                if self.tasks[i].planningTargetDate == nil {
                    let savedTarget = self.tasks[i].userOverriddenDeadline ?? self.tasks[i].extractedDeadline
                    self.tasks[i].planningTargetDate = savedTarget
                }
                self.tasks[i].extractedDeadline = nil
                self.tasks[i].isDeadlineSupportedByEmail = false
                self.tasks[i].userOverriddenDeadline = nil
                self.tasks[i].originalDeadlineWording = "None stated in email"
                self.tasks[i].timeZoneAssumption = "None (Email contains no deadline)"
                dbNeedsMigrationSave = true
            }
            // 6. Generic resolution if wording is missing
            else if self.tasks[i].originalDeadlineWording == nil {
                let resolved = DeadlinesResolver.resolve(
                    rawDeadlineIso: nil,
                    supportingExcerpt: task.supportingExcerpt,
                    emailReceivedDate: task.sourceEmail.receivedDate,
                    configuredTimeZone: self.preferences.timeZone,
                    dateOnlyPolicy: self.preferences.dateOnlyDeadlinePolicy,
                    workdayEndHour: self.preferences.workEndHour,
                    workdayEndMinute: self.preferences.workEndMinute,
                    workdayStartHour: self.preferences.workStartHour,
                    workdayStartMinute: self.preferences.workStartMinute
                )
                self.tasks[i].originalDeadlineWording = resolved.originalWording
                self.tasks[i].timeZoneAssumption = resolved.timeZoneAssumption
                if resolved.isDateOnly {
                    self.tasks[i].isDateOnlyDeadline = true
                    self.tasks[i].dateOnlyDeadlineString = resolved.dateOnlyString
                }
                dbNeedsMigrationSave = true
            }
        }
        // 7. Check if any planningTargetDate was set to previous DatePicker artifact (Nov 4 between 11:00 AM and 12:00 PM PST)
        // Adjust to End of Workday (5:00 PM PST) so the full workday is available for scheduling
        for i in 0..<self.tasks.count {
            if let pt = self.tasks[i].planningTargetDate {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime]
                let ptStr = iso.string(from: pt)
                if ptStr.hasPrefix("2026-11-04T19:12") || ptStr.hasPrefix("2026-11-04T19:13") {
                    var gCal = Calendar(identifier: .gregorian)
                    gCal.timeZone = self.preferences.timeZone
                    let endOfWorkday = gCal.date(
                        bySettingHour: self.preferences.workEndHour,
                        minute: self.preferences.workEndMinute,
                        second: 0,
                        of: pt
                    ) ?? pt
                    self.tasks[i].planningTargetDate = endOfWorkday
                    dbNeedsMigrationSave = true
                }
            }
        }
        if dbNeedsMigrationSave {
            saveDatabase()
            recalculateSchedule()
        }
        if self.selectedTaskId == nil {
            self.selectedTaskId = tasks.first?.id
        }
    }
    
    public func saveDatabase() {
        var db = PlannerDatabase(
            version: 3,
            tasks: self.tasks,
            workSessions: self.workSessions,
            calendarCommitments: self.commitments,
            processedLogs: self.logs,
            preferences: self.preferences,
            lastSyncDate: Date(),
            lastScanDate: self.lastScanDate,
            lastScanError: self.lastScanError,
            lastScanRange: self.lastScanRange,
            lastScanCoverage: self.lastScanCoverage,
            extractionCache: self.extractionCache,
            pendingRemovalSessions: self.pendingRemovalSessions,
            failedEmailRecords: self.failedEmailRecords,
            clearedDismissedTasks: self.clearedDismissedTasks,
            deletedProposedMinutesByTaskId: self.deletedProposedMinutesByTaskId,
            declinedSlots: self.declinedSlots,
            newlyFoundTaskIds: self.newlyFoundTaskIds
        )
        db.timeQuestions = self.timeQuestions
        do {
            try storageService.saveDatabase(db)
        } catch {
            print("⚠️ Error saving database: \(error)")
        }
    }
    
    public func resetToDemoData() {
        let db = storageService.resetDatabase()
        self.tasks = db.tasks
        self.workSessions = db.workSessions
        self.commitments = db.calendarCommitments
        self.logs = db.processedLogs
        self.preferences = db.preferences
        self.ollamaModel = db.preferences.ollamaModel
        self.ollamaBaseURL = db.preferences.ollamaBaseURL
        self.extractionCache = [:]
        self.pendingRemovalSessions = []
        self.deletedProposedMinutesByTaskId = [:]
        self.externalDiscrepancies = []
        self.publishStatusMessage = nil
        self.publishErrorMessage = nil
        self.lastScanDate = nil
        self.lastScanError = nil
        self.lastScanSuccessSummary = nil
        self.currentActiveProcessingModel = nil
        self.selectedTaskId = tasks.first?.id
        self.lastSyncMessage = "Reset to demonstration database."
    }
    
    public func cancelActiveScan() {
        guard isScanningEmails else { return }
        self.isScanCancelled = true
        self.scanProgressText = "Cancelling scan... preserving completed work."
    }
    
    // MARK: - Local AI (Ollama) Settings
    
    /// Ollama needs no key; the only requirement is a model name.
    public var isEmailExtractionConfigured: Bool {
        !ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public func setOllamaModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? OllamaDefaults.model : trimmed
        self.ollamaModel = resolved
        self.preferences.ollamaModel = resolved
        self.ollamaTestSuccessMessage = nil
        self.ollamaTestErrorMessage = nil
        saveDatabase()
    }
    
    public func setOllamaBaseURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? OllamaDefaults.baseURL : trimmed
        self.ollamaBaseURL = resolved
        self.preferences.ollamaBaseURL = resolved
        saveDatabase()
    }
    
    /// Refreshes the list of models downloaded in Ollama (empty if Ollama isn't running).
    public func refreshOllamaModels() async {
        do {
            self.ollamaInstalledModels = try await ollamaService.installedModels(baseURL: ollamaBaseURL)
        } catch {
            self.ollamaInstalledModels = []
        }
    }
    
    public func testOllamaConnection() async {
        isTestingOllama = true
        ollamaTestErrorMessage = nil
        ollamaTestSuccessMessage = nil
        do {
            ollamaTestSuccessMessage = try await ollamaService.testConnection(baseURL: ollamaBaseURL, model: ollamaModel)
        } catch {
            ollamaTestErrorMessage = error.localizedDescription
        }
        await refreshOllamaModels()
        isTestingOllama = false
    }
    
    /// Runs one Ollama analysis for an email, surfacing retry progress in the scan status line.
    private func analyzeEmailWithOllama(_ email: EmailSource, progressLabel: String?) async throws -> EmailAnalysis {
        let threadHistory = self.tasks.filter { $0.sourceEmail.threadId == email.threadId }.map { $0.sourceEmail }
        let threadTasks = self.tasks.filter { $0.sourceEmail.threadId == email.threadId }
        return try await ollamaService.analyzeEmail(
            email: email,
            threadContext: threadHistory,
            existingTasks: threadTasks,
            baseURL: ollamaBaseURL,
            model: ollamaModel,
            timeZone: preferences.timeZone,
            checkCancellation: { [weak self] in self?.isScanCancelled == true },
            onRetry: { [weak self] note in
                guard let self = self else { return }
                if let label = progressLabel {
                    self.scanProgressText = "\(label): \(note)"
                } else {
                    self.scanProgressText = note
                }
            }
        )
    }
    
    // MARK: - Gmail Auth & Management
    
    public func checkGmailStatus() {
        self.hasGmailClientConfig = gmailService.hasClientConfig
        let connected = gmailService.isConnected
        self.isGmailAuthenticated = connected
        self.preferences.isGmailConnected = connected
    }
    
    public func importGoogleCredentials(data: Data) -> Bool {
        do {
            let config = try gmailService.importClientConfig(from: data)
            checkGmailStatus()
            let projectIdStr = config.projectId.map { " (Project: \($0))" } ?? ""
            gmailStatusMessage = "Credentials imported successfully\(projectIdStr). Ready to sign in."
            gmailErrorMessage = nil
            return true
        } catch {
            gmailErrorMessage = "Failed to import credentials: \(error.localizedDescription)"
            return false
        }
    }
    
    public func connectGmail() async {
        isAuthenticatingGmail = true
        gmailErrorMessage = nil
        gmailStatusMessage = "Opening browser for Google sign-in..."
        
        do {
            try await gmailService.signIn()
            checkGmailStatus()
            saveDatabase()
            gmailStatusMessage = "Successfully connected to Gmail!"
            await fetchRecentGmailEmails()
        } catch {
            gmailErrorMessage = error.localizedDescription
            gmailStatusMessage = nil
        }
        
        isAuthenticatingGmail = false
    }
    
    public func disconnectGmail() {
        do {
            try gmailService.disconnect()
            recentGmailEmails = []
            checkGmailStatus()
            saveDatabase()
            gmailStatusMessage = "Gmail disconnected."
            gmailErrorMessage = nil
        } catch {
            gmailErrorMessage = "Failed to disconnect: \(error.localizedDescription)"
        }
    }
    
    public func fetchRecentGmailEmails() async {
        guard gmailService.isConnected else { return }
        isFetchingRecentEmails = true
        gmailErrorMessage = nil
        
        do {
            let summaries = try await gmailService.fetchRecentEmailSummaries(limit: 5)
            self.recentGmailEmails = summaries
            gmailStatusMessage = "Retrieved \(summaries.count) recent emails from Gmail."
        } catch {
            gmailErrorMessage = "Failed to fetch recent emails: \(error.localizedDescription)"
        }
        
        isFetchingRecentEmails = false
    }
    
    // MARK: - Live 7-Day Email Scan with Multi-Model Fallback, Caching & Failure Tracking
    
    public var lastCompletedCheckText: String {
        relativeTimeString(from: lastScanDate)
    }
    
    public func relativeTimeString(from date: Date?) -> String {
        guard let d = date else { return "Never" }
        let now = Date()
        let interval = now.timeIntervalSince(d)
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let timeStr = timeFormatter.string(from: d)
        
        let cal = Calendar.current
        let prefix: String
        if cal.isDateInToday(d) {
            prefix = "Today at \(timeStr)"
        } else if cal.isDateInYesterday(d) {
            prefix = "Yesterday at \(timeStr)"
        } else {
            let df = DateFormatter()
            df.dateStyle = .short
            df.timeStyle = .short
            prefix = df.string(from: d)
        }
        
        if interval < 60 {
            return "\(prefix) (just now)"
        } else if interval < 3600 {
            let mins = max(1, Int(interval / 60))
            return "\(prefix) (\(mins)m ago)"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(prefix) (\(hours)h ago)"
        } else {
            let days = Int(interval / 86400)
            return "\(prefix) (\(days)d ago)"
        }
    }
    
    public func testScanFiveEmails() async {
        await executeEmailScan(maxUncachedToAnalyze: 5)
    }
    
    public func scanEmailsFromLast3Days() async {
        let tracking = beginNewTaskTracking()
        defer { endNewTaskTracking(tracking) }
        await executeEmailScan(maxUncachedToAnalyze: nil)
    }
    
    // Retained for backward compatibility
    public func scanEmailsFromLast7Days() async {
        await scanEmailsFromLast3Days()
    }
    
    public func scanEmailsFromLast14Days() async {
        await scanEmailsFromLast3Days()
    }
    
    public func recordFailure(
        id: String,
        threadId: String,
        subject: String,
        sender: String,
        receivedDate: Date,
        stage: EmailFailureStage,
        reason: String
    ) {
        if let idx = self.failedEmailRecords.firstIndex(where: { $0.id == id }) {
            self.failedEmailRecords[idx].failureStage = stage
            self.failedEmailRecords[idx].failureReason = reason
            self.failedEmailRecords[idx].lastAttemptAt = Date()
            self.failedEmailRecords[idx].attemptCount += 1
            if !subject.isEmpty && subject != "(Unavailable)" {
                self.failedEmailRecords[idx].subject = subject
            }
            if !sender.isEmpty && sender != "Unknown" {
                self.failedEmailRecords[idx].sender = sender
            }
        } else {
            let record = FailedEmailRecord(
                id: id,
                threadId: threadId,
                subject: subject,
                sender: sender,
                receivedDate: receivedDate,
                failureStage: stage,
                failureReason: reason,
                firstFailedAt: Date(),
                lastAttemptAt: Date(),
                attemptCount: 1
            )
            self.failedEmailRecords.append(record)
        }
        self.scanFailedCount = self.failedEmailRecords.count
        saveDatabase()
    }
    
    public func removeFailure(id: String) {
        self.failedEmailRecords.removeAll { $0.id == id }
        self.scanFailedCount = self.failedEmailRecords.count
        saveDatabase()
    }
    
    public func dismissFailedEmail(id: String) {
        removeFailure(id: id)
    }
    
    public func retryFailedEmail(id: String) async {
        guard let failure = failedEmailRecords.first(where: { $0.id == id }) else { return }
        guard isEmailExtractionConfigured else {
            lastScanError = "No Ollama model is selected. Choose one in Settings."
            return
        }
        
        isScanningEmails = true
        isScanCancelled = false
        scanProgressText = "Retrying: \(failure.subject)..."
        
        do {
            let email = try await gmailService.fetchSingleEmail(id: failure.id, threadId: failure.threadId)
            let modelUsed = ollamaModel
            let analysis = try await analyzeEmailWithOllama(email, progressLabel: "Retrying \(failure.subject)")
            
            let cacheEntry = CachedEmailExtraction(
                emailId: email.id,
                emailSubject: email.subject,
                senderEmail: email.senderEmail,
                receivedDate: email.receivedDate,
                analyzedDate: Date(),
                modelUsed: modelUsed,
                analysis: analysis
            )
            self.extractionCache[email.id] = cacheEntry
            
            var disc = 0; var upd = 0; var news = 0; var non = 0
            applyAnalysis(analysis, for: email, discoveredCount: &disc, updatedCount: &upd, newslettersFiltered: &news, nonRecipientFiltered: &non)
            
            removeFailure(id: email.id)
            scanProcessedCount += 1
            scanProgressText = nil
            
            if self.failedEmailRecords.isEmpty {
                lastScanSuccessSummary = "You’re up to date—no new emails to analyze."
            } else {
                lastScanSuccessSummary = "No new emails. \(self.failedEmailRecords.count) email\(self.failedEmailRecords.count == 1 ? "" : "s") still need retry."
            }
            lastScanError = nil
            recalculateSchedule()
            saveDatabase()
        } catch let aiError as AIServiceError where aiError.isFatalForScan {
            // Key / billing / request problems would fail every retry the same way: surface once and stop.
            lastScanError = aiError.localizedDescription
            retryStoppedByFatalError = true
            scanProgressText = nil
        } catch {
            let stage: EmailFailureStage
            if let aiError = error as? AIServiceError {
                stage = aiError.kind == .invalidResponse ? .validation : .analysis
            } else {
                stage = (error.localizedDescription.contains("Gmail") || error.localizedDescription.contains("HTTP") || error.localizedDescription.contains("not found")) ? .retrieval : .analysis
            }
            recordFailure(
                id: failure.id,
                threadId: failure.threadId,
                subject: failure.subject,
                sender: failure.sender,
                receivedDate: failure.receivedDate,
                stage: stage,
                reason: error.localizedDescription
            )
            scanProgressText = nil
        }
        
        isScanningEmails = false
    }
    
    public func retryAllFailedEmails(includeOutsideWindow: Bool = true, windowHours: Double = 72) async {
        let targets = failedEmailRecords.filter { includeOutsideWindow || !$0.isOutsideScanWindow(hours: windowHours) }
        let ids = targets.map { $0.id }
        retryStoppedByFatalError = false
        for id in ids {
            if isScanCancelled || retryStoppedByFatalError { break }
            await retryFailedEmail(id: id)
        }
    }
    
    /// Caches a successful analysis (including zero tasks), clears any failure record, and applies the tasks.
    private func recordSuccessfulScanAnalysis(
        _ analysis: EmailAnalysis,
        for email: EmailSource,
        model: String,
        discoveredCount: inout Int,
        updatedCount: inout Int,
        newslettersFiltered: inout Int,
        nonRecipientFiltered: inout Int
    ) {
        let cacheEntry = CachedEmailExtraction(
            emailId: email.id,
            emailSubject: email.subject,
            senderEmail: email.senderEmail,
            receivedDate: email.receivedDate,
            analyzedDate: Date(),
            modelUsed: model,
            analysis: analysis
        )
        self.extractionCache[email.id] = cacheEntry
        
        // Remove failure record if it was previously failed
        removeFailure(id: email.id)
        
        // Record analyzed email summary item for user inspection
        let statusDesc: String
        if analysis.isNewsletterOrMarketing {
            statusDesc = "Newsletter / marketing (filtered)"
        } else if !analysis.isDirectedAtRecipient {
            statusDesc = "Not directed at recipient (filtered)"
        } else if analysis.tasks.isEmpty {
            statusDesc = "No actionable tasks found"
        } else {
            statusDesc = "\(analysis.tasks.count) task(s) discovered"
        }
        
        let summaryItem = AnalyzedEmailSummaryItem(
            id: email.id,
            subject: email.subject,
            sender: "\(email.senderName) <\(email.senderEmail)>",
            date: email.receivedDate,
            modelUsed: model,
            tasksDiscoveredCount: analysis.tasks.count,
            taskTitles: analysis.tasks.map { $0.title },
            statusDescription: statusDesc
        )
        self.lastAnalyzedEmailItems.append(summaryItem)
        
        applyAnalysis(
            analysis,
            for: email,
            discoveredCount: &discoveredCount,
            updatedCount: &updatedCount,
            newslettersFiltered: &newslettersFiltered,
            nonRecipientFiltered: &nonRecipientFiltered
        )
        
        self.scanProcessedCount += 1
        self.scanPendingCount = max(0, self.scanPendingCount - 1)
        saveDatabase()
    }
    
    private func executeEmailScan(maxUncachedToAnalyze: Int?) async {
        // Prevent concurrent scans or repeated button clicks from bypassing pacing
        guard !isScanningEmails else { return }
        
        guard isGmailAuthenticated else {
            lastScanError = "Gmail is not connected. Please connect your Gmail account in Settings before scanning."
            return
        }
        guard isEmailExtractionConfigured else {
            lastScanError = "No Ollama model is selected. Choose one in Settings."
            return
        }
        
        isScanningEmails = true
        isScanCancelled = false
        lastScanError = nil
        lastScanSuccessSummary = nil
        currentActiveProcessingModel = ollamaModel
        
        let isTestScan = (maxUncachedToAnalyze != nil)
        if isTestScan {
            self.lastAnalyzedEmailItems = []
        }
        
        let scanStart = Date()
        let scanWindowHours: Double = 72.0
        let scanWindowStart = scanStart.addingTimeInterval(-scanWindowHours * 3600.0)
        let scanWindowEnd = scanStart
        
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        let tz = TimeZone(identifier: preferences.timeZoneIdentifier) ?? TimeZone.current
        df.timeZone = tz
        let tzAbbr = tz.abbreviation(for: scanStart) ?? ""
        let startStr = df.string(from: scanWindowStart)
        let endStr = df.string(from: scanWindowEnd)
        let exactRangeStr = "\(startStr) – \(endStr) \(tzAbbr)".trimmingCharacters(in: .whitespaces)
        self.lastScanRange = "Last 3 days / 72h (\(exactRangeStr))"
        self.lastScanCoverage = "Inbox only: \(exactRangeStr)"
        self.scanProgressText = "Querying Gmail inbox for the last 3 days (72 hours)..."
        
        do {
            let (stubs, _, _) = try await gmailService.listInboxMessageStubs(windowStart: scanWindowStart, windowEnd: scanWindowEnd)
            self.scanTotalInboxCount = stubs.count
            
            // Incremental categorization based on persisted message IDs
            let cachedStubs = stubs.filter { self.extractionCache[$0.id] != nil }
            let uncachedStubs = stubs.filter { self.extractionCache[$0.id] == nil }
            
            self.scanCachedCount = cachedStubs.count
            self.scanNewCount = uncachedStubs.count
            self.scanPendingCount = uncachedStubs.count
            self.scanProcessedCount = 0
            self.scanFailedCount = self.failedEmailRecords.count
            
            if stubs.isEmpty || uncachedStubs.isEmpty {
                self.lastScanDate = Date()
                self.scanProgressText = nil
                self.isScanningEmails = false
                self.currentActiveProcessingModel = nil
                
                if isTestScan && !stubs.isEmpty {
                    self.lastScanSuccessSummary = "All \(stubs.count) emails have already been analyzed and cached."
                } else if self.failedEmailRecords.isEmpty {
                    self.lastScanSuccessSummary = "You’re up to date—no new emails to analyze."
                } else {
                    self.lastScanSuccessSummary = "No new emails. \(self.failedEmailRecords.count) email\(self.failedEmailRecords.count == 1 ? "" : "s") still need retry."
                }
                self.lastScanError = nil
                saveDatabase()
                return
            }
            
            let stubsToProcess = isTestScan ? Array(uncachedStubs.prefix(maxUncachedToAnalyze!)) : uncachedStubs
            self.scanPendingCount = stubsToProcess.count
            
            var discoveredCount = 0
            var updatedCount = 0
            var newslettersFiltered = 0
            var nonRecipientFiltered = 0
            var fatalError: Error? = nil
            
            for (index, stub) in stubsToProcess.enumerated() {
                if isScanCancelled {
                    break
                }
                
                // 1. Retrieve & Decode Single Email (Applied only for uncached messages)
                self.scanProgressText = isTestScan
                    ? "Test Scan (\(index + 1)/\(stubsToProcess.count)): Fetching message \(stub.id)..."
                    : "Fetching (\(index + 1)/\(stubsToProcess.count)): message \(stub.id)..."
                
                let email: EmailSource
                do {
                    email = try await gmailService.fetchSingleEmail(id: stub.id, threadId: stub.threadId)
                } catch {
                    let failureStage: EmailFailureStage = (error.localizedDescription.contains("decode") || error.localizedDescription.contains("parse")) ? .decoding : .retrieval
                    recordFailure(
                        id: stub.id,
                        threadId: stub.threadId,
                        subject: "(Unavailable)",
                        sender: "Unknown",
                        receivedDate: Date(),
                        stage: failureStage,
                        reason: "Gmail retrieval failed: \(error.localizedDescription)"
                    )
                    self.scanPendingCount = max(0, self.scanPendingCount - 1)
                    continue
                }
                
                // 1b. Boundary check: ensure email is strictly within the rolling 72-hour window
                if email.receivedDate < scanWindowStart || email.receivedDate > scanWindowEnd {
                    self.scanPendingCount = max(0, self.scanPendingCount - 1)
                    continue
                }
                
                // 2. Fresh analysis with the local model (retries happen inside the service)
                let prefixLabel = isTestScan ? "Test Scan (\(index + 1)/\(stubsToProcess.count))" : "Analyzing (\(index + 1)/\(stubsToProcess.count))"
                let activeModel = ollamaModel
                self.currentActiveProcessingModel = activeModel
                self.scanProgressText = "\(prefixLabel) with \(activeModel): \(email.subject)..."
                do {
                    let analysis = try await analyzeEmailWithOllama(email, progressLabel: prefixLabel)
                    recordSuccessfulScanAnalysis(
                        analysis,
                        for: email,
                        model: activeModel,
                        discoveredCount: &discoveredCount,
                        updatedCount: &updatedCount,
                        newslettersFiltered: &newslettersFiltered,
                        nonRecipientFiltered: &nonRecipientFiltered
                    )
                } catch is CancellationError {
                    break
                } catch let aiError as AIServiceError where aiError.isFatalForScan {
                    fatalError = aiError
                    break
                } catch {
                    let stage: EmailFailureStage = ((error as? AIServiceError)?.kind == .invalidResponse) ? .validation : .analysis
                    recordFailure(id: email.id, threadId: email.threadId, subject: email.subject, sender: "\(email.senderName) <\(email.senderEmail)>", receivedDate: email.receivedDate, stage: stage, reason: error.localizedDescription)
                    self.scanPendingCount = max(0, self.scanPendingCount - 1)
                }
                
                if fatalError != nil {
                    break
                }
            }
            
            // Check cancellation first: never describe cancelled scan as fully successful
            if isScanCancelled {
                self.lastScanError = "Scan cancelled by user. \(self.scanProcessedCount) email(s) were analyzed and progress was saved."
                self.lastScanSuccessSummary = nil
                self.scanProgressText = nil
                self.currentActiveProcessingModel = nil
                isScanningEmails = false
                saveDatabase()
                return
            }
            
            if let fatal = fatalError {
                self.lastScanError = fatal.localizedDescription
                self.lastScanSuccessSummary = nil
                self.scanProgressText = nil
                self.currentActiveProcessingModel = nil
                isScanningEmails = false
                saveDatabase()
                return
            }
            
            self.lastScanDate = Date()
            self.scanProgressText = nil
            self.currentActiveProcessingModel = nil
            
            if isTestScan {
                let totalUncached = uncachedStubs.count
                let count = self.scanProcessedCount
                if totalUncached > maxUncachedToAnalyze! {
                    self.lastScanSuccessSummary = "Analyzed \(count) of \(maxUncachedToAnalyze!) uncached email(s) (out of \(totalUncached) uncached available). \(discoveredCount) task(s) discovered."
                } else {
                    self.lastScanSuccessSummary = "Analyzed all \(count) available uncached email(s). \(discoveredCount) task(s) discovered."
                }
            } else if self.scanProcessedCount > 0 {
                self.lastScanSuccessSummary = "Analyzed \(self.scanProcessedCount) new email(s). \(discoveredCount) task(s) discovered."
            } else if self.failedEmailRecords.isEmpty {
                self.lastScanSuccessSummary = "You’re up to date—no new emails to analyze."
            } else {
                self.lastScanSuccessSummary = "No new emails. \(self.failedEmailRecords.count) email\(self.failedEmailRecords.count == 1 ? "" : "s") still need retry."
            }
            
            self.lastScanError = nil
            recalculateSchedule()
            saveDatabase()
        } catch {
            lastScanError = "Email scan failed: \(error.localizedDescription)"
            lastScanSuccessSummary = nil
            scanProgressText = nil
            currentActiveProcessingModel = nil
        }
        
        isScanningEmails = false
    }
    
    public func processExtractedEmailTasks(
        email: EmailSource,
        analysis: EmailAnalysis
    ) {
        var d = 0, u = 0, n = 0, r = 0
        applyAnalysis(analysis, for: email, discoveredCount: &d, updatedCount: &u, newslettersFiltered: &n, nonRecipientFiltered: &r)
    }
    
    func applyAnalysis(
        _ analysis: EmailAnalysis,
        for email: EmailSource,
        discoveredCount: inout Int,
        updatedCount: inout Int,
        newslettersFiltered: inout Int,
        nonRecipientFiltered: inout Int
    ) {
        if analysis.isNewsletterOrMarketing {
            newslettersFiltered += 1
            let log = EmailProcessingLog(
                emailId: email.id,
                sender: email.senderName,
                subject: email.subject,
                timestamp: email.receivedDate,
                action: .ignoredNewsletter,
                explanation: "Classified as newsletter or marketing. Filtered out from task list."
            )
            appendLog(log)
            return
        }
        
        if !analysis.isDirectedAtRecipient {
            nonRecipientFiltered += 1
            let log = EmailProcessingLog(
                emailId: email.id,
                sender: email.senderName,
                subject: email.subject,
                timestamp: email.receivedDate,
                action: .ignoredNewsletter,
                explanation: "Filtered out: request was directed at other people, not recipient."
            )
            appendLog(log)
            return
        }
        
        if !analysis.hasActionableTask || analysis.tasks.isEmpty {
            let log = EmailProcessingLog(
                emailId: email.id,
                sender: email.senderName,
                subject: email.subject,
                timestamp: email.receivedDate,
                action: .ignoredNewsletter,
                explanation: "No personal action items, assignments, or commitments in email body."
            )
            appendLog(log)
            return
        }
        
        for candidate in analysis.tasks {
            // Check if this task was previously dismissed and cleared from the visible list
            if let clearedMatch = self.clearedDismissedTasks.first(where: {
                $0.sourceEmailId == email.id ||
                ($0.sourceThreadId == email.threadId && ($0.title == candidate.title || $0.requiredAction == candidate.requiredAction)) ||
                TaskMemory.similarity(candidate.title, $0.title) >= 0.75
            }) {
                let log = EmailProcessingLog(
                    emailId: email.id,
                    sender: email.senderName,
                    subject: email.subject,
                    timestamp: email.receivedDate,
                    action: .taskDismissed,
                    explanation: "Skipping '\(candidate.title)': previously dismissed and cleared from visible list.",
                    extractedTaskId: clearedMatch.id
                )
                appendLog(log)
                continue
            }
            
            // Task memory: the same email/thread, or any task that is clearly the same one
            // (another email, a Canvas announcement…). Update it instead of adding a duplicate.
            let candidateResolved = DeadlinesResolver.resolve(
                rawDeadlineIso: candidate.deadlineIso,
                supportingExcerpt: candidate.supportingExcerpt,
                emailReceivedDate: email.receivedDate,
                configuredTimeZone: self.preferences.timeZone,
                dateOnlyPolicy: self.preferences.dateOnlyDeadlinePolicy,
                workdayEndHour: self.preferences.workEndHour,
                workdayEndMinute: self.preferences.workEndMinute,
                workdayStartHour: self.preferences.workStartHour,
                workdayStartMinute: self.preferences.workStartMinute
            )
            let candidateDeadline = candidateResolved.isSupported ? candidateResolved.deadlineDate : nil
            let sameSourceIndex = self.tasks.firstIndex(where: {
                $0.sourceEmail.id == email.id ||
                ($0.sourceEmail.threadId == email.threadId && ($0.title == candidate.title || $0.requiredAction == candidate.requiredAction))
            })
            if let existingIndex = sameSourceIndex ?? TaskMemory.findMatch(
                title: candidate.title, action: candidate.requiredAction, deadline: candidateDeadline,
                isDeadlineChange: candidate.isDeadlineUpdate, in: self.tasks
            ) {
                var existing = self.tasks[existingIndex]
                // Re-reading the very same message adds nothing new.
                if existing.sourceEmail.id == email.id { continue }
                // Canvas and Gradescope own their due dates; other sources only add details.
                let isLMSTask = [.canvas, .gradescope].contains(existing.sourceEmail.category)
                let source = email.category == .canvas ? "Canvas" : "Email"
                let changes = TaskMemory.merge(
                    into: &existing,
                    deadline: isLMSTask ? nil : candidateDeadline,
                    details: candidate.isDeadlineUpdate ? (candidate.deadlineUpdateNote ?? candidate.supportingExcerpt) : candidate.supportingExcerpt,
                    source: source,
                    now: Date(),
                    timeZone: self.preferences.timeZone
                )
                if !changes.isEmpty {
                    // Keep the email's own wording ("Deadline extended to Monday at 5 PM").
                    if candidate.isDeadlineUpdate, let note = candidate.deadlineUpdateNote,
                       changes.contains(where: { $0.hasPrefix("Due date") }) {
                        existing.deadlineUpdateNote = note
                    }
                    self.tasks[existingIndex] = existing
                    updatedCount += 1
                }
                let log = EmailProcessingLog(
                    emailId: email.id,
                    sender: email.senderName,
                    subject: email.subject,
                    timestamp: email.receivedDate,
                    action: .taskUpdated,
                    explanation: changes.isEmpty
                        ? "Already tracked as '\(existing.displayTitle)'; nothing new."
                        : "Updated existing task '\(existing.displayTitle)': \(changes.joined(separator: "; ")).",
                    extractedTaskId: existing.id
                )
                appendLog(log)
                // PRESERVE user completion, dismissal, and overrides
                continue
            }
            
            // New task
            let resolved = DeadlinesResolver.resolve(
                rawDeadlineIso: candidate.deadlineIso,
                supportingExcerpt: candidate.supportingExcerpt,
                emailReceivedDate: email.receivedDate,
                configuredTimeZone: self.preferences.timeZone,
                dateOnlyPolicy: self.preferences.dateOnlyDeadlinePolicy,
                workdayEndHour: self.preferences.workEndHour,
                workdayEndMinute: self.preferences.workEndMinute,
                workdayStartHour: self.preferences.workStartHour,
                workdayStartMinute: self.preferences.workStartMinute
            )
            
            let isAmbiguous = candidate.isAmbiguous || (resolved.deadlineDate == nil && !resolved.isDateOnly) || !candidate.uncertainDetails.isEmpty
            let taskStatus: TaskStatus = isAmbiguous ? .needsClarification : .ready
            
            let newTask = DiscoveredTask(
                id: UUID(),
                title: candidate.title,
                requiredAction: candidate.requiredAction,
                notes: analysis.reasoning,
                sourceEmail: email,
                extractedDeadline: resolved.isSupported ? resolved.deadlineDate : nil,
                isDeadlineSupportedByEmail: resolved.isSupported,
                supportingExcerpt: candidate.supportingExcerpt,
                estimatedMinutes: max(15, candidate.estimatedDurationMinutes),
                status: taskStatus,
                uncertainDetails: candidate.uncertainDetails,
                clarificationPrompt: candidate.uncertainDetails.isEmpty ? nil : candidate.uncertainDetails.joined(separator: "\n• "),
                isClarified: !isAmbiguous,
                deadlineUpdateNote: candidate.deadlineUpdateNote,
                isDismissed: false,
                isDateOnlyDeadline: resolved.isDateOnly,
                originalDeadlineWording: resolved.originalWording,
                dateOnlyDeadlineString: resolved.dateOnlyString,
                timeZoneAssumption: resolved.timeZoneAssumption,
                createdAt: email.receivedDate,
                updatedAt: Date()
            )
            
            self.tasks.append(newTask)
            discoveredCount += 1
            
            let log = EmailProcessingLog(
                emailId: email.id,
                sender: email.senderName,
                subject: email.subject,
                timestamp: email.receivedDate,
                action: isAmbiguous ? .taskNeedsClarification : .taskCreated,
                explanation: isAmbiguous ? "Discovered request requiring clarification: \(candidate.uncertainDetails.joined(separator: ", "))" : "Discovered clear action: \(candidate.title)",
                extractedTaskId: newTask.id
            )
            appendLog(log)
        }
    }
    
    func appendLog(_ log: EmailProcessingLog) {
        if !self.logs.contains(where: { $0.emailId == log.emailId && $0.action == log.action }) {
            self.logs.insert(log, at: 0)
        }
    }
    
    private func parseISO8601Date(_ str: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: str) { return d }
        let standard = ISO8601DateFormatter()
        return standard.date(from: str)
    }
    
    public func runSimulatedEmailDiscovery() async {
        let tracking = beginNewTaskTracking()
        defer { endNewTaskTracking(tracking) }
        isSyncing = true
        lastSyncMessage = "Scanning simulated Gmail inbox..."
        
        do {
            let emails = try await emailService.fetchRecentMessages()
            let result = try await extractionService.extractTasks(from: emails, existingTasks: tasks)
            
            var newCount = 0
            for t in result.newTasks {
                if !self.tasks.contains(where: { $0.id == t.id }) {
                    self.tasks.append(t)
                    newCount += 1
                }
            }
            
            for u in result.updatedTasks {
                if let idx = self.tasks.firstIndex(where: { $0.id == u.id }) {
                    self.tasks[idx] = u
                }
            }
            
            for l in result.logs {
                if !self.logs.contains(where: { $0.id == l.id }) {
                    self.logs.insert(l, at: 0)
                }
            }
            
            recalculateSchedule()
            lastSyncMessage = "Simulated scan complete: \(newCount) new tasks discovered."
            saveDatabase()
        } catch {
            lastSyncMessage = "Simulated email sync failed: \(error.localizedDescription)"
        }
        
        isSyncing = false
    }
    
    public func recalculateSchedule() {
        generateProposedPlan(isAutomatic: true)
    }
    
    /// Calendar events plus removed times that belong to no task (these block everyone). A deleted
    /// task session only limits that task on its day (`taskDayLimits`), so other work can move up.
    var planningCommitments: [CalendarCommitment] {
        commitments + declinedSlots.filter { $0.taskId == nil && $0.end > Date() }.map {
            CalendarCommitment(title: "Removed work time", startTime: $0.start, endTime: $0.end,
                               isBusy: true, calendarName: "DayBook AI · removed", isSimulatedDemo: false)
        }
    }

    /// keepExistingPlan: leave every planned session where it is and only place missing work in free
    /// time (used after deleting a session, so nothing else moves).
    public func generateProposedPlan(isAutomatic: Bool = false, keepExistingPlan: Bool = false) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let endDate = cal.date(byAdding: .day, value: 14, to: today) else { return }
        
        pruneDeclinedSlots()
        calibrateEstimates()
        isGeneratingSchedule = true
        func plan(keepBefore: Date?) -> SchedulingResult {
            schedulingEngine.generateSchedule(
                tasks: tasks,
                commitments: planningCommitments,
                existingSessions: workSessions,
                preferences: preferences,
                dateRange: today...endDate,
                currentDate: Date(),
                deletedProposedMinutesByTaskId: [:],
                keepPlannedBefore: keepBefore,
                taskDayLimits: taskDayLimits
            )
        }
        let keepBefore: Date? = keepExistingPlan ? endDate.addingTimeInterval(86400) : (isAutomatic ? keepTodaySteadyUntil() : nil)
        var result = plan(keepBefore: keepBefore)
        // A steady day gives way when a task newly needs to start now (or no longer fits) and has nothing today.
        if keepBefore != nil && !keepExistingPlan,
           let pressing = Self.newlyPressingTask(old: lastSchedulingResult, new: result, sessions: result.allSessions, tasks: tasks) {
            result = plan(keepBefore: nil)
            replanExplanation = "Re-planned today: '\(pressing)' now needs to start."
        }
        
        self.workSessions = result.allSessions
        self.lastSchedulingResult = result
        if !isAutomatic {
            self.schedulingStatusMessage = "Proposed \(result.proposedSessions.count) work sessions across next 14 days (\(result.stats.totalPlannedHoursFormatted))."
        }
        self.isGeneratingSchedule = false
        saveDatabase()
    }
    
    public func toggleSessionLock(id: UUID) {
        guard let idx = workSessions.firstIndex(where: { $0.id == id }) else { return }
        workSessions[idx].isLocked.toggle()
        saveDatabase()
    }
    
    public func addWorkSession(_ session: WorkSession) {
        var s = session
        s.isManuallyAdjusted = true
        workSessions.append(s)
        saveDatabase()
        recalculateSchedule()
    }
    
    public func removeSession(id: UUID) {
        if let idx = workSessions.firstIndex(where: { $0.id == id }) {
            let session = workSessions[idx]
            if session.isPublished, session.calendarEventId != nil, !session.isSimulatedDemo {
                pendingRemovalSessions.append(session)
            }
            workSessions.remove(at: idx)
            // Keep the task's full estimate, but give it no more time on this day than it has left (its other
            // sessions there stay). Later sessions that day move up into the freed time (until you delete
            // those too); the deleted work is planned again on another day, without moving anything else.
            if let taskId = session.taskId, session.status == .planned, !session.isPaidWork {
                declinedSlots.append(DeclinedSlot(taskId: taskId, start: session.startTime, end: session.endTime,
                                                  minutesLeftThatDay: plannedMinutes(of: taskId, onDayOf: session.startTime)))
                shiftSessionsForward(freedFrom: session.startTime)
                generateProposedPlan(isAutomatic: true, keepExistingPlan: true)
            }
            saveDatabase()
        }
    }
    
    public func moveSession(id: UUID, newStartTime: Date, newEndTime: Date) {
        guard let idx = workSessions.firstIndex(where: { $0.id == id }) else { return }
        workSessions[idx].startTime = newStartTime
        workSessions[idx].endTime = newEndTime
        workSessions[idx].isManuallyAdjusted = true
        saveDatabase()
        recalculateSchedule()
    }
    
    public func setTaskPriority(id: UUID, priority: TaskPriority) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].userPriority = priority
        tasks[idx].updatedAt = Date()
        saveDatabase()
        recalculateSchedule()
    }
    
    public func setDateOnlyDeadlinePolicy(_ policy: DateOnlyDeadlinePolicy) {
        preferences.dateOnlyDeadlinePolicy = policy
        saveDatabase()
        recalculateSchedule()
    }
    
    public func setIncludeDemoDataInPlan(_ include: Bool) {
        preferences.includeDemoDataInPlan = include
        saveDatabase()
        recalculateSchedule()
    }
    
    public func completeTask(taskId: UUID) {
        if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[idx].status = .completed
            tasks[idx].updatedAt = Date()
            
            for sIdx in workSessions.indices {
                if workSessions[sIdx].taskId == taskId {
                    workSessions[sIdx].status = .completed
                }
            }
            recordActualTime(taskId: taskId)
            recalculateSchedule()
            saveDatabase()
        }
    }
    
    public func dismissTask(taskId: UUID) {
        if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[idx].isDismissed = true
            tasks[idx].status = .dismissed
            tasks[idx].updatedAt = Date()
            
            workSessions.removeAll(where: { $0.taskId == taskId })
            recalculateSchedule()
            saveDatabase()
        }
    }
    
    public func clarifyTask(taskId: UUID, clarifiedDeadline: Date?, correctedDurationMinutes: Int?, userNotes: String?) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        
        var task = tasks[idx]
        if let dl = clarifiedDeadline {
            if !task.isDeadlineSupportedByEmail {
                task.planningTargetDate = dl
            } else {
                task.userOverriddenDeadline = dl
            }
        }
        if let dur = correctedDurationMinutes {
            task.userOverriddenDuration = dur
            task.estimatedMinutes = dur
        }
        if let notes = userNotes, !notes.isEmpty {
            task.notes += "\n\nUser clarification: \(notes)"
        }
        task.isClarified = true
        task.status = .ready
        task.updatedAt = Date()
        
        tasks[idx] = task
        recalculateSchedule()
        saveDatabase()
    }
    
    public func updateTaskTitle(taskId: UUID, newTitle: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[idx].userOverriddenTitle = newTitle
        tasks[idx].updatedAt = Date()
        saveDatabase()
    }
    
    public func updateTaskUserOverrides(id: UUID, title: String? = nil, deadline: Date? = nil, duration: Int? = nil) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        if let t = title { tasks[idx].userOverriddenTitle = t }
        if let dl = deadline {
            if !tasks[idx].isDeadlineSupportedByEmail {
                tasks[idx].planningTargetDate = dl
            } else {
                tasks[idx].userOverriddenDeadline = dl
            }
        }
        if let dur = duration { tasks[idx].userOverriddenDuration = dur; tasks[idx].estimatedMinutes = dur }
        tasks[idx].updatedAt = Date()
        recalculateSchedule()
        saveDatabase()
    }
    
    public func updateTaskDuration(id: UUID, minutes: Int) {
        updateTaskUserOverrides(id: id, duration: minutes)
    }
    
    public func toggleTaskCompletion(id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        recordUndoSnapshot(description: "Toggle completion for '\(tasks[idx].title)'")
        
        let wasCompleted = tasks[idx].isCompleted
        if wasCompleted {
            tasks[idx].status = tasks[idx].isClarified ? .ready : .needsClarification
            tasks[idx].updatedAt = Date()
            for sIdx in workSessions.indices where workSessions[sIdx].taskId == id {
                workSessions[sIdx].status = .planned
            }
            recalculateSchedule()
            replanExplanation = "Marked '\(tasks[idx].title)' incomplete."
        } else {
            tasks[idx].status = .completed
            tasks[idx].isCarryover = false
            tasks[idx].updatedAt = Date()
            
            // Completing a whole task removes its remaining future proposals while retaining completed work history
            let now = Date()
            let cal = Calendar.current
            var removedTodaySlot = false
            var todayDate = now
            
            var sessionsToRemove: [UUID] = []
            for sIdx in workSessions.indices where workSessions[sIdx].taskId == id {
                if workSessions[sIdx].status == .planned {
                    if workSessions[sIdx].startTime.isBeforeOrEqual(now) && workSessions[sIdx].endTime.isAfter(now) {
                        // In-progress session: finish it at now
                        workSessions[sIdx].status = .completed
                        workSessions[sIdx].endTime = now
                        if cal.isDateInToday(workSessions[sIdx].startTime) {
                            removedTodaySlot = true
                            todayDate = workSessions[sIdx].startTime
                        }
                    } else if workSessions[sIdx].startTime.isAfter(now) {
                        // Future proposal: remove it so future time is freed
                        if cal.isDateInToday(workSessions[sIdx].startTime) {
                            removedTodaySlot = true
                            todayDate = workSessions[sIdx].startTime
                        }
                        sessionsToRemove.append(workSessions[sIdx].id)
                    } else {
                        // Past planned session: mark completed
                        workSessions[sIdx].status = .completed
                    }
                }
            }
            
            workSessions.removeAll { sessionsToRemove.contains($0.id) }
            recordActualTime(taskId: id, now: now)
            
            // If freed time on today, advance same-day flexible sessions
            if removedTodaySlot {
                let moved = advanceSameDayFlexibleSessions(on: todayDate, from: now)
                if !moved.isEmpty {
                    replanExplanation = "Completed '\(tasks[idx].title)'. Released future proposals and advanced: \(moved.joined(separator: ", "))."
                } else {
                    replanExplanation = "Completed '\(tasks[idx].title)'. Future proposals released."
                }
            } else {
                replanExplanation = "Completed '\(tasks[idx].title)'. Future proposals released."
            }
        }
        
        saveDatabase()
    }
    
    public func setPlanningTarget(id: UUID, targetDate: Date?) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].planningTargetDate = targetDate
        tasks[idx].updatedAt = Date()
        saveDatabase()
        recalculateSchedule()
    }
    
    public func removeDemonstrationData() {
        self.tasks.removeAll { $0.sourceEmail.isSimulatedDemo }
        self.workSessions.removeAll { $0.isSimulatedDemo }
        self.commitments.removeAll { $0.isSimulatedDemo }
        if let sel = selectedTaskId, !tasks.contains(where: { $0.id == sel }) {
            selectedTaskId = tasks.first?.id
        }
        saveDatabase()
        recalculateSchedule()
    }
    
    public var isDemonstrationModeActive: Bool {
        return !isGmailAuthenticated && tasks.allSatisfy { $0.sourceEmail.isSimulatedDemo }
    }
    
    public func restoreTask(id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].isDismissed = false
        tasks[idx].status = tasks[idx].isClarified ? .ready : .needsClarification
        tasks[idx].updatedAt = Date()
        recalculateSchedule()
        saveDatabase()
    }
    
    public func clarifyTask(id: UUID, targetDeadline: Date?, notes: String?) {
        clarifyTask(taskId: id, clarifiedDeadline: targetDeadline, correctedDurationMinutes: nil, userNotes: notes)
    }
    
    public func dismissTask(id: UUID) {
        dismissTask(taskId: id)
    }
    
    public func toggleSessionStatus(id: UUID) {
        guard let idx = workSessions.firstIndex(where: { $0.id == id }) else { return }
        let session = workSessions[idx]
        if session.status == .completed {
            recordUndoSnapshot(description: "Marked '\(session.title)' planned")
            workSessions[idx].status = .planned
            replanExplanation = "Marked '\(session.title)' as planned."
            saveDatabase()
        } else {
            // When user marks a paid work activity completed, ask to confirm or adjust actual start/end times and breaks!
            completeSessionEarly(id: id)
        }
    }
    
    // MARK: - Undo Replan
    
    public func recordUndoSnapshot(description: String) {
        self.lastUndoSnapshot = ScheduleUndoSnapshot(
            tasks: self.tasks,
            workSessions: self.workSessions,
            deletedProposedMinutesByTaskId: self.deletedProposedMinutesByTaskId,
            description: description,
            timestamp: Date()
        )
    }
    
    public func undoLatestReplan() {
        guard let snapshot = lastUndoSnapshot else { return }
        self.tasks = snapshot.tasks
        self.workSessions = snapshot.workSessions
        self.deletedProposedMinutesByTaskId = snapshot.deletedProposedMinutesByTaskId
        self.lastUndoSnapshot = nil
        self.replanExplanation = "Undid: \(snapshot.description)"
        saveDatabase()
    }
    
    // MARK: - Same-Day Early Completion Rescheduling
    
    public func completeSessionEarly(id: UUID, completionTime: Date = Date()) {
        guard let idx = workSessions.firstIndex(where: { $0.id == id }) else { return }
        let session = workSessions[idx]
        
        // Paid work requires confirming actual hours in the dedicated sheet
        
        recordUndoSnapshot(description: "Completed '\(session.title)' early")
        
        let now = completionTime
        let wasEarly = session.endTime.isAfter(now)
        
        workSessions[idx].status = .completed
        if wasEarly {
            if session.startTime.isAfter(now) {
                // Completed before scheduled window started: release entire scheduled window
                workSessions[idx].startTime = now.addingTimeInterval(-Double(session.durationMinutes * 60))
                workSessions[idx].endTime = now
            } else {
                // Completed during scheduled window: release remaining time
                workSessions[idx].endTime = now
            }
        }
        
        var taskTitle = session.title
        if let taskId = session.taskId, let tIdx = tasks.firstIndex(where: { $0.id == taskId }) {
            taskTitle = tasks[tIdx].title
            let otherPlanned = workSessions.filter { $0.taskId == taskId && $0.id != id && $0.status == .planned }
            if otherPlanned.isEmpty {
                tasks[tIdx].status = .completed
                tasks[tIdx].isCarryover = false
                recordActualTime(taskId: taskId, now: max(now, session.endTime))
            }
        }
        
        if wasEarly {
            let moved = advanceSameDayFlexibleSessions(on: session.startTime, from: now)
            if !moved.isEmpty {
                replanExplanation = "Completed '\(taskTitle)' early. Advanced \(moved.joined(separator: ", "))."
            } else {
                replanExplanation = "Completed '\(taskTitle)' early. Released remaining scheduled time."
            }
        } else {
            replanExplanation = "Completed '\(taskTitle)'."
        }
        
        saveDatabase()
    }
    
    @discardableResult
    public func advanceSameDayFlexibleSessions(on targetDay: Date, from now: Date = Date()) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = preferences.timeZone
        
        let dayStart = cal.startOfDay(for: targetDay)
        let weekday = cal.component(.weekday, from: dayStart)
        let hours = preferences.workingHours(for: weekday)
        guard hours.isWorkday else { return [] }
        
        guard let workStart = cal.date(bySettingHour: hours.startHour, minute: hours.startMinute, second: 0, of: dayStart),
              let workEnd = cal.date(bySettingHour: hours.endHour, minute: hours.endMinute, second: 0, of: dayStart),
              workStart.isBefore(workEnd) else {
            return []
        }
        
        // Never schedule earlier than current time, nor before workday start
        let earliestBoundary = max(now, workStart)
        guard earliestBoundary.isBefore(workEnd) else { return [] }
        
        // Fixed obstacles on this day
        var fixedIntervals: [(start: Date, end: Date)] = []
        fixedIntervals.append((workStart, earliestBoundary))
        
        let preserved = workSessions.filter { s in
            cal.isDate(s.startTime, inSameDayAs: dayStart) &&
            (s.status != .planned || s.isLocked || s.isManuallyAdjusted || s.isPaidWork || s.taskId == nil)
        }
        for s in preserved {
            fixedIntervals.append((s.startTime, s.endTime))
        }

        // Busy commitments overlapping the workday (including multi-day events that began earlier),
        // honoring the all-day blocking preference exactly like the scheduling engine.
        let dayCommitments = planningCommitments.filter { c in
            c.blocksScheduling &&
            c.startTime.isBefore(workEnd) && c.endTime.isAfter(workStart) &&
            (!c.isAllDay || preferences.allDayEventsBlockTime) &&
            (preferences.includeDemoDataInPlan || !c.isSimulatedDemo)
        }
        for c in dayCommitments {
            fixedIntervals.append((max(workStart, c.startTime), min(workEnd, c.endTime)))
        }

        // Lunch break is protected exactly as in the scheduling engine
        if let lunchStart = cal.date(bySettingHour: preferences.lunchStartHour, minute: 0, second: 0, of: dayStart),
           let lunchEnd = cal.date(byAdding: .minute, value: preferences.lunchDurationMinutes, to: lunchStart),
           lunchStart.isBefore(workEnd) && lunchEnd.isAfter(workStart) {
            fixedIntervals.append((max(workStart, lunchStart), min(workEnd, lunchEnd)))
        }
        
        fixedIntervals.sort { $0.start < $1.start }
        var mergedObstacles: [(start: Date, end: Date)] = []
        for interval in fixedIntervals {
            if let last = mergedObstacles.last {
                if interval.start <= last.end {
                    mergedObstacles[mergedObstacles.count - 1] = (last.start, max(last.end, interval.end))
                } else {
                    mergedObstacles.append(interval)
                }
            } else {
                mergedObstacles.append(interval)
            }
        }
        
        // Find other flexible sessions already scheduled on this same day
        let flexibleIndices = workSessions.indices.filter { idx in
            let s = workSessions[idx]
            return cal.isDate(s.startTime, inSameDayAs: dayStart) &&
                   s.status == .planned &&
                   !s.isLocked &&
                   !s.isManuallyAdjusted &&
                   !s.isPaidWork &&
                   s.taskId != nil &&
                   s.endTime.isAfter(earliestBoundary)
        }.sorted { workSessions[$0].startTime < workSessions[$1].startTime }

        guard !flexibleIndices.isEmpty else { return [] }
        
        var movedSummaries: [String] = []
        let breakSeconds = Double(preferences.breakMinutes * 60)
        
        func insertObstacle(_ interval: (start: Date, end: Date)) {
            mergedObstacles.append(interval)
            mergedObstacles.sort { $0.start < $1.start }
            var newMerged: [(start: Date, end: Date)] = []
            for intv in mergedObstacles {
                if let l = newMerged.last, intv.start <= l.end {
                    newMerged[newMerged.count - 1] = (l.start, max(l.end, intv.end))
                } else {
                    newMerged.append(intv)
                }
            }
            mergedObstacles = newMerged
        }
        
        for idx in flexibleIndices {
            let session = workSessions[idx]
            let durationSeconds = Double(session.durationMinutes * 60)
            var didMove = false
            
            // Recompute free gaps from mergedObstacles
            var gaps: [(start: Date, end: Date)] = []
            var cursor = earliestBoundary
            for obstacle in mergedObstacles {
                if obstacle.start > cursor {
                    gaps.append((cursor, min(workEnd, obstacle.start)))
                }
                cursor = max(cursor, obstacle.end)
            }
            if cursor < workEnd {
                gaps.append((cursor, workEnd))
            }
            
            for gap in gaps {
                let availableStart = gap.start
                let proposedEnd = availableStart.addingTimeInterval(durationSeconds)
                
                if proposedEnd <= gap.end && availableStart.isBefore(session.startTime) {
                    var deadlineOk = true
                    if let tId = session.taskId, let task = tasks.first(where: { $0.id == tId }) {
                        if let dl = task.effectiveDeadline, proposedEnd.isAfter(dl) {
                            deadlineOk = false
                        }
                    }
                    
                    if deadlineOk {
                        let oldStartStr = formatTime(session.startTime)
                        let newStartStr = formatTime(availableStart)
                        
                        workSessions[idx].startTime = availableStart
                        workSessions[idx].endTime = proposedEnd
                        
                        movedSummaries.append("'\(session.title)' from \(oldStartStr) to \(newStartStr)")
                        
                        // Add this session + break into obstacles
                        insertObstacle((start: availableStart, end: proposedEnd.addingTimeInterval(breakSeconds)))
                        didMove = true
                        break
                    }
                }
            }
            
            // A session that could not advance still occupies its slot: later sessions must
            // never be advanced into it (previously this produced overlapping sessions).
            if !didMove {
                insertObstacle((start: session.startTime, end: session.endTime.addingTimeInterval(breakSeconds)))
            }
        }
        
        return movedSummaries
    }
    
    // MARK: - "Not Done Yet" Carryover
    
    public func promptNotDoneYet(for session: WorkSession) {
        self.sessionForCarryover = session
        self.showCarryoverSheet = true
    }
    
    public func confirmCarryover(
        session: WorkSession,
        remainingMinutes: Int,
        carryoverToNextWorkday: Bool = false
    ) {
        recordUndoSnapshot(description: "Carried over '\(session.title)'")
        
        guard let taskId = session.taskId,
              let tIdx = tasks.firstIndex(where: { $0.id == taskId }) else {
            sessionForCarryover = nil
            showCarryoverSheet = false
            return
        }
        
        // 1. Mark task as carryover
        tasks[tIdx].isCarryover = true
        tasks[tIdx].updatedAt = Date()
        
        // 2. Adjust remaining effort:
        // Task duration = completed so far + confirmed remaining
        let completedMins = workSessions
            .filter { $0.taskId == taskId && $0.status == .completed }
            .reduce(0) { $0 + $1.durationMinutes }
        tasks[tIdx].userOverriddenDuration = completedMins + remainingMinutes
        
        // 3. Clear any deletedProposedMinutes for this task so scheduling engine can schedule it
        deletedProposedMinutesByTaskId.removeValue(forKey: taskId.uuidString)
        
        // 4. Replace or move the unfinished session rather than creating duplicate work
        workSessions.removeAll { s in
            s.taskId == taskId && s.status == .planned
        }
        
        // 5. Determine scheduling start boundary
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = preferences.timeZone
        
        let now = Date()
        var scheduleStart = now
        if carryoverToNextWorkday {
            var nextDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
            while !preferences.workingHours(for: cal.component(.weekday, from: nextDay)).isWorkday {
                nextDay = cal.date(byAdding: .day, value: 1, to: nextDay) ?? nextDay
            }
            let hours = preferences.workingHours(for: cal.component(.weekday, from: nextDay))
            scheduleStart = cal.date(bySettingHour: hours.startHour, minute: hours.startMinute, second: 0, of: nextDay) ?? nextDay
        }
        
        let today = cal.startOfDay(for: now)
        let endDate = cal.date(byAdding: .day, value: 14, to: today) ?? today.addingTimeInterval(14 * 86400)
        
        let result = schedulingEngine.generateSchedule(
            tasks: tasks,
            commitments: planningCommitments,
            existingSessions: workSessions,
            preferences: preferences,
            dateRange: today...endDate,
            currentDate: scheduleStart,
            deletedProposedMinutesByTaskId: deletedProposedMinutesByTaskId
        )
        
        self.workSessions = result.allSessions
        self.lastSchedulingResult = result
        
        let newSession = workSessions.first { $0.taskId == taskId && $0.status == .planned }
        if let ns = newSession {
            let df = DateFormatter()
            df.timeZone = preferences.timeZone
            df.dateFormat = "EEE, MMM d 'at' h:mm a"
            let targetFormatted = df.string(from: ns.startTime)
            replanExplanation = "Carried over '\(tasks[tIdx].title)' (\(remainingMinutes)m) to \(targetFormatted). Unlocked sessions shifted."
        } else {
            replanExplanation = "Carried over '\(tasks[tIdx].title)' (\(remainingMinutes)m)."
        }
        
        sessionForCarryover = nil
        showCarryoverSheet = false
        saveDatabase()
    }
    
    public func removeCarryover(taskId: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        recordUndoSnapshot(description: "Removed carryover from '\(tasks[idx].title)'")
        tasks[idx].isCarryover = false
        for sIdx in workSessions.indices where workSessions[sIdx].taskId == taskId {
            workSessions[sIdx].isCarryover = false
        }
        recalculateSchedule()
        replanExplanation = "Removed carryover priority from '\(tasks[idx].title)'."
        saveDatabase()
    }
    
    // MARK: - End-of-Day Review
    
    public var endOfDayIncompleteSessions: [WorkSession] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = preferences.timeZone
        let today = cal.startOfDay(for: Date())
        return workSessions.filter { s in
            cal.isDate(s.startTime, inSameDayAs: today) &&
            s.status != .completed
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = preferences.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    public func updatePreferences(_ newPrefs: UserPreferences) {
        self.preferences = newPrefs
        recalculateSchedule()
        saveDatabase()
    }
    
    // MARK: - Apple Calendar Integration (EventKit)
    
    public func requestCalendarAccess() async {
        calendarErrorMessage = nil
        calendarStatusMessage = "Requesting Apple Calendar permission..."
        do {
            let granted = try await calendarService.requestAccess()
            calendarAuthorizationStatus = calendarService.authorizationStatus
            if granted || calendarAuthorizationStatus == .authorized {
                calendarStatusMessage = "Apple Calendar connected."
                await loadAvailableCalendars()
                await refreshCalendarCommitments(isAutomatic: false)
            } else if calendarAuthorizationStatus == .denied || calendarAuthorizationStatus == .restricted {
                calendarStatusMessage = nil
                calendarErrorMessage = "Calendar permission was denied. To enable it, open System Settings > Privacy & Security > Calendars and allow DayBook AI."
            }
        } catch {
            calendarStatusMessage = nil
            calendarErrorMessage = "Failed to request calendar access: \(error.localizedDescription)"
        }
    }
    
    public func loadAvailableCalendars() async {
        do {
            let calendars = try await calendarService.fetchAvailableCalendars()
            self.availableCalendars = calendars
            if preferences.selectedCalendarIdentifiers.isEmpty && !calendars.isEmpty {
                // By default, select all available calendars
                let allIds = Set(calendars.map { $0.id })
                self.selectedCalendarIds = allIds
                self.preferences.selectedCalendarIdentifiers = Array(allIds)
                saveDatabase()
            } else {
                self.selectedCalendarIds = Set(preferences.selectedCalendarIdentifiers)
            }
        } catch {
            self.calendarErrorMessage = "Error fetching calendars: \(error.localizedDescription)"
        }
    }
    
    public func toggleCalendarSelection(id: String) {
        if selectedCalendarIds.contains(id) {
            selectedCalendarIds.remove(id)
        } else {
            selectedCalendarIds.insert(id)
        }
        preferences.selectedCalendarIdentifiers = Array(selectedCalendarIds)
        saveDatabase()
        Task {
            await refreshCalendarCommitments(isAutomatic: false)
        }
    }
    
    public func setAllDayEventsBlockTime(_ block: Bool) {
        allDayEventsBlockTime = block
        preferences.allDayEventsBlockTime = block
        saveDatabase()
        recalculateSchedule()
    }
    
    public func refreshCalendarCommitments(isAutomatic: Bool = false) async {
        calendarAuthorizationStatus = calendarService.authorizationStatus
        guard calendarAuthorizationStatus == .authorized else {
            if !isAutomatic && calendarAuthorizationStatus == .denied {
                calendarErrorMessage = "Calendar permission is denied. Please grant access in System Settings > Privacy & Security > Calendars."
            }
            return
        }
        
        isRefreshingCalendar = true
        if !isAutomatic {
            calendarStatusMessage = "Refreshing events from Apple Calendar..."
        }
        calendarErrorMessage = nil
        
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let endDate = cal.date(byAdding: .day, value: 14, to: today) else {
            isRefreshingCalendar = false
            return
        }
        
        do {
            let events = try await calendarService.fetchCommitments(
                for: today...endDate,
                selectedCalendarIdentifiers: selectedCalendarIds.isEmpty ? nil : selectedCalendarIds,
                allDayBlocksTime: allDayEventsBlockTime
            )
            // Keep planner-local commitments (e.g. events saved from Quick Capture): they are not in
            // Apple Calendar, so replacing the list wholesale would silently delete them.
            let localOnly = self.commitments.filter { $0.isLocalOnly }
            self.commitments = events + localOnly
            self.lastCalendarRefreshDate = Date()
            self.calendarStatusMessage = "Loaded \(events.count) calendar event\(events.count == 1 ? "" : "s") for the next 14 days."
            recalculateSchedule()
            saveDatabase()
            await checkForCalendarDiscrepancies()
        } catch {
            self.calendarErrorMessage = "Failed to refresh events: \(error.localizedDescription)"
        }
        
        self.isRefreshingCalendar = false
    }
    
    public func openSystemCalendarSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Apple Calendar Publishing & Synchronization
    
    public func computePublicationPlan() -> CalendarPublicationPlan {
        let realSessions = workSessions.filter { !$0.isSimulatedDemo }
        let toAdd = realSessions.filter { $0.calendarEventId == nil || !$0.isPublished }
        let toUpdate = realSessions.filter { $0.isPublished && $0.hasUnpublishedChanges }
        let toRemove = pendingRemovalSessions.filter { !$0.isSimulatedDemo && $0.calendarEventId != nil }
        return CalendarPublicationPlan(toAdd: toAdd, toUpdate: toUpdate, toRemove: toRemove)
    }
    
    @discardableResult
    public func setupPlannerCalendar() async -> CalendarAccountInfo? {
        do {
            let calInfo = try await calendarService.getOrCreatePlannerCalendar()
            self.publicationCalendarInfo = calInfo
            self.preferences.publicationCalendarIdentifier = calInfo.id
            if !self.selectedCalendarIds.contains(calInfo.id) {
                self.selectedCalendarIds.insert(calInfo.id)
                self.preferences.selectedCalendarIdentifiers = Array(self.selectedCalendarIds)
            }
            saveDatabase()
            return calInfo
        } catch {
            self.publishErrorMessage = "Could not setup 'DayBook AI' calendar: \(error.localizedDescription)"
            return nil
        }
    }
    
    public func publishApprovedSessions(
        selectedAddSessionIds: Set<UUID>,
        selectedUpdateSessionIds: Set<UUID>,
        selectedRemoveSessionIds: Set<UUID>
    ) async {
        isPublishingCalendar = true
        publishStatusMessage = "Connecting to Apple Calendar..."
        publishErrorMessage = nil
        
        // 1. Ensure permission
        if calendarAuthorizationStatus != .authorized {
            let granted = (try? await calendarService.requestAccess()) ?? false
            calendarAuthorizationStatus = calendarService.authorizationStatus
            guard granted || calendarAuthorizationStatus == .authorized else {
                isPublishingCalendar = false
                publishErrorMessage = "Calendar permission is required to publish sessions. Please grant access in System Settings > Privacy & Security > Calendars."
                return
            }
        }
        
        // 2. Ensure target calendar exists
        guard let targetCalendar = await setupPlannerCalendar() else {
            isPublishingCalendar = false
            return
        }
        
        publishStatusMessage = "Publishing to '\(targetCalendar.title)' calendar..."
        
        // 3. Collect sessions to write
        let sessionsToWrite = workSessions.filter { s in
            selectedAddSessionIds.contains(s.id) || selectedUpdateSessionIds.contains(s.id)
        }
        
        var taskTitleLookup: [UUID: String] = [:]
        for t in tasks {
            taskTitleLookup[t.id] = t.title
        }
        
        var totalPublished = 0
        var totalUpdated = 0
        var totalFailed = 0
        var partialErrors: [String] = []
        
        if !sessionsToWrite.isEmpty {
            do {
                let result = try await calendarService.publishSessions(
                    sessionsToWrite,
                    to: targetCalendar.id,
                    taskTitleLookup: taskTitleLookup
                )
                
                totalPublished += result.publishedCount
                totalUpdated += result.updatedCount
                totalFailed += result.failedCount
                
                for (sessionId, eventId) in result.successSessionEventMap {
                    if let idx = self.workSessions.firstIndex(where: { $0.id == sessionId }) {
                        self.workSessions[idx].calendarEventId = eventId
                        self.workSessions[idx].lastPublishedDate = Date()
                        self.workSessions[idx].lastPublishedStartTime = self.workSessions[idx].startTime
                        self.workSessions[idx].lastPublishedEndTime = self.workSessions[idx].endTime
                        self.workSessions[idx].lastPublishedTitle = self.workSessions[idx].title
                    }
                }
                
                if !result.errors.isEmpty {
                    partialErrors.append(contentsOf: result.errors.values)
                }
            } catch {
                totalFailed += sessionsToWrite.count
                partialErrors.append(error.localizedDescription)
            }
        }
        
        // 4. Handle removals
        let sessionsToRemove = pendingRemovalSessions.filter { selectedRemoveSessionIds.contains($0.id) }
        let eventIdsToRemove = Set(sessionsToRemove.compactMap { $0.calendarEventId })
        
        if !eventIdsToRemove.isEmpty {
            do {
                let deleteResults = try await calendarService.deletePublishedEvents(Array(eventIdsToRemove))
                let successfullyDeletedIds = Set(deleteResults.filter { $0.value == true }.map { $0.key })
                self.pendingRemovalSessions.removeAll { s in
                    if let calId = s.calendarEventId {
                        return successfullyDeletedIds.contains(calId)
                    }
                    return false
                }
            } catch {
                partialErrors.append("Failed to delete events: \(error.localizedDescription)")
            }
        }
        
        self.lastPublishedDate = Date()
        saveDatabase()
        
        if totalFailed == 0 && partialErrors.isEmpty {
            var msgParts: [String] = []
            if totalPublished > 0 { msgParts.append("\(totalPublished) new session\(totalPublished == 1 ? "" : "s") added") }
            if totalUpdated > 0 { msgParts.append("\(totalUpdated) session\(totalUpdated == 1 ? "" : "s") updated") }
            if !eventIdsToRemove.isEmpty { msgParts.append("\(eventIdsToRemove.count) session\(eventIdsToRemove.count == 1 ? "" : "s") removed") }
            
            if msgParts.isEmpty {
                self.publishStatusMessage = "Calendar is up to date."
            } else {
                self.publishStatusMessage = "Successfully published: " + msgParts.joined(separator: ", ") + " to Apple Calendar."
            }
            self.publishErrorMessage = nil
        } else {
            self.publishErrorMessage = "Publishing completed with \(totalFailed) failure\(totalFailed == 1 ? "" : "s"): \(partialErrors.joined(separator: "; ")). Successfully updated sessions were saved; you can retry publishing the remaining sessions."
            self.publishStatusMessage = nil
        }
        
        self.isPublishingCalendar = false
        
        // Refresh commitments to reflect new calendar state
        await refreshCalendarCommitments(isAutomatic: true)
    }
    
    public func checkForCalendarDiscrepancies() async {
        guard calendarAuthorizationStatus == .authorized else { return }
        do {
            let disc = try await calendarService.detectExternalDiscrepancies(
                for: workSessions,
                targetCalendarIdentifier: preferences.publicationCalendarIdentifier,
                externalCommitments: commitments
            )
            self.externalDiscrepancies = disc
        } catch {
            print("⚠️ Discrepancy check error: \(error)")
        }
    }
    
    public func resolveDiscrepancy(_ discrepancy: ExternalDiscrepancy, action: DiscrepancyResolutionAction) async {
        switch discrepancy.kind {
        case .movedInCalendar(let newStartTime, let newEndTime):
            switch action {
            case .adoptExternalChange:
                if let idx = workSessions.firstIndex(where: { $0.id == discrepancy.sessionId }) {
                    workSessions[idx].startTime = newStartTime
                    workSessions[idx].endTime = newEndTime
                    workSessions[idx].lastPublishedStartTime = newStartTime
                    workSessions[idx].lastPublishedEndTime = newEndTime
                    workSessions[idx].isManuallyAdjusted = true
                    saveDatabase()
                    recalculateSchedule()
                }
            case .restorePlannerVersion:
                if let session = workSessions.first(where: { $0.id == discrepancy.sessionId }),
                   let targetCalId = preferences.publicationCalendarIdentifier {
                    var taskLookup: [UUID: String] = [:]
                    for t in tasks { taskLookup[t.id] = t.title }
                    _ = try? await calendarService.publishSessions([session], to: targetCalId, taskTitleLookup: taskLookup)
                }
            case .dismissAlert:
                break
            }
            
        case .deletedInCalendar:
            switch action {
            case .adoptExternalChange:
                // User adopts calendar deletion: remove local session and remember the removed
                // planned minutes so the automatic replan below does not resurrect the slot.
                if let removed = workSessions.first(where: { $0.id == discrepancy.sessionId }),
                   let taskId = removed.taskId, removed.status == .planned {
                    declinedSlots.append(DeclinedSlot(taskId: taskId, start: removed.startTime, end: removed.endTime))
                }
                workSessions.removeAll(where: { $0.id == discrepancy.sessionId })
                saveDatabase()
                recalculateSchedule()
            case .restorePlannerVersion:
                // User restores session: clear old event ID and republish
                if let idx = workSessions.firstIndex(where: { $0.id == discrepancy.sessionId }) {
                    workSessions[idx].calendarEventId = nil
                    saveDatabase()
                    await publishApprovedSessions(
                        selectedAddSessionIds: [discrepancy.sessionId],
                        selectedUpdateSessionIds: [],
                        selectedRemoveSessionIds: []
                    )
                }
            case .dismissAlert:
                break
            }
            
        case .externalConflict:
            switch action {
            case .adoptExternalChange:
                // Replan around external conflict
                recalculateSchedule()
            case .restorePlannerVersion, .dismissAlert:
                break
            }
        }
        
        externalDiscrepancies.removeAll(where: { $0.sessionId == discrepancy.sessionId })
        saveDatabase()
    }
    
    // MARK: - Dismissed Tasks Management
    
    public func clearDismissedTasks() {
        let dismissed = tasks.filter { $0.isDismissed }
        guard !dismissed.isEmpty else { return }
        
        for task in dismissed {
            let record = DismissedTaskRecord(
                id: task.id,
                title: task.title,
                requiredAction: task.requiredAction,
                sourceEmailId: task.sourceEmail.id,
                sourceThreadId: task.sourceEmail.threadId,
                sourceSubject: task.sourceEmail.subject,
                sourceSender: task.sourceEmail.senderName,
                sourceCategory: task.sourceEmail.isSimulatedDemo ? "demo" : "email",
                quickCaptureRetentionId: nil,
                dismissedAt: Date(),
                notes: task.notes
            )
            clearedDismissedTasks.append(record)
        }
        
        tasks.removeAll { $0.isDismissed }
        if let sel = selectedTaskId, !tasks.contains(where: { $0.id == sel }) {
            selectedTaskId = nil
        }
        
        let log = EmailProcessingLog(
            emailId: "system-clear-dismissed",
            sender: "DayBook AI",
            subject: "Cleared Dismissed Tasks",
            timestamp: Date(),
            action: .taskDismissed,
            explanation: "Cleared \(dismissed.count) dismissed task(s) from visible list. Preserved source IDs to prevent recreation on future scans."
        )
        appendLog(log)
        
        recalculateSchedule()
        saveDatabase()
    }
    
    // MARK: - Quick Capture Workflow
    
    public func openQuickCapture(fromClipboard: Bool = true) {
        if self.quickCaptureDraft.proposals.isEmpty {
            self.quickCaptureDraft.referenceDate = Date()
            self.quickCaptureDraft.referenceTimeZoneIdentifier = self.preferences.timeZoneIdentifier
            if fromClipboard {
                readClipboardContentOnce()
            }
        }
        QuickCapturePanelController.shared.show(appState: self)
    }
    
    public func readClipboardContentOnce() {
        let pb = NSPasteboard.general
        
        // 1. Check for image on clipboard
        if let image = NSImage(pasteboard: pb),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            self.quickCaptureDraft.contentType = .image
            self.quickCaptureDraft.imageData = jpegData
            self.quickCaptureDraft.imageMimeType = "image/jpeg"
            return
        }
        
        // 2. Check for text on clipboard
        if let str = pb.string(forType: .string), !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.quickCaptureDraft.contentType = .text
            self.quickCaptureDraft.rawText = str
            return
        }
    }
    
    public func resetQuickCaptureDraft() {
        self.quickCaptureDraft = QuickCaptureDraft(
            referenceDate: Date(),
            referenceTimeZoneIdentifier: self.preferences.timeZoneIdentifier
        )
        self.quickCaptureProposals = []
        self.quickCaptureError = nil
        self.isAnalyzingQuickCapture = false
    }
    
    public func clearQuickCaptureImage() {
        self.quickCaptureDraft.imageData = nil
        self.quickCaptureDraft.imageMimeType = nil
        if self.quickCaptureDraft.rawText.isEmpty {
            self.quickCaptureDraft.contentType = .text
        }
    }
    
    public func clearQuickCaptureText() {
        self.quickCaptureDraft.rawText = ""
    }
    
    public func analyzeQuickCapture() async {
        isAnalyzingQuickCapture = true
        quickCaptureError = nil
        quickCaptureActiveModel = ollamaModel
        
        let tz = preferences.timeZone
        let refDate = quickCaptureDraft.referenceDate
        
        do {
            let (props, reasoning) = try await quickCaptureService.analyzeCapture(
                text: quickCaptureDraft.rawText,
                imageData: quickCaptureDraft.imageData,
                imageMimeType: quickCaptureDraft.imageMimeType,
                referenceDate: refDate,
                timeZone: tz,
                baseURL: ollamaBaseURL,
                model: ollamaModel
            )
            
            // Check duplicates for each proposal
            var processedProposals = props
            for idx in 0..<processedProposals.count {
                let dupWarning = QuickCaptureDuplicateDetector.checkDuplicate(
                    proposal: processedProposals[idx],
                    existingTasks: tasks,
                    existingCommitments: commitments,
                    timeZone: tz
                )
                processedProposals[idx].duplicateWarning = dupWarning
            }
            
            self.quickCaptureProposals = processedProposals
            self.quickCaptureDraft.proposals = processedProposals
            self.quickCaptureDraft.reasoning = reasoning
            
            // Optional source retention
            if preferences.quickCaptureRetainSource {
                let id = "qc_\(UUID().uuidString)"
                _ = try? quickCaptureStorageService.retainCapture(
                    id: id,
                    text: quickCaptureDraft.rawText.isEmpty ? nil : quickCaptureDraft.rawText,
                    imageData: quickCaptureDraft.imageData,
                    mimeType: quickCaptureDraft.imageMimeType
                )
            }
            
        } catch {
            self.quickCaptureError = error.localizedDescription
        }
        
        isAnalyzingQuickCapture = false
    }
    
    public func saveQuickCaptureTask(proposal: QuickCaptureProposal) {
        guard !proposal.isSaved else { return }
        let now = Date()
        let refDate = quickCaptureDraft.referenceDate
        
        let sourceEmail = EmailSource(
            id: "qc-\(UUID().uuidString)",
            threadId: "qc-\(UUID().uuidString)",
            senderName: "Quick Capture",
            senderEmail: "quickcapture@local",
            subject: proposal.title,
            receivedDate: refDate,
            snippet: proposal.supportingExcerpt.isEmpty ? proposal.title : proposal.supportingExcerpt,
            fullBody: quickCaptureDraft.rawText.isEmpty ? proposal.supportingExcerpt : quickCaptureDraft.rawText,
            category: .quickCapture,
            isSimulatedDemo: false
        )
        
        let initialStatus: TaskStatus
        if proposal.extractedDeadline != nil || proposal.planningTargetDate != nil {
            initialStatus = .ready
        } else if proposal.isAmbiguous {
            initialStatus = .needsClarification
        } else {
            initialStatus = .needsClarification
        }
        
        let task = DiscoveredTask(
            id: UUID(),
            title: proposal.title,
            requiredAction: proposal.requiredAction.isEmpty ? proposal.title : proposal.requiredAction,
            notes: proposal.notes,
            sourceEmail: sourceEmail,
            extractedDeadline: proposal.extractedDeadline,
            isDeadlineSupportedByEmail: proposal.deadlineProvenance != .unsupported,
            supportingExcerpt: proposal.supportingExcerpt,
            estimatedMinutes: proposal.estimatedDurationMinutes,
            status: initialStatus,
            uncertainDetails: proposal.isAmbiguous ? ["Clarify deadline or scope"] : [],
            clarificationPrompt: proposal.clarificationPrompt,
            isClarified: proposal.extractedDeadline != nil || proposal.planningTargetDate != nil,
            deadlineUpdateNote: nil,
            isDismissed: false,
            userOverriddenTitle: nil,
            userOverriddenDeadline: nil,
            userOverriddenDuration: proposal.isDurationInferred ? nil : proposal.estimatedDurationMinutes,
            userPriority: .medium,
            isDateOnlyDeadline: proposal.dateOnlyString != nil,
            planningTargetDate: proposal.planningTargetDate,
            originalDeadlineWording: proposal.originalDeadlineWording,
            dateOnlyDeadlineString: proposal.dateOnlyString,
            timeZoneAssumption: proposal.timeZoneAssumption,
            createdAt: now,
            updatedAt: now
        )
        
        addTask(task)
        
        // Update proposal in state
        if let idx = quickCaptureProposals.firstIndex(where: { $0.id == proposal.id }) {
            quickCaptureProposals[idx].isSaved = true
            quickCaptureProposals[idx].savedTaskId = task.id
        }
    }
    
    public func saveQuickCaptureEvent(proposal: QuickCaptureProposal) {
        guard !proposal.isSaved else { return }
        let start = proposal.eventStartTime ?? quickCaptureDraft.referenceDate
        let end = proposal.eventEndTime ?? start.addingTimeInterval(3600)
        
        let commitment = CalendarCommitment(
            id: UUID(),
            title: proposal.isTentative ? "[Tentative] \(proposal.eventTitle)" : proposal.eventTitle,
            location: proposal.location,
            startTime: start,
            endTime: end,
            isAllDay: proposal.isAllDay,
            isBusy: !proposal.isTentative,
            calendarName: "DayBook AI",
            calendarIdentifier: nil,
            colorHex: proposal.isTentative ? "#FF9500" : "#30D158",
            isSimulatedDemo: false,
            externalEventId: nil,
            isPlannerOwnEvent: true
        )
        
        addCommitment(commitment)
        
        // Update proposal in state
        if let idx = quickCaptureProposals.firstIndex(where: { $0.id == proposal.id }) {
            quickCaptureProposals[idx].isSaved = true
            quickCaptureProposals[idx].savedCommitmentId = commitment.id
        }
    }
    
    public func discardQuickCaptureProposal(id: UUID) {
        if let idx = quickCaptureProposals.firstIndex(where: { $0.id == id }) {
            quickCaptureProposals[idx].isDiscarded = true
        }
    }
    
    public func addTask(_ task: DiscoveredTask) {
        if !tasks.contains(where: { $0.id == task.id }) {
            tasks.append(task)
            saveDatabase()
            recalculateSchedule()
        }
    }
    
    public func addCommitment(_ commitment: CalendarCommitment) {
        if !commitments.contains(where: { $0.id == commitment.id }) {
            commitments.append(commitment)
            saveDatabase()
            recalculateSchedule()
        }
    }
}


/// Storage for optional add-on modules, passed to `AppState` (tests and `--render-ui` use temp folders).
/// Empty when no add-on is built in.
public struct AddOnServices {
    public init() {}

    /// Add-on storage inside `folder` (a temp folder for tests and UI renders).
    public static func inFolder(_ folder: URL) -> AddOnServices {
        AddOnServices()
    }
}
