import Foundation

public final class SimulatedCalendarService: CalendarServiceProtocol {
    public var authorizationStatus: CalendarAuthorizationStatus = .authorized
    public var onCalendarStoreChanged: (() -> Void)? = nil
    
    public struct SimulatedEvent {
        public var id: String
        public var calendarId: String
        public var title: String
        public var startTime: Date
        public var endTime: Date
        public var notes: String
    }
    
    public var simulatedEvents: [String: SimulatedEvent] = [:]
    public var failNextPublicationForSessionId: UUID? = nil
    
    public init() {}
    
    public func requestAccess() async throws -> Bool {
        return true
    }
    
    public func fetchAvailableCalendars() async throws -> [CalendarAccountInfo] {
        return [
            CalendarAccountInfo(id: "demo-cal-work", title: "Work Calendar", sourceTitle: "Demonstration", colorHex: "#0A84FF", allowsModifications: true),
            CalendarAccountInfo(id: "demo-cal-personal", title: "Personal Calendar", sourceTitle: "Demonstration", colorHex: "#30D158", allowsModifications: true),
            CalendarAccountInfo(id: "demo-cal-uni", title: "University Calendar", sourceTitle: "Demonstration", colorHex: "#BF5AF2", allowsModifications: true),
            CalendarAccountInfo(id: "sim-cal-planner", title: "DayBook AI", sourceTitle: "On My Mac", colorHex: "#BF5AF2", allowsModifications: true)
        ]
    }
    
    public func fetchCommitments(
        for dateRange: ClosedRange<Date>,
        selectedCalendarIdentifiers: Set<String>?,
        allDayBlocksTime: Bool
    ) async throws -> [CalendarCommitment] {
        try? await Task.sleep(nanoseconds: 20_000_000)
        
        let all = DemoDataFactory.makeCalendarCommitments()
        var results = all.compactMap { commitment -> CalendarCommitment? in
            guard commitment.endTime.timeIntervalSinceReferenceDate >= dateRange.lowerBound.timeIntervalSinceReferenceDate && commitment.startTime.timeIntervalSinceReferenceDate <= dateRange.upperBound.timeIntervalSinceReferenceDate else {
                return nil
            }
            
            let calId: String
            switch commitment.calendarName {
            case "Work Calendar": calId = "demo-cal-work"
            case "Personal Calendar": calId = "demo-cal-personal"
            case "University Calendar": calId = "demo-cal-uni"
            default: calId = "demo-cal-work"
            }
            
            if let selected = selectedCalendarIdentifiers, !selected.isEmpty, !selected.contains(calId) {
                return nil
            }
            
            var c = commitment
            c.calendarIdentifier = calId
            c.isSimulatedDemo = true
            c.isPlannerOwnEvent = false
            return c
        }
        
        // Include published simulated sessions if "sim-cal-planner" is selected (or no selection filter)
        for (_, event) in simulatedEvents {
            if let selected = selectedCalendarIdentifiers, !selected.isEmpty, !selected.contains(event.calendarId) {
                continue
            }
            guard event.endTime.timeIntervalSinceReferenceDate >= dateRange.lowerBound.timeIntervalSinceReferenceDate && event.startTime.timeIntervalSinceReferenceDate <= dateRange.upperBound.timeIntervalSinceReferenceDate else {
                continue
            }
            results.append(CalendarCommitment(
                id: UUID(),
                title: event.title,
                location: nil,
                startTime: event.startTime,
                endTime: event.endTime,
                isAllDay: false,
                isBusy: true,
                calendarName: "DayBook AI",
                calendarIdentifier: event.calendarId,
                colorHex: "#BF5AF2",
                isSimulatedDemo: false,
                externalEventId: event.id,
                isPlannerOwnEvent: true
            ))
        }
        
        return results.sorted { $0.startTime.timeIntervalSinceReferenceDate < $1.startTime.timeIntervalSinceReferenceDate }
    }
    
    // MARK: - Dedicated Writable Planner Calendar
    
    public func getOrCreatePlannerCalendar() async throws -> CalendarAccountInfo {
        return CalendarAccountInfo(
            id: "sim-cal-planner",
            title: "DayBook AI",
            sourceTitle: "On My Mac",
            colorHex: "#BF5AF2",
            allowsModifications: true
        )
    }
    
    // MARK: - Publishing Approved Sessions
    
    public func publishSessions(
        _ sessions: [WorkSession],
        to calendarIdentifier: String,
        taskTitleLookup: [UUID: String]
    ) async throws -> PublishBatchResult {
        var publishedCount = 0
        var updatedCount = 0
        var failedCount = 0
        var successMap: [UUID: String] = [:]
        var errorMap: [UUID: String] = [:]
        
        for session in sessions {
            // Simulated partial failure hook for automated testing
            if let failId = failNextPublicationForSessionId, failId == session.id {
                failedCount += 1
                errorMap[session.id] = "Simulated temporary calendar write error"
                continue
            }
            
            let taskTitle = session.taskId.flatMap { taskTitleLookup[$0] } ?? session.title
            let notesText = "[PersonalPlanner Session] - Planned focus session for: \(taskTitle)"
            
            if let eventId = session.calendarEventId, var existing = simulatedEvents[eventId] {
                // Update existing event in-place
                existing.title = session.title
                existing.startTime = session.startTime
                existing.endTime = session.endTime
                existing.notes = notesText
                simulatedEvents[eventId] = existing
                updatedCount += 1
                successMap[session.id] = eventId
            } else {
                // Create new event
                let newEventId = "sim-evt-\(UUID().uuidString)"
                let newEvent = SimulatedEvent(
                    id: newEventId,
                    calendarId: calendarIdentifier,
                    title: session.title,
                    startTime: session.startTime,
                    endTime: session.endTime,
                    notes: notesText
                )
                simulatedEvents[newEventId] = newEvent
                publishedCount += 1
                successMap[session.id] = newEventId
            }
        }
        
        return PublishBatchResult(
            publishedCount: publishedCount,
            updatedCount: updatedCount,
            failedCount: failedCount,
            successSessionEventMap: successMap,
            errors: errorMap,
            destinationCalendarId: calendarIdentifier,
            destinationCalendarName: "DayBook AI",
            executedDate: Date()
        )
    }
    
    public func deletePublishedEvents(_ eventIdentifiers: [String]) async throws -> [String: Bool] {
        var results: [String: Bool] = [:]
        for id in eventIdentifiers {
            if simulatedEvents.removeValue(forKey: id) != nil {
                results[id] = true
            } else {
                results[id] = false
            }
        }
        return results
    }
    
    public func detectExternalDiscrepancies(
        for sessions: [WorkSession],
        targetCalendarIdentifier: String?,
        externalCommitments: [CalendarCommitment]
    ) async throws -> [ExternalDiscrepancy] {
        var discrepancies: [ExternalDiscrepancy] = []
        
        for session in sessions where session.calendarEventId != nil {
            guard let eventId = session.calendarEventId else { continue }
            
            if let event = simulatedEvents[eventId] {
                let startDiff = abs(event.startTime.timeIntervalSince(session.lastPublishedStartTime ?? session.startTime))
                let endDiff = abs(event.endTime.timeIntervalSince(session.lastPublishedEndTime ?? session.endTime))
                
                if startDiff > 60 || endDiff > 60 {
                    discrepancies.append(ExternalDiscrepancy(
                        sessionId: session.id,
                        calendarEventId: eventId,
                        sessionTitle: session.title,
                        kind: .movedInCalendar(newStartTime: event.startTime, newEndTime: event.endTime)
                    ))
                }
                
                let conflict = externalCommitments.first { c in
                    !c.isPlannerOwnEvent && c.isBusy && !c.isAllDay &&
                    c.startTime.timeIntervalSinceReferenceDate < session.endTime.timeIntervalSinceReferenceDate && c.endTime.timeIntervalSinceReferenceDate > session.startTime.timeIntervalSinceReferenceDate
                }
                if let conflict = conflict {
                    discrepancies.append(ExternalDiscrepancy(
                        sessionId: session.id,
                        calendarEventId: eventId,
                        sessionTitle: session.title,
                        kind: .externalConflict(conflictingTitle: conflict.title, conflictStart: conflict.startTime, conflictEnd: conflict.endTime)
                    ))
                }
            } else {
                discrepancies.append(ExternalDiscrepancy(
                    sessionId: session.id,
                    calendarEventId: eventId,
                    sessionTitle: session.title,
                    kind: .deletedInCalendar
                ))
            }
        }
        
        return discrepancies
    }
}
