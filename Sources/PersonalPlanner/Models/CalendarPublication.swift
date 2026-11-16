import Foundation

public enum ExternalDiscrepancyKind: Codable, Hashable {
    case deletedInCalendar
    case movedInCalendar(newStartTime: Date, newEndTime: Date)
    case externalConflict(conflictingTitle: String, conflictStart: Date, conflictEnd: Date)
}

public enum DiscrepancyResolutionAction {
    case adoptExternalChange
    case restorePlannerVersion
    case dismissAlert
}

public struct ExternalDiscrepancy: Identifiable, Codable, Hashable {
    public var id: UUID { sessionId }
    public let sessionId: UUID
    public let calendarEventId: String
    public let sessionTitle: String
    public let kind: ExternalDiscrepancyKind
    public let detectedDate: Date
    
    public init(
        sessionId: UUID,
        calendarEventId: String,
        sessionTitle: String,
        kind: ExternalDiscrepancyKind,
        detectedDate: Date = Date()
    ) {
        self.sessionId = sessionId
        self.calendarEventId = calendarEventId
        self.sessionTitle = sessionTitle
        self.kind = kind
        self.detectedDate = detectedDate
    }
}

public struct PublishBatchResult: Codable {
    public var publishedCount: Int
    public var updatedCount: Int
    public var failedCount: Int
    public var successSessionEventMap: [UUID: String] // sessionId -> calendarEventId
    public var errors: [UUID: String] // sessionId -> localized error message
    public var destinationCalendarId: String
    public var destinationCalendarName: String
    public var executedDate: Date
    
    public init(
        publishedCount: Int = 0,
        updatedCount: Int = 0,
        failedCount: Int = 0,
        successSessionEventMap: [UUID: String] = [:],
        errors: [UUID: String] = [:],
        destinationCalendarId: String = "",
        destinationCalendarName: String = "",
        executedDate: Date = Date()
    ) {
        self.publishedCount = publishedCount
        self.updatedCount = updatedCount
        self.failedCount = failedCount
        self.successSessionEventMap = successSessionEventMap
        self.errors = errors
        self.destinationCalendarId = destinationCalendarId
        self.destinationCalendarName = destinationCalendarName
        self.executedDate = executedDate
    }
    
    public var isCompleteSuccess: Bool {
        failedCount == 0 && errors.isEmpty
    }
}

public struct CalendarPublicationPlan {
    public var toAdd: [WorkSession]
    public var toUpdate: [WorkSession]
    public var toRemove: [WorkSession]
    
    public init(
        toAdd: [WorkSession] = [],
        toUpdate: [WorkSession] = [],
        toRemove: [WorkSession] = []
    ) {
        self.toAdd = toAdd
        self.toUpdate = toUpdate
        self.toRemove = toRemove
    }
    
    public var totalChangeCount: Int {
        toAdd.count + toUpdate.count + toRemove.count
    }
    
    public var hasChanges: Bool {
        totalChangeCount > 0
    }
}
