import Foundation

public struct DemoDataFactory {
    
    public static func makeDate(daysFromNow: Int = 0, hour: Int, minute: Int) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let targetDay = cal.date(byAdding: .day, value: daysFromNow, to: today) else {
            return Date()
        }
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: targetDay) ?? targetDay
    }
    
    public static func makeSampleEmails() -> [EmailSource] {
        let cal = Calendar.current
        let now = Date()
        let twoHoursAgo = cal.date(byAdding: .hour, value: -2, to: now) ?? now
        let fiveHoursAgo = cal.date(byAdding: .hour, value: -5, to: now) ?? now
        let yesterday = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: now) ?? now
        
        // 1. Clear Assignment
        let email1 = EmailSource(
            id: "msg-clear-001",
            threadId: "thread-cs420-lab3",
            senderName: "Prof. Elena Vance",
            senderEmail: "evance@university.edu",
            subject: "CS 420: Distributed Systems Lab 3 - Raft Consensus Algorithm",
            receivedDate: twoDaysAgo,
            snippet: "Lab 3 on Raft Consensus is now released. Submission deadline is Friday at 11:59 PM. Estimated effort: 3-4 hours.",
            fullBody: """
            Hello class,
            
            Lab 3 on the Raft Consensus Algorithm is now officially released.
            
            Requirements:
            1. Implement leader election with randomized election timeouts.
            2. Implement heartbeat mechanism and AppendEntries RPC.
            3. Implement basic log replication and committed entry execution.
            
            Submission Deadline: This Friday at 11:59 PM.
            Estimated effort: 3 hours (180 minutes).
            
            Late submissions will incur a 10% penalty per day. The grading harness is available in the starter repository.
            
            Best regards,
            Prof. Elena Vance
            Department of Computer Science
            """,
            category: .assignment,
            isSimulatedDemo: true
        )
        
        // 2. Ambiguous Request
        let email2 = EmailSource(
            id: "msg-ambig-002",
            threadId: "thread-deck-feedback",
            senderName: "Alex Rivera",
            senderEmail: "alex.rivera@innovatetech.io",
            subject: "Quick feedback on slide 8 architecture diagram",
            receivedDate: yesterday,
            snippet: "Whenever you get some breathing room this week or next, could you take a quick pass at slide 8? See what you think.",
            fullBody: """
            Hey there,
            
            Whenever you get some breathing room this week or next, could you take a quick pass at the architecture diagram on slide 8 of the Q4 pitch deck?
            
            The client mentioned wanting to see cloud redundancy highlighted, but I'm not sure if we should do a full diagram overhaul or just add a few callouts and badges.
            
            Take a look whenever you can, let me know what you think, and we can figure out next steps.
            
            Thanks!
            Alex Rivera
            Product Lead, InnovateTech
            """,
            category: .ambiguous,
            isSimulatedDemo: true
        )
        
        // 3. Newsletter (Informational - Filtered out)
        let email3 = EmailSource(
            id: "msg-news-003",
            threadId: "thread-swift-weekly-312",
            senderName: "Swift Weekly Curators",
            senderEmail: "dispatch@swiftweekly.org",
            subject: "Swift Weekly #312: SwiftUI Desktop Patterns & Swift 6 Concurrency",
            receivedDate: fiveHoursAgo,
            snippet: "In this issue: Building multi-window macOS apps, strict concurrency tips in Swift 6, and open source updates.",
            fullBody: """
            Swift Weekly — Issue #312
            
            Welcome to this week's roundup of Swift and macOS engineering:
            
            * SwiftUI Desktop Architecture: Best practices for split views, toolbars, and inspector panels on macOS Sequoia.
            * Swift 6 Concurrency in Depth: Migrating legacy completion handlers to async/await and actor isolation.
            * Tool Spotlight: Native Keychain wrappers and EventKit integration patterns.
            
            Enjoy reading!
            Sent with care by the Swift Weekly editorial team.
            Click here to manage your email preferences or unsubscribe.
            """,
            category: .newsletter,
            isSimulatedDemo: true
        )
        
        // 4. Deadline Change Update
        let email4 = EmailSource(
            id: "msg-update-004",
            threadId: "thread-cs420-lab3",
            senderName: "Prof. Elena Vance",
            senderEmail: "evance@university.edu",
            subject: "UPDATE: CS 420 Lab 3 Deadline Extended to Sunday",
            receivedDate: twoHoursAgo,
            snippet: "Due to campus cluster maintenance on Thursday evening, I am extending the deadline for CS 420 Lab 3 to Sunday at 11:59 PM.",
            fullBody: """
            Hi students,
            
            Due to scheduled campus cluster maintenance on Thursday evening from 6 PM to 10 PM, the test runner server will be temporarily offline.
            
            To ensure everyone has sufficient testing time, I am extending the submission deadline for CS 420 Lab 3 by 48 hours:
            
            New Deadline: This Sunday at 11:59 PM (extended from Friday).
            
            Office hours remain scheduled as normal.
            
            Best,
            Prof. Elena Vance
            """,
            category: .deadlineChange,
            isSimulatedDemo: true
        )
        
        return [email1, email2, email3, email4]
    }
    
    public static func makeCalendarCommitments() -> [CalendarCommitment] {
        return [
            // Today Commitments
            CalendarCommitment(
                title: "Team Weekly Standup",
                location: "Conference Room B / Zoom",
                startTime: makeDate(daysFromNow: 0, hour: 10, minute: 0),
                endTime: makeDate(daysFromNow: 0, hour: 11, minute: 0),
                calendarName: "Work Calendar",
                colorHex: "#0A84FF",
                isSimulatedDemo: true
            ),
            CalendarCommitment(
                title: "Lunch Break",
                location: "Campus Cafe",
                startTime: makeDate(daysFromNow: 0, hour: 12, minute: 0),
                endTime: makeDate(daysFromNow: 0, hour: 13, minute: 0),
                calendarName: "Personal Calendar",
                colorHex: "#30D158",
                isSimulatedDemo: true
            ),
            CalendarCommitment(
                title: "CS 420 Discussion Section",
                location: "Turing Hall 204",
                startTime: makeDate(daysFromNow: 0, hour: 14, minute: 30),
                endTime: makeDate(daysFromNow: 0, hour: 15, minute: 30),
                calendarName: "University Calendar",
                colorHex: "#BF5AF2",
                isSimulatedDemo: true
            ),
            CalendarCommitment(
                title: "1-on-1 with Tech Mentor",
                location: "Virtual Meeting",
                startTime: makeDate(daysFromNow: 0, hour: 16, minute: 30),
                endTime: makeDate(daysFromNow: 0, hour: 17, minute: 0),
                calendarName: "Work Calendar",
                colorHex: "#0A84FF",
                isSimulatedDemo: true
            ),
            CalendarCommitment(
                title: "Optional CS 420 Office Hours",
                location: "Zoom",
                startTime: makeDate(daysFromNow: 0, hour: 13, minute: 0),
                endTime: makeDate(daysFromNow: 0, hour: 14, minute: 0),
                isAllDay: false,
                isBusy: false,
                calendarName: "University Calendar",
                colorHex: "#BF5AF2",
                isSimulatedDemo: true
            ),
            
            // Tomorrow (Day +1)
            CalendarCommitment(
                title: "Sprint Planning Sync",
                location: "Virtual Meeting",
                startTime: makeDate(daysFromNow: 1, hour: 9, minute: 30),
                endTime: makeDate(daysFromNow: 1, hour: 10, minute: 30),
                calendarName: "Work Calendar",
                colorHex: "#0A84FF",
                isSimulatedDemo: true
            ),
            CalendarCommitment(
                title: "Lunch",
                location: nil,
                startTime: makeDate(daysFromNow: 1, hour: 12, minute: 0),
                endTime: makeDate(daysFromNow: 1, hour: 13, minute: 0),
                calendarName: "Personal Calendar",
                colorHex: "#30D158",
                isSimulatedDemo: true
            ),
            
            // Day +2 to Day +4 (Multi-day conference)
            CalendarCommitment(
                title: "Annual Developer Summit",
                location: "Convention Center",
                startTime: makeDate(daysFromNow: 2, hour: 9, minute: 0),
                endTime: makeDate(daysFromNow: 4, hour: 17, minute: 0),
                isAllDay: false,
                isBusy: true,
                calendarName: "Work Calendar",
                colorHex: "#0A84FF",
                isSimulatedDemo: true
            ),
            
            // Day +2
            CalendarCommitment(
                title: "CS 420 Lecture",
                location: "Main Lecture Hall",
                startTime: makeDate(daysFromNow: 2, hour: 11, minute: 0),
                endTime: makeDate(daysFromNow: 2, hour: 12, minute: 0),
                calendarName: "University Calendar",
                colorHex: "#BF5AF2",
                isSimulatedDemo: true
            ),
            
            // Day +3
            CalendarCommitment(
                title: "Campus Cluster Maintenance",
                location: "Cluster Offline",
                startTime: makeDate(daysFromNow: 3, hour: 18, minute: 0),
                endTime: makeDate(daysFromNow: 3, hour: 22, minute: 0),
                calendarName: "University Calendar",
                colorHex: "#FF9F0A",
                isSimulatedDemo: true
            ),
            
            // Day +4
            CalendarCommitment(
                title: "Weekly Engineering Demo",
                location: "Auditorium",
                startTime: makeDate(daysFromNow: 4, hour: 16, minute: 0),
                endTime: makeDate(daysFromNow: 4, hour: 17, minute: 0),
                calendarName: "Work Calendar",
                colorHex: "#0A84FF",
                isSimulatedDemo: true
            ),
            
            // Day +5 (All-Day Event)
            CalendarCommitment(
                title: "University Reading Day",
                location: "Campus",
                startTime: makeDate(daysFromNow: 5, hour: 0, minute: 0),
                endTime: makeDate(daysFromNow: 5, hour: 23, minute: 59),
                isAllDay: true,
                isBusy: true,
                calendarName: "University Calendar",
                colorHex: "#BF5AF2",
                isSimulatedDemo: true
            )
        ]
    }
    
    public static func makeDemonstrationDatabase() -> PlannerDatabase {
        let emails = makeSampleEmails()
        let commitments = makeCalendarCommitments()
        
        let lab3TaskId = UUID()
        let deckTaskId = UUID()
        
        // Task 1: Clear Assignment with deadline extended by Email 4
        let deadlineExtended = makeDate(daysFromNow: 6, hour: 23, minute: 59) // Sunday
        
        let task1 = DiscoveredTask(
            id: lab3TaskId,
            title: "CS 420 Lab 3: Raft Consensus Implementation",
            requiredAction: "Implement leader election, heartbeats, and log replication",
            notes: "Implement leader election, heartbeats, and log replication. Grading harness available in starter repo.",
            sourceEmail: emails[0],
            extractedDeadline: deadlineExtended,
            isDeadlineSupportedByEmail: true,
            supportingExcerpt: "Submission Deadline: This Friday at 11:59 PM. Estimated effort: 3 hours (180 minutes).",
            estimatedMinutes: 180,
            status: .ready,
            uncertainDetails: [],
            clarificationPrompt: nil,
            isClarified: true,
            deadlineUpdateNote: "Extended to Sunday (+48h) due to server maintenance window.",
            createdAt: emails[0].receivedDate,
            updatedAt: emails[3].receivedDate
        )
        
        // Task 2: Ambiguous Request
        let task2 = DiscoveredTask(
            id: deckTaskId,
            title: "Review & clarify slide 8 architecture diagrams",
            requiredAction: "Review slide 8 architecture diagram and decide on full overhaul vs minor callouts",
            notes: "Client requested cloud redundancy highlighted on slide 8. Need decision on full overhaul vs minor callouts.",
            sourceEmail: emails[1],
            extractedDeadline: nil, // Ambiguous: no deadline given!
            isDeadlineSupportedByEmail: false,
            supportingExcerpt: "Whenever you get some breathing room this week or next, could you take a quick pass at the architecture diagram on slide 8?",
            estimatedMinutes: 45,
            status: .needsClarification,
            uncertainDetails: [
                "No deadline specified in email ('this week or next')",
                "Scope is open-ended: full diagram overhaul vs minor callouts"
            ],
            clarificationPrompt: "No deadline specified ('this week or next') and scope is ambiguous. Pick a target completion date and clarify scope.",
            isClarified: false,
            deadlineUpdateNote: nil,
            createdAt: emails[1].receivedDate,
            updatedAt: emails[1].receivedDate
        )
        
        // Work sessions scheduled around commitments:
        // Free periods today:
        // 9:00 - 10:00 (Open)
        // 10:00 - 11:00 (Busy: Team Standup)
        // 11:00 - 12:00 (Open) -> Work Session 1 (Task 1, 60m)
        // 12:00 - 13:00 (Busy: Lunch)
        // 13:00 - 14:15 (Open) -> Work Session 2 (Task 2, 45m + buffer)
        // 14:30 - 15:30 (Busy: CS 420 Discussion)
        // 15:30 - 16:30 (Open) -> Work Session 3 (Task 1, 60m)
        // 16:30 - 17:00 (Busy: 1-on-1 Mentor)
        
        let session1 = WorkSession(
            taskId: lab3TaskId,
            title: "Lab 3: Leader Election & Heartbeats Setup",
            startTime: makeDate(daysFromNow: 0, hour: 11, minute: 0),
            endTime: makeDate(daysFromNow: 0, hour: 12, minute: 0),
            status: .completed,
            notes: "Set up test harness and verified initial election timer tick."
        )
        
        let session2 = WorkSession(
            taskId: deckTaskId,
            title: "Pitch Deck: Slide 8 Diagram Audit",
            startTime: makeDate(daysFromNow: 0, hour: 13, minute: 0),
            endTime: makeDate(daysFromNow: 0, hour: 13, minute: 45),
            status: .planned,
            notes: "Inspect current architecture diagram and draft 2 layout options for Alex."
        )
        
        let session3 = WorkSession(
            taskId: lab3TaskId,
            title: "Lab 3: Log Replication RPCs",
            startTime: makeDate(daysFromNow: 0, hour: 15, minute: 30),
            endTime: makeDate(daysFromNow: 0, hour: 16, minute: 30),
            status: .planned,
            notes: "Implement AppendEntries handler and state machine apply index."
        )
        
        let session4 = WorkSession(
            taskId: lab3TaskId,
            title: "Lab 3: Full Test Suite Execution",
            startTime: makeDate(daysFromNow: 1, hour: 10, minute: 30),
            endTime: makeDate(daysFromNow: 1, hour: 11, minute: 30),
            status: .planned,
            notes: "Run 2A and 2B concurrency tests."
        )
        
        // Processing logs showing discovery pipeline decisions
        let log1 = EmailProcessingLog(
            emailId: emails[0].id,
            sender: emails[0].senderName,
            subject: emails[0].subject,
            timestamp: emails[0].receivedDate,
            action: .taskCreated,
            explanation: "Discovered clear assignment. Extracted deadline (Friday 11:59 PM) and estimated effort (180 mins). Status set to Ready to Schedule.",
            extractedTaskId: lab3TaskId
        )
        
        let log2 = EmailProcessingLog(
            emailId: emails[1].id,
            sender: emails[1].senderName,
            subject: emails[1].subject,
            timestamp: emails[1].receivedDate,
            action: .taskNeedsClarification,
            explanation: "Discovered task request with missing deadline ('sometime soon') and open scope. Flagged for user clarification.",
            extractedTaskId: deckTaskId
        )
        
        let log3 = EmailProcessingLog(
            emailId: emails[2].id,
            sender: emails[2].senderName,
            subject: emails[2].subject,
            timestamp: emails[2].receivedDate,
            action: .ignoredNewsletter,
            explanation: "Classified as newsletter / informational broadcast. No personal assignments, requests, or deadlines detected. Filtered out from task list.",
            extractedTaskId: nil
        )
        
        let log4 = EmailProcessingLog(
            emailId: emails[3].id,
            sender: emails[3].senderName,
            subject: emails[3].subject,
            timestamp: emails[3].receivedDate,
            action: .taskUpdated,
            explanation: "Detected deadline extension for 'CS 420 Lab 3'. Matched thread 'thread-cs420-lab3'. Automatically updated deadline to Sunday 11:59 PM (+48 hours).",
            extractedTaskId: lab3TaskId
        )
        
        return PlannerDatabase(
            version: 1,
            tasks: [task1, task2],
            workSessions: [session1, session2, session3, session4],
            calendarCommitments: commitments,
            processedLogs: [log4, log3, log2, log1], // newest first
            preferences: UserPreferences(),
            lastSyncDate: Date()
        )
    }
}
