import Foundation

public enum SessionStatus: String, Codable, CaseIterable {
    case planned = "Planned"
    case inProgress = "In Progress"
    case completed = "Completed"
    case skipped = "Skipped"
}

public struct WorkSession: Identifiable, Codable, Hashable {
    public let id: UUID
    public var taskId: UUID? // Optional reference to the underlying DiscoveredTask
    public var title: String
    public var startTime: Date
    public var endTime: Date
    public var status: SessionStatus
    public var notes: String?
    public var isLocked: Bool
    public var isManuallyAdjusted: Bool
    public var isSimulatedDemo: Bool
    public var isCarryover: Bool
    
    // Persistent Apple Calendar Publication Mapping
    public var calendarEventId: String?
    public var lastPublishedDate: Date?
    public var lastPublishedStartTime: Date?
    public var lastPublishedEndTime: Date?
    public var lastPublishedTitle: String?
    
    // Paid work (used by the optional work-tracker add-on; ordinary sessions leave these empty)
    public var isPaidWork: Bool
    public var paidJob: String?
    public var hourlyRate: Decimal?
    public var unpaidBreakMinutes: Int
    public var linkedWorkEntryId: String?
    public var isActualHoursConfirmed: Bool
    public var confirmedActualStartTime: Date?
    public var confirmedActualEndTime: Date?
    public var confirmedUnpaidBreakMinutes: Int?
    
    public init(
        id: UUID = UUID(),
        taskId: UUID? = nil,
        title: String,
        startTime: Date,
        endTime: Date,
        status: SessionStatus = .planned,
        notes: String? = nil,
        isLocked: Bool = false,
        isManuallyAdjusted: Bool = false,
        isSimulatedDemo: Bool = false,
        isCarryover: Bool = false,
        calendarEventId: String? = nil,
        lastPublishedDate: Date? = nil,
        lastPublishedStartTime: Date? = nil,
        lastPublishedEndTime: Date? = nil,
        lastPublishedTitle: String? = nil,
        isPaidWork: Bool = false,
        paidJob: String? = nil,
        hourlyRate: Decimal? = 19,
        unpaidBreakMinutes: Int = 0,
        linkedWorkEntryId: String? = nil,
        isActualHoursConfirmed: Bool = false,
        confirmedActualStartTime: Date? = nil,
        confirmedActualEndTime: Date? = nil,
        confirmedUnpaidBreakMinutes: Int? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.notes = notes
        self.isLocked = isLocked
        self.isManuallyAdjusted = isManuallyAdjusted
        self.isSimulatedDemo = isSimulatedDemo
        self.isCarryover = isCarryover
        self.calendarEventId = calendarEventId
        self.lastPublishedDate = lastPublishedDate
        self.lastPublishedStartTime = lastPublishedStartTime
        self.lastPublishedEndTime = lastPublishedEndTime
        self.lastPublishedTitle = lastPublishedTitle
        self.isPaidWork = isPaidWork
        self.paidJob = paidJob
        self.hourlyRate = hourlyRate
        self.unpaidBreakMinutes = unpaidBreakMinutes
        self.linkedWorkEntryId = linkedWorkEntryId
        self.isActualHoursConfirmed = isActualHoursConfirmed
        self.confirmedActualStartTime = confirmedActualStartTime
        self.confirmedActualEndTime = confirmedActualEndTime
        self.confirmedUnpaidBreakMinutes = confirmedUnpaidBreakMinutes
    }
    
    enum CodingKeys: String, CodingKey {
        case id, taskId, title, startTime, endTime, status, notes
        case isLocked, isManuallyAdjusted, isSimulatedDemo, isCarryover
        case calendarEventId, lastPublishedDate
        case lastPublishedStartTime, lastPublishedEndTime, lastPublishedTitle
        case isPaidWork, paidJob, hourlyRate, unpaidBreakMinutes, linkedWorkEntryId
        case isActualHoursConfirmed, confirmedActualStartTime, confirmedActualEndTime, confirmedUnpaidBreakMinutes
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.taskId = try container.decodeIfPresent(UUID.self, forKey: .taskId)
        self.title = try container.decode(String.self, forKey: .title)
        self.startTime = try container.decode(Date.self, forKey: .startTime)
        self.endTime = try container.decode(Date.self, forKey: .endTime)
        self.status = try container.decodeIfPresent(SessionStatus.self, forKey: .status) ?? .planned
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        self.isManuallyAdjusted = try container.decodeIfPresent(Bool.self, forKey: .isManuallyAdjusted) ?? false
        self.isSimulatedDemo = try container.decodeIfPresent(Bool.self, forKey: .isSimulatedDemo) ?? false
        self.isCarryover = try container.decodeIfPresent(Bool.self, forKey: .isCarryover) ?? false
        self.calendarEventId = try container.decodeIfPresent(String.self, forKey: .calendarEventId)
        self.lastPublishedDate = try container.decodeIfPresent(Date.self, forKey: .lastPublishedDate)
        self.lastPublishedStartTime = try container.decodeIfPresent(Date.self, forKey: .lastPublishedStartTime)
        self.lastPublishedEndTime = try container.decodeIfPresent(Date.self, forKey: .lastPublishedEndTime)
        self.lastPublishedTitle = try container.decodeIfPresent(String.self, forKey: .lastPublishedTitle)
        self.isPaidWork = try container.decodeIfPresent(Bool.self, forKey: .isPaidWork) ?? false
        self.paidJob = try container.decodeIfPresent(String.self, forKey: .paidJob)
        self.hourlyRate = try container.decodeIfPresent(Decimal.self, forKey: .hourlyRate) ?? 19
        self.unpaidBreakMinutes = try container.decodeIfPresent(Int.self, forKey: .unpaidBreakMinutes) ?? 0
        self.linkedWorkEntryId = try container.decodeIfPresent(String.self, forKey: .linkedWorkEntryId)
        self.isActualHoursConfirmed = try container.decodeIfPresent(Bool.self, forKey: .isActualHoursConfirmed) ?? false
        self.confirmedActualStartTime = try container.decodeIfPresent(Date.self, forKey: .confirmedActualStartTime)
        self.confirmedActualEndTime = try container.decodeIfPresent(Date.self, forKey: .confirmedActualEndTime)
        self.confirmedUnpaidBreakMinutes = try container.decodeIfPresent(Int.self, forKey: .confirmedUnpaidBreakMinutes)
    }
    
    public var durationMinutes: Int {
        max(1, Int(endTime.timeIntervalSince(startTime) / 60))
    }
    
    public var plannedPaidMinutes: Int {
        max(0, durationMinutes - unpaidBreakMinutes)
    }
    
    public var plannedPaidHours: Decimal {
        Decimal(plannedPaidMinutes) / 60
    }
    
    public var isPublished: Bool {
        calendarEventId != nil
    }
    
    public var hasUnpublishedChanges: Bool {
        guard isPublished else { return false }
        if let pubStart = lastPublishedStartTime, pubStart != startTime { return true }
        if let pubEnd = lastPublishedEndTime, pubEnd != endTime { return true }
        if let pubTitle = lastPublishedTitle, pubTitle != title { return true }
        return false
    }
}
