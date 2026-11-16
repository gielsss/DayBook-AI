import Foundation

public enum DateOnlyDeadlinePolicy: String, Codable, CaseIterable, Identifiable {
    case endOfWorkday = "End of Workday (5:00 PM)"
    case endOfDay = "End of Day (11:59 PM)"
    case startOfWorkday = "Start of Workday (9:00 AM)"
    
    public var id: String { rawValue }
    
    public var shortTitle: String {
        switch self {
        case .endOfWorkday: return "End of Workday"
        case .endOfDay: return "End of Day (11:59 PM)"
        case .startOfWorkday: return "Start of Workday"
        }
    }
    
    public var description: String {
        switch self {
        case .endOfWorkday: return "Tasks due on a specific date will be scheduled to finish before the end of working hours on that day."
        case .endOfDay: return "Tasks due on a specific date will be scheduled up to 11:59 PM on that day."
        case .startOfWorkday: return "Tasks due on a specific date must be completed before working hours start on that day (i.e. by previous workday)."
        }
    }
}

public struct WeekdayHours: Codable, Equatable, Hashable {
    public var isWorkday: Bool
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int
    
    public init(
        isWorkday: Bool = true,
        startHour: Int = 9,
        startMinute: Int = 0,
        endHour: Int = 17,
        endMinute: Int = 0
    ) {
        self.isWorkday = isWorkday
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }
    
    public static var defaultSchedule: [Int: WeekdayHours] {
        return [
            1: WeekdayHours(isWorkday: false, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0), // Sunday
            2: WeekdayHours(isWorkday: true, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0),  // Monday
            3: WeekdayHours(isWorkday: true, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0),  // Tuesday
            4: WeekdayHours(isWorkday: true, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0),  // Wednesday
            5: WeekdayHours(isWorkday: true, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0),  // Thursday
            6: WeekdayHours(isWorkday: true, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0),  // Friday
            7: WeekdayHours(isWorkday: false, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0)  // Saturday
        ]
    }
}

/// A finished task waiting for "How long did it take?" (Today).
public struct TimeQuestion: Codable, Equatable, Identifiable {
    public var taskId: UUID
    public var title: String
    /// The estimate before any adjustment from history (what's being judged).
    public var plannedMinutes: Int
    /// Prefilled answer: the checked-off session time, or the plan when there were none.
    public var suggestedMinutes: Int
    public var askedAt: Date
    public var id: UUID { taskId }

    public init(taskId: UUID, title: String, plannedMinutes: Int, suggestedMinutes: Int, askedAt: Date) {
        self.taskId = taskId
        self.title = title
        self.plannedMinutes = plannedMinutes
        self.suggestedMinutes = suggestedMinutes
        self.askedAt = askedAt
    }
}

/// One finished task: how long it was estimated to take vs. how long you said it took.
public struct EstimateRecord: Codable, Equatable {
    public var kind: String        // "problem set", "essay", "lab"… (see AppState.workKind)
    public var course: String      // Canvas/Gradescope course name, or "" for email tasks
    public var title: String
    public var estimatedMinutes: Int
    public var actualMinutes: Int
    public var date: Date

    public init(kind: String, course: String, title: String, estimatedMinutes: Int, actualMinutes: Int, date: Date) {
        self.kind = kind
        self.course = course
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.actualMinutes = actualMinutes
        self.date = date
    }
}

public struct UserPreferences: Codable, Equatable {
    public var workStartHour: Int
    public var workStartMinute: Int
    public var workEndHour: Int
    public var workEndMinute: Int
    public var defaultSessionMinutes: Int
    public var minSessionMinutes: Int
    public var breakMinutes: Int
    public var lunchStartHour: Int
    public var lunchDurationMinutes: Int
    
    // Advanced scheduling rules
    public var weekdayWorkingHours: [Int: WeekdayHours]
    public var maxDailyWorkMinutes: Int
    public var deadlineBufferMinutes: Int
    public var dateOnlyDeadlinePolicy: DateOnlyDeadlinePolicy
    public var includeDemoDataInPlan: Bool
    
    // Milestone connection statuses
    public var isSimulationMode: Bool
    public var isGmailConnected: Bool
    public var isAppleCalendarConnected: Bool
    public var selectedCalendarIdentifiers: [String]
    public var allDayEventsBlockTime: Bool
    public var publicationCalendarIdentifier: String?
    
    // Local AI (Ollama): one model for email scanning, Quick Capture and receipts
    public var ollamaModel: String
    public var ollamaBaseURL: String
    
    // Canvas LMS (sign-in cookies / token live in Keychain, never here)
    public var canvasBaseURL: String
    public var lastCanvasSyncDate: Date?
    /// When set, Canvas is read through a signed-in tab in this browser instead of an in-app sign-in.
    public var canvasBrowser: CanvasBrowser?
    /// When set, Gradescope assignments are read through a signed-in Gradescope tab in this browser.
    public var gradescopeBrowser: CanvasBrowser?
    public var lastGradescopeSyncDate: Date?
    
    // Configurable Timezone
    public var timeZoneIdentifier: String
    
    // Quick Capture
    public var quickCaptureShortcut: String
    public var quickCaptureRetainSource: Bool
    
    // Sync Everything: runs automatically at these hours (local time) while DayBook AI is open
    public var autoSyncEnabled: Bool
    public var lastFullSyncDate: Date?
    // Morning summary notification and AI time estimates for Canvas/Gradescope
    public var morningSummaryEnabled: Bool
    public var lastMorningSummaryDate: Date?
    public var aiTimeEstimatesEnabled: Bool
    // Planner: keep today steady, learn from actual time, evening check-in
    public var keepTodaySteady: Bool
    public var learnFromActualTime: Bool
    public var estimateHistory: [EstimateRecord]
    public var eveningCheckInEnabled: Bool
    public var lastEveningCheckInDate: Date?
    public static let autoSyncHours = [8, 13, 18]
    
    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone.current
    }
    
    public init(
        workStartHour: Int = 9,
        workStartMinute: Int = 0,
        workEndHour: Int = 17,
        workEndMinute: Int = 0,
        defaultSessionMinutes: Int = 45,
        minSessionMinutes: Int = 25,
        breakMinutes: Int = 15,
        lunchStartHour: Int = 12,
        lunchDurationMinutes: Int = 60,
        weekdayWorkingHours: [Int: WeekdayHours] = WeekdayHours.defaultSchedule,
        maxDailyWorkMinutes: Int = 360,
        deadlineBufferMinutes: Int = 60,
        dateOnlyDeadlinePolicy: DateOnlyDeadlinePolicy = .endOfWorkday,
        includeDemoDataInPlan: Bool = false,
        isSimulationMode: Bool = true,
        isGmailConnected: Bool = false,
        isAppleCalendarConnected: Bool = true,
        selectedCalendarIdentifiers: [String] = [],
        allDayEventsBlockTime: Bool = false,
        publicationCalendarIdentifier: String? = nil,
        ollamaModel: String = OllamaDefaults.model,
        canvasBaseURL: String = "",
        lastCanvasSyncDate: Date? = nil,
        canvasBrowser: CanvasBrowser? = nil,
        gradescopeBrowser: CanvasBrowser? = nil,
        lastGradescopeSyncDate: Date? = nil,
        ollamaBaseURL: String = OllamaDefaults.baseURL,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        quickCaptureShortcut: String = "Command+Shift+C",
        quickCaptureRetainSource: Bool = false,
        autoSyncEnabled: Bool = true,
        lastFullSyncDate: Date? = nil,
        morningSummaryEnabled: Bool = true,
        lastMorningSummaryDate: Date? = nil,
        aiTimeEstimatesEnabled: Bool = true,
        keepTodaySteady: Bool = true,
        learnFromActualTime: Bool = true,
        estimateHistory: [EstimateRecord] = [],
        eveningCheckInEnabled: Bool = true,
        lastEveningCheckInDate: Date? = nil
    ) {
        self.workStartHour = workStartHour
        self.workStartMinute = workStartMinute
        self.workEndHour = workEndHour
        self.workEndMinute = workEndMinute
        self.defaultSessionMinutes = defaultSessionMinutes
        self.minSessionMinutes = minSessionMinutes
        self.breakMinutes = breakMinutes
        self.lunchStartHour = lunchStartHour
        self.lunchDurationMinutes = lunchDurationMinutes
        self.weekdayWorkingHours = weekdayWorkingHours
        self.maxDailyWorkMinutes = maxDailyWorkMinutes
        self.deadlineBufferMinutes = deadlineBufferMinutes
        self.dateOnlyDeadlinePolicy = dateOnlyDeadlinePolicy
        self.includeDemoDataInPlan = includeDemoDataInPlan
        self.isSimulationMode = isSimulationMode
        self.isGmailConnected = isGmailConnected
        self.isAppleCalendarConnected = isAppleCalendarConnected
        self.selectedCalendarIdentifiers = selectedCalendarIdentifiers
        self.allDayEventsBlockTime = allDayEventsBlockTime
        self.publicationCalendarIdentifier = publicationCalendarIdentifier
        self.ollamaModel = ollamaModel
        self.canvasBaseURL = canvasBaseURL
        self.lastCanvasSyncDate = lastCanvasSyncDate
        self.canvasBrowser = canvasBrowser
        self.gradescopeBrowser = gradescopeBrowser
        self.lastGradescopeSyncDate = lastGradescopeSyncDate
        self.ollamaBaseURL = ollamaBaseURL
        self.timeZoneIdentifier = timeZoneIdentifier
        self.quickCaptureShortcut = quickCaptureShortcut
        self.quickCaptureRetainSource = quickCaptureRetainSource
        self.autoSyncEnabled = autoSyncEnabled
        self.lastFullSyncDate = lastFullSyncDate
        self.morningSummaryEnabled = morningSummaryEnabled
        self.lastMorningSummaryDate = lastMorningSummaryDate
        self.aiTimeEstimatesEnabled = aiTimeEstimatesEnabled
        self.keepTodaySteady = keepTodaySteady
        self.learnFromActualTime = learnFromActualTime
        self.estimateHistory = estimateHistory
        self.eveningCheckInEnabled = eveningCheckInEnabled
        self.lastEveningCheckInDate = lastEveningCheckInDate
    }
    
    public func workingHours(for weekday: Int) -> WeekdayHours {
        if let custom = weekdayWorkingHours[weekday] {
            return custom
        }
        let isWorkday = (weekday >= 2 && weekday <= 6)
        return WeekdayHours(
            isWorkday: isWorkday,
            startHour: workStartHour,
            startMinute: workStartMinute,
            endHour: workEndHour,
            endMinute: workEndMinute
        )
    }
    
    enum CodingKeys: String, CodingKey {
        case workStartHour, workStartMinute, workEndHour, workEndMinute
        case defaultSessionMinutes, minSessionMinutes, breakMinutes, lunchStartHour, lunchDurationMinutes
        case weekdayWorkingHours, maxDailyWorkMinutes, deadlineBufferMinutes, dateOnlyDeadlinePolicy, includeDemoDataInPlan
        case isSimulationMode, isGmailConnected, isAppleCalendarConnected
        case selectedCalendarIdentifiers, allDayEventsBlockTime, publicationCalendarIdentifier
        case ollamaModel, ollamaBaseURL
        case canvasBaseURL, lastCanvasSyncDate, canvasBrowser
        case gradescopeBrowser, lastGradescopeSyncDate
        case legacyOllamaEmailModel = "ollamaEmailModel"
        case timeZoneIdentifier
        case quickCaptureShortcut, quickCaptureRetainSource
        case autoSyncEnabled, lastFullSyncDate
        case morningSummaryEnabled, lastMorningSummaryDate, aiTimeEstimatesEnabled
        case keepTodaySteady, learnFromActualTime, estimateHistory, eveningCheckInEnabled, lastEveningCheckInDate
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let wStartH = try container.decodeIfPresent(Int.self, forKey: .workStartHour) ?? 9
        let wStartM = try container.decodeIfPresent(Int.self, forKey: .workStartMinute) ?? 0
        let wEndH = try container.decodeIfPresent(Int.self, forKey: .workEndHour) ?? 17
        let wEndM = try container.decodeIfPresent(Int.self, forKey: .workEndMinute) ?? 0
        
        self.workStartHour = wStartH
        self.workStartMinute = wStartM
        self.workEndHour = wEndH
        self.workEndMinute = wEndM
        self.defaultSessionMinutes = try container.decodeIfPresent(Int.self, forKey: .defaultSessionMinutes) ?? 45
        self.minSessionMinutes = try container.decodeIfPresent(Int.self, forKey: .minSessionMinutes) ?? 25
        self.breakMinutes = try container.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 15
        self.lunchStartHour = try container.decodeIfPresent(Int.self, forKey: .lunchStartHour) ?? 12
        self.lunchDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .lunchDurationMinutes) ?? 60
        
        // Decode weekday working hours, fallback to default schedule aligned with workStartHour/workEndHour
        if let decodedSchedule = try container.decodeIfPresent([Int: WeekdayHours].self, forKey: .weekdayWorkingHours) {
            self.weekdayWorkingHours = decodedSchedule
        } else {
            var schedule = WeekdayHours.defaultSchedule
            for day in 2...6 {
                schedule[day] = WeekdayHours(isWorkday: true, startHour: wStartH, startMinute: wStartM, endHour: wEndH, endMinute: wEndM)
            }
            self.weekdayWorkingHours = schedule
        }
        
        self.maxDailyWorkMinutes = try container.decodeIfPresent(Int.self, forKey: .maxDailyWorkMinutes) ?? 360
        self.deadlineBufferMinutes = try container.decodeIfPresent(Int.self, forKey: .deadlineBufferMinutes) ?? 60
        self.dateOnlyDeadlinePolicy = try container.decodeIfPresent(DateOnlyDeadlinePolicy.self, forKey: .dateOnlyDeadlinePolicy) ?? .endOfWorkday
        self.includeDemoDataInPlan = try container.decodeIfPresent(Bool.self, forKey: .includeDemoDataInPlan) ?? false
        
        self.isSimulationMode = try container.decodeIfPresent(Bool.self, forKey: .isSimulationMode) ?? true
        self.isGmailConnected = try container.decodeIfPresent(Bool.self, forKey: .isGmailConnected) ?? false
        self.isAppleCalendarConnected = try container.decodeIfPresent(Bool.self, forKey: .isAppleCalendarConnected) ?? true
        self.selectedCalendarIdentifiers = try container.decodeIfPresent([String].self, forKey: .selectedCalendarIdentifiers) ?? []
        self.allDayEventsBlockTime = try container.decodeIfPresent(Bool.self, forKey: .allDayEventsBlockTime) ?? false
        self.publicationCalendarIdentifier = try container.decodeIfPresent(String.self, forKey: .publicationCalendarIdentifier)
        
        let storedModel = try container.decodeIfPresent(String.self, forKey: .ollamaModel)
        let legacyModel = try container.decodeIfPresent(String.self, forKey: .legacyOllamaEmailModel)
        let ollama = storedModel ?? legacyModel ?? ""
        self.ollamaModel = ollama.isEmpty ? OllamaDefaults.model : ollama
        self.ollamaBaseURL = try container.decodeIfPresent(String.self, forKey: .ollamaBaseURL) ?? OllamaDefaults.baseURL
        self.canvasBaseURL = try container.decodeIfPresent(String.self, forKey: .canvasBaseURL) ?? ""
        self.lastCanvasSyncDate = try container.decodeIfPresent(Date.self, forKey: .lastCanvasSyncDate)
        self.canvasBrowser = try? container.decodeIfPresent(CanvasBrowser.self, forKey: .canvasBrowser)
        self.gradescopeBrowser = try? container.decodeIfPresent(CanvasBrowser.self, forKey: .gradescopeBrowser)
        self.lastGradescopeSyncDate = try container.decodeIfPresent(Date.self, forKey: .lastGradescopeSyncDate)
        self.timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier) ?? TimeZone.current.identifier
        self.quickCaptureShortcut = try container.decodeIfPresent(String.self, forKey: .quickCaptureShortcut) ?? "Command+Shift+C"
        self.quickCaptureRetainSource = try container.decodeIfPresent(Bool.self, forKey: .quickCaptureRetainSource) ?? false
        self.autoSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSyncEnabled) ?? true
        self.lastFullSyncDate = try container.decodeIfPresent(Date.self, forKey: .lastFullSyncDate)
        self.morningSummaryEnabled = try container.decodeIfPresent(Bool.self, forKey: .morningSummaryEnabled) ?? true
        self.lastMorningSummaryDate = try container.decodeIfPresent(Date.self, forKey: .lastMorningSummaryDate)
        self.aiTimeEstimatesEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiTimeEstimatesEnabled) ?? true
        self.keepTodaySteady = try container.decodeIfPresent(Bool.self, forKey: .keepTodaySteady) ?? true
        self.learnFromActualTime = try container.decodeIfPresent(Bool.self, forKey: .learnFromActualTime) ?? true
        self.estimateHistory = (try? container.decodeIfPresent([EstimateRecord].self, forKey: .estimateHistory)) ?? []
        self.eveningCheckInEnabled = try container.decodeIfPresent(Bool.self, forKey: .eveningCheckInEnabled) ?? true
        self.lastEveningCheckInDate = try container.decodeIfPresent(Date.self, forKey: .lastEveningCheckInDate)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workStartHour, forKey: .workStartHour)
        try container.encode(workStartMinute, forKey: .workStartMinute)
        try container.encode(workEndHour, forKey: .workEndHour)
        try container.encode(workEndMinute, forKey: .workEndMinute)
        try container.encode(defaultSessionMinutes, forKey: .defaultSessionMinutes)
        try container.encode(minSessionMinutes, forKey: .minSessionMinutes)
        try container.encode(breakMinutes, forKey: .breakMinutes)
        try container.encode(lunchStartHour, forKey: .lunchStartHour)
        try container.encode(lunchDurationMinutes, forKey: .lunchDurationMinutes)
        try container.encode(weekdayWorkingHours, forKey: .weekdayWorkingHours)
        try container.encode(maxDailyWorkMinutes, forKey: .maxDailyWorkMinutes)
        try container.encode(deadlineBufferMinutes, forKey: .deadlineBufferMinutes)
        try container.encode(dateOnlyDeadlinePolicy, forKey: .dateOnlyDeadlinePolicy)
        try container.encode(includeDemoDataInPlan, forKey: .includeDemoDataInPlan)
        try container.encode(isSimulationMode, forKey: .isSimulationMode)
        try container.encode(isGmailConnected, forKey: .isGmailConnected)
        try container.encode(isAppleCalendarConnected, forKey: .isAppleCalendarConnected)
        try container.encode(selectedCalendarIdentifiers, forKey: .selectedCalendarIdentifiers)
        try container.encode(allDayEventsBlockTime, forKey: .allDayEventsBlockTime)
        try container.encode(publicationCalendarIdentifier, forKey: .publicationCalendarIdentifier)
        try container.encode(ollamaModel, forKey: .ollamaModel)
        try container.encode(canvasBaseURL, forKey: .canvasBaseURL)
        try container.encodeIfPresent(lastCanvasSyncDate, forKey: .lastCanvasSyncDate)
        try container.encodeIfPresent(canvasBrowser, forKey: .canvasBrowser)
        try container.encodeIfPresent(gradescopeBrowser, forKey: .gradescopeBrowser)
        try container.encodeIfPresent(lastGradescopeSyncDate, forKey: .lastGradescopeSyncDate)
        try container.encode(ollamaBaseURL, forKey: .ollamaBaseURL)
        try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try container.encode(quickCaptureShortcut, forKey: .quickCaptureShortcut)
        try container.encode(quickCaptureRetainSource, forKey: .quickCaptureRetainSource)
        try container.encode(autoSyncEnabled, forKey: .autoSyncEnabled)
        try container.encodeIfPresent(lastFullSyncDate, forKey: .lastFullSyncDate)
        try container.encode(morningSummaryEnabled, forKey: .morningSummaryEnabled)
        try container.encodeIfPresent(lastMorningSummaryDate, forKey: .lastMorningSummaryDate)
        try container.encode(aiTimeEstimatesEnabled, forKey: .aiTimeEstimatesEnabled)
        try container.encode(keepTodaySteady, forKey: .keepTodaySteady)
        try container.encode(learnFromActualTime, forKey: .learnFromActualTime)
        try container.encode(estimateHistory, forKey: .estimateHistory)
        try container.encode(eveningCheckInEnabled, forKey: .eveningCheckInEnabled)
        try container.encodeIfPresent(lastEveningCheckInDate, forKey: .lastEveningCheckInDate)
    }
}
