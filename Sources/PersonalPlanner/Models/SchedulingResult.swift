import Foundation

public enum UnscheduledReason: String, Codable, CaseIterable {
    case deadlinePassed = "Deadline Already Passed"
    case insufficientTimeBeforeDeadline = "Insufficient Time Before Deadline"
    case missingDeadline = "Missing Deadline (Target Needed)"
    case needsActionClarification = "Unclear Required Action (Needs Clarification)"
    case dailyCapReached = "Daily Planned Work Limit Reached"
    case calendarFullyBooked = "Working Hours Occupied by Calendar Commitments"
}

public struct UnscheduledTaskReport: Identifiable, Codable, Hashable {
    public var id: UUID { task.id }
    public var task: DiscoveredTask
    public var totalEstimatedMinutes: Int
    public var alreadyCompletedMinutes: Int
    public var scheduledMinutes: Int
    public var unscheduledMinutes: Int
    public var primaryReason: UnscheduledReason
    public var detailedExplanation: String
    
    public init(
        task: DiscoveredTask,
        totalEstimatedMinutes: Int,
        alreadyCompletedMinutes: Int = 0,
        scheduledMinutes: Int = 0,
        unscheduledMinutes: Int,
        primaryReason: UnscheduledReason,
        detailedExplanation: String
    ) {
        self.task = task
        self.totalEstimatedMinutes = totalEstimatedMinutes
        self.alreadyCompletedMinutes = alreadyCompletedMinutes
        self.scheduledMinutes = scheduledMinutes
        self.unscheduledMinutes = unscheduledMinutes
        self.primaryReason = primaryReason
        self.detailedExplanation = detailedExplanation
    }
}

public struct SchedulingStats: Codable, Hashable {
    public var tasksEvaluated: Int
    public var fullyScheduledCount: Int
    public var partiallyScheduledCount: Int
    public var unscheduledCount: Int
    public var totalPlannedMinutes: Int
    public var replannedDate: Date
    
    public init(
        tasksEvaluated: Int = 0,
        fullyScheduledCount: Int = 0,
        partiallyScheduledCount: Int = 0,
        unscheduledCount: Int = 0,
        totalPlannedMinutes: Int = 0,
        replannedDate: Date = Date()
    ) {
        self.tasksEvaluated = tasksEvaluated
        self.fullyScheduledCount = fullyScheduledCount
        self.partiallyScheduledCount = partiallyScheduledCount
        self.unscheduledCount = unscheduledCount
        self.totalPlannedMinutes = totalPlannedMinutes
        self.replannedDate = replannedDate
    }
    
    public var totalPlannedHoursFormatted: String {
        let hrs = Double(totalPlannedMinutes) / 60.0
        return String(format: "%.1f hrs", hrs)
    }
}

public struct SchedulingResult: Codable {
    public var proposedSessions: [WorkSession]
    public var preservedSessions: [WorkSession]
    public var allSessions: [WorkSession]
    public var unscheduledReports: [UnscheduledTaskReport]
    public var ambiguousTasks: [DiscoveredTask]
    public var stats: SchedulingStats
    /// How urgent it is to start each scheduled task (slack before its deadline). Not saved.
    public var urgencyByTaskId: [UUID: TaskUrgency] = [:]
    
    enum CodingKeys: String, CodingKey {
        case proposedSessions, preservedSessions, allSessions, unscheduledReports, ambiguousTasks, stats
    }
    
    public init(
        proposedSessions: [WorkSession] = [],
        preservedSessions: [WorkSession] = [],
        allSessions: [WorkSession] = [],
        unscheduledReports: [UnscheduledTaskReport] = [],
        ambiguousTasks: [DiscoveredTask] = [],
        stats: SchedulingStats = SchedulingStats()
    ) {
        self.proposedSessions = proposedSessions
        self.preservedSessions = preservedSessions
        self.allSessions = allSessions
        self.unscheduledReports = unscheduledReports
        self.ambiguousTasks = ambiguousTasks
        self.stats = stats
    }
}
