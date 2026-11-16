import Foundation

public enum TimelineItemKind: Equatable {
    case commitment(CalendarCommitment)
    case workSession(WorkSession)
    
    public var isCommitment: Bool {
        if case .commitment = self { return true }
        return false
    }
    
    public var isWorkSession: Bool {
        if case .workSession = self { return true }
        return false
    }
}

public struct UnifiedTimelineItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let startTime: Date
    public let endTime: Date
    public let kind: TimelineItemKind
    public var overlappingTitles: [String] = []
    
    public var isOverlapping: Bool {
        !overlappingTitles.isEmpty
    }
    
    public var isCommitment: Bool {
        kind.isCommitment
    }
    
    public var isWorkSession: Bool {
        kind.isWorkSession
    }
    
    public var commitment: CalendarCommitment? {
        if case .commitment(let c) = kind { return c }
        return nil
    }
    
    public var workSession: WorkSession? {
        if case .workSession(let s) = kind { return s }
        return nil
    }
    
    public var isCarryover: Bool {
        workSession?.isCarryover ?? false
    }
}

public struct TimelineDayData: Equatable {
    public let day: Date
    public let deadlines: [DiscoveredTask]
    public let allDayCommitments: [CalendarCommitment]
    public let timedItems: [UnifiedTimelineItem]
}

public enum UnifiedTimelineEngine {
    /// Builds sorted deadlines, all-day events, and combined timed timeline items for a given day.
    public static func buildDayData(
        day: Date,
        tasks: [DiscoveredTask],
        workSessions: [WorkSession],
        commitments: [CalendarCommitment],
        timeZone: TimeZone = .current
    ) -> TimelineDayData {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        
        let startOfDay = cal.startOfDay(for: day)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else {
            return TimelineDayData(day: day, deadlines: [], allDayCommitments: [], timedItems: [])
        }
        
        // 1. Deadlines due on this day, sorted strictly by due time
        let dayDeadlines = tasks.filter { task in
            guard !task.isDismissed else { return false }
            guard let dl = task.effectiveDeadline ?? task.extractedDeadline else { return false }
            return cal.isDate(dl, inSameDayAs: day)
        }.sorted { t1, t2 in
            let d1 = t1.effectiveDeadline ?? t1.extractedDeadline ?? Date.distantFuture
            let d2 = t2.effectiveDeadline ?? t2.extractedDeadline ?? Date.distantFuture
            if d1 != d2 {
                return d1 < d2
            }
            return t1.id.uuidString < t2.id.uuidString
        }
        
        // 2. Work sessions for this day
        let daySessions = workSessions.filter { s in
            s.status != .skipped && cal.isDate(s.startTime, inSameDayAs: day)
        }
        
        // 3. Apple Calendar commitments touching this day
        let rawCommitments = commitments.filter { c in
            c.startTime < endOfDay && c.endTime > startOfDay
        }
        
        // Deduplicate published work sessions so they are never shown twice
        let publishedSessions = daySessions.filter { $0.isPublished }
        let publishedEventIds = Set(publishedSessions.compactMap { $0.calendarEventId })
        
        let dedupedCommitments = rawCommitments.filter { c in
            // Check by external event ID
            if let extId = c.externalEventId, publishedEventIds.contains(extId) {
                return false
            }
            // Check if flagged as planner's own event matching a published session
            if c.isPlannerOwnEvent {
                if publishedSessions.contains(where: {
                    ($0.calendarEventId != nil && $0.calendarEventId == c.externalEventId) ||
                    ($0.title.lowercased() == c.title.lowercased() && abs($0.startTime.timeIntervalSince(c.startTime)) < 60)
                }) {
                    return false
                }
            }
            // Check matching title and start/end time with published session
            if publishedSessions.contains(where: {
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == c.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() &&
                abs($0.startTime.timeIntervalSince(c.startTime)) < 60 &&
                abs($0.endTime.timeIntervalSince(c.endTime)) < 60
            }) {
                return false
            }
            return true
        }
        
        // Segregate all-day commitments
        let allDayCommitments = dedupedCommitments.filter { $0.isAllDay }
        let timedCommitments = dedupedCommitments.filter { !$0.isAllDay }
        
        // 4. Build timed items list
        var timedItems: [UnifiedTimelineItem] = []
        
        for c in timedCommitments {
            timedItems.append(UnifiedTimelineItem(
                id: "c-\(c.id.uuidString)",
                title: c.title,
                startTime: c.startTime,
                endTime: c.endTime,
                kind: .commitment(c),
                overlappingTitles: []
            ))
        }
        
        for s in daySessions {
            timedItems.append(UnifiedTimelineItem(
                id: "s-\(s.id.uuidString)",
                title: s.title,
                startTime: s.startTime,
                endTime: s.endTime,
                kind: .workSession(s),
                overlappingTitles: []
            ))
        }
        
        // 5. Stable sorting:
        //    Primary: startTime
        //    Tie-breaker 1: kind (commitments first, then work sessions)
        //    Tie-breaker 2: endTime
        //    Tie-breaker 3: title
        //    Tie-breaker 4: id
        timedItems.sort { a, b in
            if a.startTime != b.startTime {
                return a.startTime < b.startTime
            }
            let aRank = a.isCommitment ? 0 : 1
            let bRank = b.isCommitment ? 0 : 1
            if aRank != bRank {
                return aRank < bRank
            }
            if a.endTime != b.endTime {
                return a.endTime < b.endTime
            }
            if a.title != b.title {
                return a.title < b.title
            }
            return a.id < b.id
        }
        
        // 6. Overlap detection
        let timeFormatter = DateFormatter()
        timeFormatter.timeZone = timeZone
        timeFormatter.timeStyle = .short
        
        for i in 0..<timedItems.count {
            let startI = timedItems[i].startTime
            let endI = timedItems[i].endTime
            
            for j in 0..<timedItems.count where i != j {
                let startJ = timedItems[j].startTime
                let endJ = timedItems[j].endTime
                
                // Interval overlap: max(startI, startJ) < min(endI, endJ)
                if max(startI, startJ) < min(endI, endJ) {
                    let otherTitle = timedItems[j].title
                    let timeStr = "\(timeFormatter.string(from: startJ))–\(timeFormatter.string(from: endJ))"
                    timedItems[i].overlappingTitles.append("\(otherTitle) (\(timeStr))")
                }
            }
        }
        
        return TimelineDayData(
            day: day,
            deadlines: dayDeadlines,
            allDayCommitments: allDayCommitments,
            timedItems: timedItems
        )
    }
}
