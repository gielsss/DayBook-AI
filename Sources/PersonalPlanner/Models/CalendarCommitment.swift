import Foundation

public struct CalendarCommitment: Identifiable, Codable, Hashable {
    public let id: UUID
    public var title: String
    public var location: String?
    public var startTime: Date
    public var endTime: Date
    public var isAllDay: Bool
    public var isBusy: Bool
    public var calendarName: String
    public var calendarIdentifier: String?
    public var colorHex: String
    public var isSimulatedDemo: Bool
    public var externalEventId: String?
    public var isPlannerOwnEvent: Bool
    
    public init(
        id: UUID = UUID(),
        title: String,
        location: String? = nil,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool = false,
        isBusy: Bool = true,
        calendarName: String = "Calendar",
        calendarIdentifier: String? = nil,
        colorHex: String = "#0A84FF",
        isSimulatedDemo: Bool = false,
        externalEventId: String? = nil,
        isPlannerOwnEvent: Bool = false
    ) {
        self.id = id
        self.title = title
        self.location = location
        self.startTime = startTime
        self.endTime = endTime
        self.isAllDay = isAllDay
        self.isBusy = isBusy
        self.calendarName = calendarName
        self.calendarIdentifier = calendarIdentifier
        self.colorHex = colorHex
        self.isSimulatedDemo = isSimulatedDemo
        self.externalEventId = externalEventId
        self.isPlannerOwnEvent = isPlannerOwnEvent
    }

    /// A planner-local commitment (e.g. an event saved from Quick Capture) that does not come from
    /// Apple Calendar. Such commitments must survive calendar refreshes.
    public var isLocalOnly: Bool {
        externalEventId == nil && calendarIdentifier == nil && !isSimulatedDemo
    }

    /// Whether this commitment occupies time for scheduling. Calendar mirrors of the planner's own
    /// published sessions do not block (the session itself does), but local planner events do.
    public var blocksScheduling: Bool {
        isBusy && (!isPlannerOwnEvent || isLocalOnly)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, location, startTime, endTime, isAllDay, isBusy
        case calendarName, calendarIdentifier, colorHex, isSimulatedDemo
        case externalEventId, isPlannerOwnEvent
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.location = try container.decodeIfPresent(String.self, forKey: .location)
        self.startTime = try container.decode(Date.self, forKey: .startTime)
        self.endTime = try container.decode(Date.self, forKey: .endTime)
        self.isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        self.isBusy = try container.decodeIfPresent(Bool.self, forKey: .isBusy) ?? true
        self.calendarName = try container.decodeIfPresent(String.self, forKey: .calendarName) ?? "Calendar"
        self.calendarIdentifier = try container.decodeIfPresent(String.self, forKey: .calendarIdentifier)
        self.colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "#0A84FF"
        self.isSimulatedDemo = try container.decodeIfPresent(Bool.self, forKey: .isSimulatedDemo) ?? false
        self.externalEventId = try container.decodeIfPresent(String.self, forKey: .externalEventId)
        self.isPlannerOwnEvent = try container.decodeIfPresent(Bool.self, forKey: .isPlannerOwnEvent) ?? false
    }
    
    public var durationMinutes: Int {
        max(1, Int(endTime.timeIntervalSince(startTime) / 60))
    }
    
    public var isMultiDay: Bool {
        let cal = Calendar.current
        return !cal.isDate(startTime, inSameDayAs: endTime)
    }
}
