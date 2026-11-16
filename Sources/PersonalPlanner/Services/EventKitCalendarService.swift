import Foundation
import EventKit
import AppKit

public final class EventKitCalendarService: CalendarServiceProtocol, @unchecked Sendable {
    /// Calendars the app owns: the current name plus the name used before the app was renamed.
    static let plannerCalendarTitles: Set<String> = ["DayBook AI", "Personal Planner"]

    private let eventStore: EKEventStore
    public var onCalendarStoreChanged: (() -> Void)? = nil
    private var observer: NSObjectProtocol?
    
    public init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
        
        // Listen for system Apple Calendar changes
        self.observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onCalendarStoreChanged?()
        }
    }
    
    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    public var authorizationStatus: CalendarAuthorizationStatus {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized, .fullAccess:
            return .authorized
        case .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
    }
    
    public func requestAccess() async throws -> Bool {
        if #available(macOS 14.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                return granted
            } catch {
                return false
            }
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }
    
    public func fetchAvailableCalendars() async throws -> [CalendarAccountInfo] {
        guard authorizationStatus == .authorized else { return [] }
        
        let calendars = eventStore.calendars(for: .event)
        return calendars.map { cal in
            var colorHex = "#0A84FF"
            if let cgColor = cal.cgColor, let nsColor = NSColor(cgColor: cgColor) {
                colorHex = nsColor.toHexString()
            }
            let sourceTitle = cal.source?.title ?? "Local"
            return CalendarAccountInfo(
                id: cal.calendarIdentifier,
                title: cal.title,
                sourceTitle: sourceTitle,
                colorHex: colorHex,
                allowsModifications: cal.allowsContentModifications
            )
        }.sorted {
            if $0.sourceTitle != $1.sourceTitle {
                return $0.sourceTitle < $1.sourceTitle
            }
            return $0.title < $1.title
        }
    }
    
    public func fetchCommitments(
        for dateRange: ClosedRange<Date>,
        selectedCalendarIdentifiers: Set<String>?,
        allDayBlocksTime: Bool
    ) async throws -> [CalendarCommitment] {
        guard authorizationStatus == .authorized else { return [] }
        
        let allCalendars = eventStore.calendars(for: .event)
        let targetCalendars: [EKCalendar]
        if let selected = selectedCalendarIdentifiers, !selected.isEmpty {
            targetCalendars = allCalendars.filter { selected.contains($0.calendarIdentifier) }
        } else {
            targetCalendars = allCalendars
        }
        
        let predicate = eventStore.predicateForEvents(
            withStart: dateRange.lowerBound,
            end: dateRange.upperBound,
            calendars: targetCalendars
        )
        
        let events = eventStore.events(matching: predicate)
        
        return events.map { event in
            let isAllDay = event.isAllDay
            let isFree = (event.availability == .free)
            let isBusy = !isFree
            
            var colorHex = "#0A84FF"
            if let cgColor = event.calendar.cgColor, let nsColor = NSColor(cgColor: cgColor) {
                colorHex = nsColor.toHexString()
            }
            
            let eventTitle = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let isPlannerOwn = (Self.plannerCalendarTitles.contains(event.calendar.title) || (event.notes?.contains("[PersonalPlanner Session]") == true))
            
            return CalendarCommitment(
                id: UUID(),
                title: eventTitle.isEmpty ? "Untitled Event" : eventTitle,
                location: event.location,
                startTime: event.startDate,
                endTime: event.endDate,
                isAllDay: isAllDay,
                isBusy: isBusy,
                calendarName: event.calendar.title,
                calendarIdentifier: event.calendar.calendarIdentifier,
                colorHex: colorHex,
                isSimulatedDemo: false,
                externalEventId: event.eventIdentifier,
                isPlannerOwnEvent: isPlannerOwn
            )
        }.sorted { $0.startTime.timeIntervalSinceReferenceDate < $1.startTime.timeIntervalSinceReferenceDate }
    }
    
    // MARK: - Dedicated Writable Planner Calendar
    
    public func getOrCreatePlannerCalendar() async throws -> CalendarAccountInfo {
        guard authorizationStatus == .authorized else {
            throw NSError(domain: "PersonalPlanner.EventKit", code: 401, userInfo: [NSLocalizedDescriptionKey: "Calendar access is not authorized."])
        }
        
        let calendars = eventStore.calendars(for: .event)
        // Reuse a calendar from before the rename ("Personal Planner") so sessions aren't split across two calendars.
        let writable = calendars.filter { $0.allowsContentModifications }
        if let existing = writable.first(where: { $0.title == "DayBook AI" }) ?? writable.first(where: { $0.title == "Personal Planner" }) {
            var colorHex = "#BF5AF2"
            if let cg = existing.cgColor, let ns = NSColor(cgColor: cg) {
                colorHex = ns.toHexString()
            }
            return CalendarAccountInfo(
                id: existing.calendarIdentifier,
                title: existing.title,
                sourceTitle: existing.source?.title ?? "Local",
                colorHex: colorHex,
                allowsModifications: true
            )
        }
        
        // Try each account in order of preference. Some accounts (often Google or Exchange added via
        // Internet Accounts) don't let apps add calendars, so a failure on one must not stop the others.
        let candidates = Self.orderedSourcesForNewCalendar(eventStore.sources, defaultSource: eventStore.defaultCalendarForNewEvents?.source)
        guard !candidates.isEmpty else {
            throw NSError(domain: "PersonalPlanner.EventKit", code: 500, userInfo: [NSLocalizedDescriptionKey: "No calendar account on this Mac can hold a new calendar. Pick an existing calendar in Settings instead."])
        }
        
        // Identifiers, not objects: reset() after a failed save invalidates previously fetched sources.
        let candidateIds = candidates.map { ($0.sourceIdentifier, $0.title) }
        var refusedAccounts: [String] = []
        for (sourceId, sourceTitle) in candidateIds {
            guard let source = eventStore.source(withIdentifier: sourceId) else {
                refusedAccounts.append(sourceTitle)
                continue
            }
            let newCalendar = EKCalendar(for: .event, eventStore: eventStore)
            newCalendar.title = "DayBook AI"
            newCalendar.source = source
            newCalendar.cgColor = NSColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 1.0).cgColor
            do {
                try eventStore.saveCalendar(newCalendar, commit: true)
                return CalendarAccountInfo(
                    id: newCalendar.calendarIdentifier,
                    title: newCalendar.title,
                    sourceTitle: source.title,
                    colorHex: "#BF5AF2",
                    allowsModifications: true
                )
            } catch {
                eventStore.reset() // drop the rejected calendar so it isn't retried on the next commit
                refusedAccounts.append(sourceTitle)
            }
        }
        
        throw NSError(domain: "PersonalPlanner.EventKit", code: 403, userInfo: [NSLocalizedDescriptionKey: "None of your calendar accounts (\(refusedAccounts.joined(separator: ", "))) allow DayBook AI to add a calendar. Create a calendar named \"DayBook AI\" in the Calendar app (File → New Calendar), or pick an existing calendar from the menu in Settings."])
    }
    
    /// iCloud first, then other CalDAV accounts, then "On My Mac", then the default account, then anything else.
    /// Birthdays and subscribed (read-only) accounts are never used.
    static func orderedSourcesForNewCalendar(_ sources: [EKSource], defaultSource: EKSource?) -> [EKSource] {
        func rank(_ source: EKSource) -> Int {
            switch source.sourceType {
            case .calDAV: return source.title.localizedCaseInsensitiveContains("icloud") ? 0 : 1
            case .local: return 2
            default: return source.sourceIdentifier == defaultSource?.sourceIdentifier ? 3 : 4
            }
        }
        let usable = sources.filter { $0.sourceType != .birthdays && $0.sourceType != .subscribed }
        return usable.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map { $0.element }
    }
    
    // MARK: - Publishing Approved Sessions
    
    public func publishSessions(
        _ sessions: [WorkSession],
        to calendarIdentifier: String,
        taskTitleLookup: [UUID: String]
    ) async throws -> PublishBatchResult {
        guard authorizationStatus == .authorized else {
            throw NSError(domain: "PersonalPlanner.EventKit", code: 401, userInfo: [NSLocalizedDescriptionKey: "Calendar access is not authorized."])
        }
        
        guard let calendar = eventStore.calendar(withIdentifier: calendarIdentifier) else {
            throw NSError(domain: "PersonalPlanner.EventKit", code: 404, userInfo: [NSLocalizedDescriptionKey: "Destination calendar was not found. It may have been deleted in Apple Calendar."])
        }
        
        guard calendar.allowsContentModifications else {
            throw NSError(domain: "PersonalPlanner.EventKit", code: 403, userInfo: [NSLocalizedDescriptionKey: "Selected calendar '\(calendar.title)' is read-only. Please select or create a writable calendar like 'DayBook AI'."])
        }
        
        var publishedCount = 0
        var updatedCount = 0
        var failedCount = 0
        var successMap: [UUID: String] = [:]
        var errorMap: [UUID: String] = [:]
        
        for session in sessions {
            // Never publish simulated/demo sessions to real Apple Calendar
            if session.isSimulatedDemo { continue }
            
            let taskTitle = session.taskId.flatMap { taskTitleLookup[$0] } ?? session.title
            let notesText = "[PersonalPlanner Session] - Planned focus session for: \(taskTitle)"
            
            if let existingEventId = session.calendarEventId,
               let existingEvent = eventStore.event(withIdentifier: existingEventId) {
                // Update existing event in-place (no duplicates)
                existingEvent.title = session.title
                existingEvent.startDate = session.startTime
                existingEvent.endDate = session.endTime
                existingEvent.calendar = calendar
                existingEvent.notes = notesText
                
                do {
                    try eventStore.save(existingEvent, span: .thisEvent, commit: false)
                    updatedCount += 1
                    successMap[session.id] = existingEvent.eventIdentifier
                } catch {
                    failedCount += 1
                    errorMap[session.id] = error.localizedDescription
                }
            } else {
                // Create new event
                let newEvent = EKEvent(eventStore: eventStore)
                newEvent.calendar = calendar
                newEvent.title = session.title
                newEvent.startDate = session.startTime
                newEvent.endDate = session.endTime
                newEvent.notes = notesText
                
                do {
                    try eventStore.save(newEvent, span: .thisEvent, commit: false)
                    publishedCount += 1
                    successMap[session.id] = newEvent.eventIdentifier
                } catch {
                    failedCount += 1
                    errorMap[session.id] = error.localizedDescription
                }
            }
        }
        
        // Commit changes to EventKit
        do {
            try eventStore.commit()
        } catch {
            throw NSError(domain: "PersonalPlanner.EventKit", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to commit calendar changes: \(error.localizedDescription)"])
        }
        
        return PublishBatchResult(
            publishedCount: publishedCount,
            updatedCount: updatedCount,
            failedCount: failedCount,
            successSessionEventMap: successMap,
            errors: errorMap,
            destinationCalendarId: calendar.calendarIdentifier,
            destinationCalendarName: calendar.title,
            executedDate: Date()
        )
    }
    
    public func deletePublishedEvents(_ eventIdentifiers: [String]) async throws -> [String: Bool] {
        guard authorizationStatus == .authorized else { return [:] }
        var results: [String: Bool] = [:]
        
        for eventId in eventIdentifiers {
            if let event = eventStore.event(withIdentifier: eventId) {
                // Safety: only delete events that belong to Personal Planner or have planner notes
                let isPlannerSession = (Self.plannerCalendarTitles.contains(event.calendar.title) || (event.notes?.contains("[PersonalPlanner Session]") == true))
                if isPlannerSession {
                    do {
                        try eventStore.remove(event, span: .thisEvent, commit: false)
                        results[eventId] = true
                    } catch {
                        results[eventId] = false
                    }
                }
            }
        }
        try? eventStore.commit()
        return results
    }
    
    public func detectExternalDiscrepancies(
        for sessions: [WorkSession],
        targetCalendarIdentifier: String?,
        externalCommitments: [CalendarCommitment]
    ) async throws -> [ExternalDiscrepancy] {
        guard authorizationStatus == .authorized else { return [] }
        var discrepancies: [ExternalDiscrepancy] = []
        
        for session in sessions where session.calendarEventId != nil {
            guard let eventId = session.calendarEventId else { continue }
            
            if let event = eventStore.event(withIdentifier: eventId) {
                // 1. Detect if moved in Apple Calendar. Compare against what the planner last
                //    published, not the current local times: local edits (manual moves, early
                //    completion, same-day advancement) are pending updates, not external moves.
                let publishedStart = session.lastPublishedStartTime ?? session.startTime
                let publishedEnd = session.lastPublishedEndTime ?? session.endTime
                let startDiff = abs(event.startDate.timeIntervalSince(publishedStart))
                let endDiff = abs(event.endDate.timeIntervalSince(publishedEnd))
                
                if startDiff > 60 || endDiff > 60 {
                    discrepancies.append(ExternalDiscrepancy(
                        sessionId: session.id,
                        calendarEventId: eventId,
                        sessionTitle: session.title,
                        kind: .movedInCalendar(newStartTime: event.startDate, newEndTime: event.endDate)
                    ))
                }
                
                // 2. Detect if an external commitment conflicts with this session
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
                // Event missing / deleted directly in Apple Calendar
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

public extension NSColor {
    func toHexString() -> String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "#0A84FF" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
