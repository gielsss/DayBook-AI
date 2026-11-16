import Foundation

/// A time where you deleted a planned work session. The planner won't use it again; the work is re-planned elsewhere.
/// A planned session you deleted. With a task: that task gets at most `minutesLeftThatDay` (nil = none)
/// on that day from then on, so other work moves up into the time. Without a task: the time is blocked.
public struct DeclinedSlot: Codable, Equatable {
    public var taskId: UUID?
    public var start: Date
    public var end: Date
    public var minutesLeftThatDay: Int?

    public init(taskId: UUID?, start: Date, end: Date, minutesLeftThatDay: Int? = nil) {
        self.taskId = taskId
        self.start = start
        self.end = end
        self.minutesLeftThatDay = minutesLeftThatDay
    }
}

public struct PlannerDatabase: Codable {
    public var version: Int
    public var tasks: [DiscoveredTask]
    public var workSessions: [WorkSession]
    public var calendarCommitments: [CalendarCommitment]
    public var processedLogs: [EmailProcessingLog]
    public var preferences: UserPreferences
    public var lastSyncDate: Date?
    public var lastScanDate: Date?
    public var lastScanError: String?
    public var lastScanRange: String?
    public var lastScanCoverage: String?
    public var extractionCache: [String: CachedEmailExtraction]
    public var pendingRemovalSessions: [WorkSession]
    public var failedEmailRecords: [FailedEmailRecord]
    public var clearedDismissedTasks: [DismissedTaskRecord]
    public var deletedProposedMinutesByTaskId: [String: Int]
    /// Times where you deleted planned work: never planned again (the work itself is re-planned elsewhere).
    public var declinedSlots: [DeclinedSlot]
    /// Tasks a sync found for the first time that you haven't looked at yet ("New" in Tasks).
    public var newlyFoundTaskIds: [UUID]
    /// Finished tasks waiting for "How long did it take?".
    public var timeQuestions: [TimeQuestion] = []
    
    public init(
        version: Int = 3,
        tasks: [DiscoveredTask] = [],
        workSessions: [WorkSession] = [],
        calendarCommitments: [CalendarCommitment] = [],
        processedLogs: [EmailProcessingLog] = [],
        preferences: UserPreferences = UserPreferences(),
        lastSyncDate: Date? = nil,
        lastScanDate: Date? = nil,
        lastScanError: String? = nil,
        lastScanRange: String? = nil,
        lastScanCoverage: String? = nil,
        extractionCache: [String: CachedEmailExtraction] = [:],
        pendingRemovalSessions: [WorkSession] = [],
        failedEmailRecords: [FailedEmailRecord] = [],
        clearedDismissedTasks: [DismissedTaskRecord] = [],
        deletedProposedMinutesByTaskId: [String: Int] = [:],
        declinedSlots: [DeclinedSlot] = [],
        newlyFoundTaskIds: [UUID] = []
    ) {
        self.version = version
        self.tasks = tasks
        self.workSessions = workSessions
        self.calendarCommitments = calendarCommitments
        self.processedLogs = processedLogs
        self.preferences = preferences
        self.lastSyncDate = lastSyncDate
        self.lastScanDate = lastScanDate
        self.lastScanError = lastScanError
        self.lastScanRange = lastScanRange
        self.lastScanCoverage = lastScanCoverage
        self.extractionCache = extractionCache
        self.pendingRemovalSessions = pendingRemovalSessions
        self.failedEmailRecords = failedEmailRecords
        self.clearedDismissedTasks = clearedDismissedTasks
        self.deletedProposedMinutesByTaskId = deletedProposedMinutesByTaskId
        self.declinedSlots = declinedSlots
        self.newlyFoundTaskIds = newlyFoundTaskIds
    }
    
    enum CodingKeys: String, CodingKey {
        case version, tasks, workSessions, calendarCommitments, processedLogs
        case preferences, lastSyncDate, lastScanDate, lastScanError, lastScanRange, lastScanCoverage
        case extractionCache, pendingRemovalSessions, failedEmailRecords
        case clearedDismissedTasks, deletedProposedMinutesByTaskId, declinedSlots, newlyFoundTaskIds, timeQuestions
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 3
        self.tasks = try container.decodeIfPresent([DiscoveredTask].self, forKey: .tasks) ?? []
        self.workSessions = try container.decodeIfPresent([WorkSession].self, forKey: .workSessions) ?? []
        self.calendarCommitments = try container.decodeIfPresent([CalendarCommitment].self, forKey: .calendarCommitments) ?? []
        self.processedLogs = try container.decodeIfPresent([EmailProcessingLog].self, forKey: .processedLogs) ?? []
        self.preferences = try container.decodeIfPresent(UserPreferences.self, forKey: .preferences) ?? UserPreferences()
        self.lastSyncDate = try container.decodeIfPresent(Date.self, forKey: .lastSyncDate)
        self.lastScanDate = try container.decodeIfPresent(Date.self, forKey: .lastScanDate)
        self.lastScanError = try container.decodeIfPresent(String.self, forKey: .lastScanError)
        self.lastScanRange = try container.decodeIfPresent(String.self, forKey: .lastScanRange)
        self.lastScanCoverage = try container.decodeIfPresent(String.self, forKey: .lastScanCoverage)
        self.extractionCache = try container.decodeIfPresent([String: CachedEmailExtraction].self, forKey: .extractionCache) ?? [:]
        self.pendingRemovalSessions = try container.decodeIfPresent([WorkSession].self, forKey: .pendingRemovalSessions) ?? []
        self.failedEmailRecords = try container.decodeIfPresent([FailedEmailRecord].self, forKey: .failedEmailRecords) ?? []
        self.clearedDismissedTasks = try container.decodeIfPresent([DismissedTaskRecord].self, forKey: .clearedDismissedTasks) ?? []
        self.deletedProposedMinutesByTaskId = try container.decodeIfPresent([String: Int].self, forKey: .deletedProposedMinutesByTaskId) ?? [:]
        self.declinedSlots = (try? container.decodeIfPresent([DeclinedSlot].self, forKey: .declinedSlots)) ?? []
        self.timeQuestions = (try? container.decodeIfPresent([TimeQuestion].self, forKey: .timeQuestions)) ?? []
        self.newlyFoundTaskIds = (try? container.decodeIfPresent([UUID].self, forKey: .newlyFoundTaskIds)) ?? []
    }
}
