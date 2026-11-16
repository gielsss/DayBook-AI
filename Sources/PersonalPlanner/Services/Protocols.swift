import Foundation

public struct TaskExtractionResult {
    public let newTasks: [DiscoveredTask]
    public let updatedTasks: [DiscoveredTask]
    public let logs: [EmailProcessingLog]
    
    public init(
        newTasks: [DiscoveredTask] = [],
        updatedTasks: [DiscoveredTask] = [],
        logs: [EmailProcessingLog] = []
    ) {
        self.newTasks = newTasks
        self.updatedTasks = updatedTasks
        self.logs = logs
    }
}

public protocol StorageServiceProtocol {
    var databaseURL: URL { get }
    func loadDatabase() -> PlannerDatabase
    func saveDatabase(_ db: PlannerDatabase) throws
    func resetDatabase() -> PlannerDatabase
}

public protocol EmailRetrievalServiceProtocol {
    func fetchRecentMessages() async throws -> [EmailSource]
}

public protocol TaskExtractionServiceProtocol {
    func extractTasks(
        from emails: [EmailSource],
        existingTasks: [DiscoveredTask]
    ) async throws -> TaskExtractionResult
}

public enum CalendarAuthorizationStatus: String, Codable {
    case notDetermined
    case restricted
    case denied
    case authorized
}

public struct CalendarAccountInfo: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let sourceTitle: String
    public let colorHex: String
    public let allowsModifications: Bool
    
    public init(id: String, title: String, sourceTitle: String, colorHex: String, allowsModifications: Bool) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.colorHex = colorHex
        self.allowsModifications = allowsModifications
    }
    
    public var providerSyncDescription: String {
        let lower = sourceTitle.lowercased()
        if lower.contains("icloud") {
            return "Syncs across your Apple devices via iCloud (\(sourceTitle))."
        } else if lower.contains("google") {
            return "Syncs with your Google Calendar account (\(sourceTitle))."
        } else if lower.contains("exchange") || lower.contains("outlook") {
            return "Syncs with your Microsoft Exchange account (\(sourceTitle))."
        } else if lower.contains("local") || lower.contains("on my mac") || lower.contains("mac") || lower.contains("demonstration") || lower.contains("demo") {
            return "Events stay strictly local on this Mac (On My Mac). Not synced to external cloud servers."
        } else {
            return "Account provider: \(sourceTitle)."
        }
    }
}

public protocol CalendarServiceProtocol: AnyObject {
    var authorizationStatus: CalendarAuthorizationStatus { get }
    var onCalendarStoreChanged: (() -> Void)? { get set }
    func requestAccess() async throws -> Bool
    func fetchAvailableCalendars() async throws -> [CalendarAccountInfo]
    func fetchCommitments(
        for dateRange: ClosedRange<Date>,
        selectedCalendarIdentifiers: Set<String>?,
        allDayBlocksTime: Bool
    ) async throws -> [CalendarCommitment]
    
    // Publication & Event Sync Methods
    func getOrCreatePlannerCalendar() async throws -> CalendarAccountInfo
    func publishSessions(
        _ sessions: [WorkSession],
        to calendarIdentifier: String,
        taskTitleLookup: [UUID: String]
    ) async throws -> PublishBatchResult
    func deletePublishedEvents(
        _ eventIdentifiers: [String]
    ) async throws -> [String: Bool]
    func detectExternalDiscrepancies(
        for sessions: [WorkSession],
        targetCalendarIdentifier: String?,
        externalCommitments: [CalendarCommitment]
    ) async throws -> [ExternalDiscrepancy]
}

public extension CalendarServiceProtocol {
    func fetchCommitments(for dateRange: ClosedRange<Date>) async throws -> [CalendarCommitment] {
        return try await fetchCommitments(
            for: dateRange,
            selectedCalendarIdentifiers: nil,
            allDayBlocksTime: false
        )
    }
}

public protocol SchedulingEngineProtocol {
    /// keepPlannedBefore: planned sessions of open tasks starting before this time are kept in place.
    /// taskDayLimits: most minutes a task may have on a day (start of day) after you deleted one of its sessions there.
    func generateSchedule(
        tasks: [DiscoveredTask],
        commitments: [CalendarCommitment],
        existingSessions: [WorkSession],
        preferences: UserPreferences,
        dateRange: ClosedRange<Date>,
        currentDate: Date,
        deletedProposedMinutesByTaskId: [String: Int],
        keepPlannedBefore: Date?,
        taskDayLimits: [UUID: [Date: Int]]
    ) -> SchedulingResult

    func generateSchedule(
        tasks: [DiscoveredTask],
        commitments: [CalendarCommitment],
        existingSessions: [WorkSession],
        preferences: UserPreferences,
        dateRange: ClosedRange<Date>,
        currentDate: Date,
        deletedProposedMinutesByTaskId: [String: Int],
        keepPlannedBefore: Date?
    ) -> SchedulingResult

    func generateSchedule(
        tasks: [DiscoveredTask],
        commitments: [CalendarCommitment],
        existingSessions: [WorkSession],
        preferences: UserPreferences,
        dateRange: ClosedRange<Date>,
        currentDate: Date,
        deletedProposedMinutesByTaskId: [String: Int]
    ) -> SchedulingResult
    
    func generateSchedule(
        tasks: [DiscoveredTask],
        commitments: [CalendarCommitment],
        existingSessions: [WorkSession],
        preferences: UserPreferences,
        dateRange: ClosedRange<Date>,
        currentDate: Date
    ) -> SchedulingResult
    
    func scheduleSessions(
        for tasks: [DiscoveredTask],
        commitments: [CalendarCommitment],
        preferences: UserPreferences,
        dateRange: ClosedRange<Date>
    ) -> [WorkSession]
}

public extension SchedulingEngineProtocol {
    func generateSchedule(
        tasks: [DiscoveredTask],
        commitments: [CalendarCommitment],
        existingSessions: [WorkSession],
        preferences: UserPreferences,
        dateRange: ClosedRange<Date>,
        currentDate: Date,
        deletedProposedMinutesByTaskId: [String: Int],
        keepPlannedBefore: Date?
    ) -> SchedulingResult {
        generateSchedule(tasks: tasks, commitments: commitments, existingSessions: existingSessions,
                         preferences: preferences, dateRange: dateRange, currentDate: currentDate,
                         deletedProposedMinutesByTaskId: deletedProposedMinutesByTaskId,
                         keepPlannedBefore: keepPlannedBefore, taskDayLimits: [:])
    }

    func generateSchedule(
        tasks: [DiscoveredTask],
        commitments: [CalendarCommitment],
        existingSessions: [WorkSession],
        preferences: UserPreferences,
        dateRange: ClosedRange<Date>,
        currentDate: Date,
        deletedProposedMinutesByTaskId: [String: Int]
    ) -> SchedulingResult {
        return generateSchedule(
            tasks: tasks,
            commitments: commitments,
            existingSessions: existingSessions,
            preferences: preferences,
            dateRange: dateRange,
            currentDate: currentDate,
            deletedProposedMinutesByTaskId: deletedProposedMinutesByTaskId,
            keepPlannedBefore: nil
        )
    }

    func generateSchedule(
        tasks: [DiscoveredTask],
        commitments: [CalendarCommitment],
        existingSessions: [WorkSession],
        preferences: UserPreferences,
        dateRange: ClosedRange<Date>,
        currentDate: Date
    ) -> SchedulingResult {
        return generateSchedule(
            tasks: tasks,
            commitments: commitments,
            existingSessions: existingSessions,
            preferences: preferences,
            dateRange: dateRange,
            currentDate: currentDate,
            deletedProposedMinutesByTaskId: [:]
        )
    }
    
    func scheduleSessions(
        for tasks: [DiscoveredTask],
        commitments: [CalendarCommitment],
        preferences: UserPreferences,
        dateRange: ClosedRange<Date>
    ) -> [WorkSession] {
        let result = generateSchedule(
            tasks: tasks,
            commitments: commitments,
            existingSessions: [],
            preferences: preferences,
            dateRange: dateRange,
            currentDate: dateRange.lowerBound,
            deletedProposedMinutesByTaskId: [:]
        )
        return result.allSessions
    }
}

public protocol KeychainServiceProtocol {
    func saveCredential(key: String, value: String) throws
    func getCredential(key: String) -> String?
    func deleteCredential(key: String) throws
}
