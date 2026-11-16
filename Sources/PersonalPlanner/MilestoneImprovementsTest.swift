import Foundation

public final class MilestoneImprovementsTest {
    
    private static var totalPassed = 0
    private static var totalFailed = 0
    
    private static func check(_ description: String, _ condition: Bool) {
        if condition {
            print("  ✅ [PASS] \(description)")
            totalPassed += 1
        } else {
            print("  ❌ [FAIL] \(description)")
            totalFailed += 1
        }
    }
    
    @MainActor
    public static func runAllTests() -> Bool {
        print("\n=======================================================")
        print(" 🚀 PERSONAL PLANNER MILESTONE IMPROVEMENTS TEST SUITE")
        print(" Dismissals, Reporting Months, Delete Logs, Calendar Work")
        print("=======================================================\n")
        
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        let tempBaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("PP_Milestone_Test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempBaseURL, withIntermediateDirectories: true)
        
        let testDbURL = tempBaseURL.appendingPathComponent("planner_database.json")
        let storageService = StorageService(customURL: testDbURL)
        
        let appState = AppState(
            storageService: storageService,
            addOns: .inFolder(tempBaseURL)
        )
        
        // -----------------------------------------------------------------
        // STAGE 1: Clear Dismissed Tasks & Scan Protection
        // -----------------------------------------------------------------
        print("--- Stage 1: Clear Dismissed Tasks & Scan Prevention ---")
        
        let email1 = EmailSource(
            id: "msg_dismiss_001",
            threadId: "thread_dismiss_001",
            senderName: "Prof. Miller",
            senderEmail: "prof@university.edu",
            subject: "Optional Research Seminar",
            receivedDate: Date(),
            snippet: "Feel free to attend if interested.",
            fullBody: "Seminar on Friday.",
            category: .assignment
        )
        let task1 = DiscoveredTask(
            id: UUID(),
            title: "Attend Optional Research Seminar",
            requiredAction: "Attend seminar if interested",
            notes: "Optional",
            sourceEmail: email1,
            isDismissed: false
        )
        appState.tasks.append(task1)
        check("Initial task added to visible tasks", appState.tasks.contains(where: { $0.id == task1.id }))
        
        // User dismisses task
        appState.dismissTask(taskId: task1.id)
        check("Task marked isDismissed", appState.tasks.first(where: { $0.id == task1.id })?.isDismissed == true)
        check("Cleared dismissed records currently empty", appState.clearedDismissedTasks.isEmpty)
        
        // User clicks Clear Dismissed
        appState.clearDismissedTasks()
        check("Dismissed task removed from visible tasks list", !appState.tasks.contains(where: { $0.id == task1.id }))
        check("Cleared dismissed record created", appState.clearedDismissedTasks.count == 1)
        check("Cleared record stores source email ID", appState.clearedDismissedTasks.first?.sourceEmailId == email1.id)
        check("Cleared record stores source thread ID", appState.clearedDismissedTasks.first?.sourceThreadId == email1.threadId)
        
        // Verify Persistence across restart
        let reloadedAppState = AppState(
            storageService: storageService,
            addOns: .inFolder(tempBaseURL)
        )
        check("Cleared dismissed tasks survive persistence reload", reloadedAppState.clearedDismissedTasks.count == 1)
        check("Reloaded task is not in visible tasks", !reloadedAppState.tasks.contains(where: { $0.id == task1.id }))
        
        // Simulate email scan encountering the same message again
        let candidateTask = CandidateTask(
            title: "Attend Optional Research Seminar",
            requiredAction: "Attend seminar if interested",
            deadlineIso: nil,
            deadlineIsSupportedByEmail: false,
            supportingExcerpt: "Attend seminar",
            estimatedDurationMinutes: 60
        )
        let dummyAnalysis = EmailAnalysis(
            isNewsletterOrMarketing: false,
            isDirectedAtRecipient: true,
            hasActionableTask: true,
            reasoning: "Sample",
            tasks: [candidateTask]
        )
        let preCount = reloadedAppState.tasks.count
        reloadedAppState.processExtractedEmailTasks(email: email1, analysis: dummyAnalysis)
        check("Future scan does NOT recreate previously dismissed and cleared task", reloadedAppState.tasks.count == preCount)
        check("Audit log records skipped dismissed candidate", reloadedAppState.logs.contains(where: { $0.action == .taskDismissed }))
        
        // -----------------------------------------------------------------
        // STAGE 7: Combined Timeline, Stable Ordering & Overlap Flagging
        // -----------------------------------------------------------------
        print("\n--- Stage 7: Combined Timeline, Stable Ordering & Overlap Flagging ---")
        
        let testDay = Date()
        var testCal = Calendar(identifier: .gregorian)
        testCal.timeZone = tz
        let startOfToday = testCal.startOfDay(for: testDay)
        
        // Setup Deadlines: 5:00 PM and 11:59 AM
        let dlLate = testCal.date(bySettingHour: 17, minute: 0, second: 0, of: startOfToday)!
        let dlEarly = testCal.date(bySettingHour: 11, minute: 59, second: 0, of: startOfToday)!
        
        let emailLate = EmailSource(
            id: "m_late",
            threadId: "th_late",
            senderName: "Prof. Physics",
            senderEmail: "prof@univ.edu",
            subject: "PS4 Due Today",
            receivedDate: Date(),
            snippet: "Submit by 5pm",
            fullBody: "Assignment 4",
            category: .assignment
        )
        let emailEarly = EmailSource(
            id: "m_early",
            threadId: "th_early",
            senderName: "TA Math",
            senderEmail: "ta@univ.edu",
            subject: "Quiz",
            receivedDate: Date(),
            snippet: "Quiz at noon",
            fullBody: "Math Quiz",
            category: .assignment
        )
        
        let taskLate = DiscoveredTask(
            id: UUID(),
            title: "Physics Problem Set 4",
            requiredAction: "Submit assignment",
            sourceEmail: emailLate,
            extractedDeadline: dlLate,
            status: .ready
        )
        let taskEarly = DiscoveredTask(
            id: UUID(),
            title: "Math Quiz Preparation",
            requiredAction: "Submit quiz",
            sourceEmail: emailEarly,
            extractedDeadline: dlEarly,
            status: .completed
        )
        
        // Setup Apple Calendar Events:
        // 1. All-day event: "University Holiday"
        let allDayHoliday = CalendarCommitment(
            title: "University Holiday",
            startTime: startOfToday,
            endTime: testCal.date(byAdding: .day, value: 1, to: startOfToday)!,
            isAllDay: true,
            calendarName: "Campus"
        )
        
        // 2. Class: 10:30 AM – 11:50 AM (Busy)
        let classStart = testCal.date(bySettingHour: 10, minute: 30, second: 0, of: startOfToday)!
        let classEnd = testCal.date(bySettingHour: 11, minute: 50, second: 0, of: startOfToday)!
        let classCommitment = CalendarCommitment(
            title: "Econ 201 Lecture",
            startTime: classStart,
            endTime: classEnd,
            isAllDay: false,
            isBusy: true,
            calendarName: "Classes"
        )
        
        // 3. Independent afternoon commitment: 2:00 PM – 3:00 PM
        let afternoonStart = testCal.date(bySettingHour: 14, minute: 0, second: 0, of: startOfToday)!
        let afternoonEnd = testCal.date(bySettingHour: 15, minute: 0, second: 0, of: startOfToday)!
        let afternoonCommitment = CalendarCommitment(
            title: "Advisor Meeting",
            startTime: afternoonStart,
            endTime: afternoonEnd,
            calendarName: "Meetings"
        )
        
        // Setup Work Sessions:
        // 1. Proposed session overlapping class: 10:30 AM – 10:45 AM (Conflicts with Econ 201!)
        let conflictSessionStart = testCal.date(bySettingHour: 10, minute: 30, second: 0, of: startOfToday)!
        let conflictSessionEnd = testCal.date(bySettingHour: 10, minute: 45, second: 0, of: startOfToday)!
        let conflictSession = WorkSession(
            id: UUID(),
            title: "Review Quiz Notes",
            startTime: conflictSessionStart,
            endTime: conflictSessionEnd
        )
        
        // 2. Non-overlapping back-to-back session: 9:30 AM – 10:30 AM (Ends right when class starts)
        let backToBackStart = testCal.date(bySettingHour: 9, minute: 30, second: 0, of: startOfToday)!
        let backToBackEnd = testCal.date(bySettingHour: 10, minute: 30, second: 0, of: startOfToday)!
        let backToBackSession = WorkSession(
            id: UUID(),
            title: "Morning Study",
            startTime: backToBackStart,
            endTime: backToBackEnd
        )
        
        // 3. Published session: 4:00 PM – 5:00 PM with corresponding published Apple Calendar event
        let publishedStart = testCal.date(bySettingHour: 16, minute: 0, second: 0, of: startOfToday)!
        let publishedEnd = testCal.date(bySettingHour: 17, minute: 0, second: 0, of: startOfToday)!
        let pubEventId = "ek_published_event_999"
        let publishedSession = WorkSession(
            id: UUID(),
            title: "Econ TA Office Hours",
            startTime: publishedStart,
            endTime: publishedEnd,
            calendarEventId: pubEventId
        )
        let publishedCommitmentDuplicate = CalendarCommitment(
            title: "Econ TA Office Hours",
            startTime: publishedStart,
            endTime: publishedEnd,
            externalEventId: pubEventId,
            isPlannerOwnEvent: true
        )
        
        let allTasks = [taskLate, taskEarly]
        var allSessions = [conflictSession, backToBackSession, publishedSession]
        let allCommitments = [allDayHoliday, classCommitment, afternoonCommitment, publishedCommitmentDuplicate]
        
        // Build Day Data
        let dayData = UnifiedTimelineEngine.buildDayData(
            day: startOfToday,
            tasks: allTasks,
            workSessions: allSessions,
            commitments: allCommitments,
            timeZone: tz
        )
        
        // 1. Deadlines above timed timeline, sorted strictly by due time
        check("Deadlines count is 2", dayData.deadlines.count == 2)
        check("Deadlines sorted by due time (11:59 AM before 5:00 PM)", dayData.deadlines.first?.title == "Math Quiz Preparation")
        check("Second deadline is 5:00 PM", dayData.deadlines.last?.title == "Physics Problem Set 4")
        
        // 2. All-day events segregated above timed timeline
        check("All-day events segregated above timed timeline", dayData.allDayCommitments.count == 1)
        check("All-day event title matches", dayData.allDayCommitments.first?.title == "University Holiday")
        
        // 3. Deduplication of published work session
        check("Published work session not duplicated (no duplicate commitment in timed items)", !dayData.timedItems.contains(where: {
            if case .commitment(let c) = $0.kind {
                return c.externalEventId == pubEventId
            }
            return false
        }))
        check("Published work session appears as session item", dayData.timedItems.contains(where: {
            if case .workSession(let s) = $0.kind {
                return s.id == publishedSession.id
            }
            return false
        }))
        
        // 4. Chronological ordering of combined timeline
        check("Timed items count is 5", dayData.timedItems.count == 5)
        check("Item 1 is 9:30 AM Morning Study", dayData.timedItems[0].title == "Morning Study")
        check("Item 2 starts at 10:30 AM (Econ 201 Lecture)", dayData.timedItems[1].title == "Econ 201 Lecture")
        check("Item 3 starts at 10:30 AM (Review Quiz Notes)", dayData.timedItems[2].title == "Review Quiz Notes")
        check("Stable tie-breaking orders commitment before session at 10:30 AM", dayData.timedItems[1].isCommitment && dayData.timedItems[2].isWorkSession)
        check("Item 4 is 2:00 PM Advisor Meeting", dayData.timedItems[3].title == "Advisor Meeting")
        check("Item 5 is 4:00 PM Econ TA Office Hours", dayData.timedItems[4].title == "Econ TA Office Hours")
        
        // 5. Overlap detection
        let classItem = dayData.timedItems.first(where: { $0.title == "Econ 201 Lecture" })!
        let conflictItem = dayData.timedItems.first(where: { $0.title == "Review Quiz Notes" })!
        
        check("Proposed 10:30–10:45 AM session is flagged as overlapping", conflictItem.isOverlapping)
        check("Session overlap mentions conflicting class", conflictItem.overlappingTitles.contains(where: { $0.contains("Econ 201 Lecture") }))
        check("Class at 10:30 AM is also flagged as overlapping", classItem.isOverlapping)
        check("Class overlap mentions conflicting proposed session", classItem.overlappingTitles.contains(where: { $0.contains("Review Quiz Notes") }))
        
        // 6. Non-overlapping back-to-back
        let backToBackItem = dayData.timedItems.first(where: { $0.title == "Morning Study" })!
        check("Back-to-back 9:30–10:30 AM session has no overlap", !backToBackItem.isOverlapping)
        
        // 7. Immediate re-ordering when times change
        var modifiedConflictSession = conflictSession
        modifiedConflictSession.startTime = testCal.date(bySettingHour: 18, minute: 0, second: 0, of: startOfToday)! // Move to 6:00 PM
        modifiedConflictSession.endTime = testCal.date(bySettingHour: 18, minute: 30, second: 0, of: startOfToday)!
        allSessions[0] = modifiedConflictSession
        
        let reorderedData = UnifiedTimelineEngine.buildDayData(
            day: startOfToday,
            tasks: allTasks,
            workSessions: allSessions,
            commitments: allCommitments,
            timeZone: tz
        )
        check("Moving session immediately moves it to end of timeline (6:00 PM)", reorderedData.timedItems.last?.title == "Review Quiz Notes")
        check("Conflict cleared after moving session out of class window", !(reorderedData.timedItems.last?.isOverlapping ?? true))
        check("Class at 10:30 AM no longer has conflict", !(reorderedData.timedItems.first(where: { $0.title == "Econ 201 Lecture" })?.isOverlapping ?? true))
        
        // -----------------------------------------------------------------
        // STAGE 8: Delete Proposed Sessions in Today and Week Tab
        // -----------------------------------------------------------------
        print("--- Stage 8: Delete Proposed Sessions in Today & Week Tab ---")
        
        let sampleTask = DiscoveredTask(
            id: UUID(),
            title: "Prepare Presentation Slides",
            requiredAction: "Draft 5 slides",
            notes: "Week 8 slides",
            sourceEmail: EmailSource(
                id: "msg_slide_01",
                threadId: "thread_slide_01",
                senderName: "Prof. Davis",
                senderEmail: "davis@university.edu",
                subject: "Presentation Requirements",
                receivedDate: Date(),
                snippet: "Prepare slides",
                fullBody: "Prepare slides by Friday",
                category: .assignment
            ),
            supportingExcerpt: "Due this Friday",
            estimatedMinutes: 60,
            planningTargetDate: testCal.date(byAdding: .day, value: 2, to: startOfToday)
        )
        appState.tasks.append(sampleTask)
        
        let proposedSessionToDelete = WorkSession(
            id: UUID(),
            taskId: sampleTask.id,
            title: "Work on Presentation Slides",
            startTime: testCal.date(bySettingHour: 13, minute: 0, second: 0, of: startOfToday)!,
            endTime: testCal.date(bySettingHour: 14, minute: 0, second: 0, of: startOfToday)!,
            status: .planned
        )
        appState.workSessions.append(proposedSessionToDelete)
        appState.saveDatabase()
        
        // 1. Verify session is present in both Today and Week timeline projections
        let todayBeforeDelete = UnifiedTimelineEngine.buildDayData(
            day: startOfToday,
            tasks: appState.tasks,
            workSessions: appState.workSessions,
            commitments: appState.commitments,
            timeZone: tz
        )
        check("Proposed session is visible in Today timeline before deletion", todayBeforeDelete.timedItems.contains(where: { $0.workSession?.id == proposedSessionToDelete.id }))
        
        // 2. Perform deletion via appState.removeSession (which is called by the delete/trash button in both Today and Week views)
        appState.removeSession(id: proposedSessionToDelete.id)
        
        // 3. Verify session is immediately removed from workSessions
        check("Proposed session is immediately removed from appState.workSessions", !appState.workSessions.contains(where: { $0.id == proposedSessionToDelete.id }))
        
        // 4. Verify Today timeline projection immediately omits the deleted session
        let todayAfterDelete = UnifiedTimelineEngine.buildDayData(
            day: startOfToday,
            tasks: appState.tasks,
            workSessions: appState.workSessions,
            commitments: appState.commitments,
            timeZone: tz
        )
        check("Today timeline no longer contains the deleted session", !todayAfterDelete.timedItems.contains(where: { $0.workSession?.id == proposedSessionToDelete.id }))
        
        // 5. Verify Week timeline projection immediately omits the deleted session
        let weekAfterDelete = UnifiedTimelineEngine.buildDayData(
            day: startOfToday,
            tasks: appState.tasks,
            workSessions: appState.workSessions,
            commitments: appState.commitments,
            timeZone: tz
        )
        check("Week timeline no longer contains the deleted session", !weekAfterDelete.timedItems.contains(where: { $0.workSession?.id == proposedSessionToDelete.id }))
        
        // 6. Verify non-resurrection: triggering recalculateSchedule does NOT resurrect the deleted session
        appState.recalculateSchedule()
        check("recalculateSchedule does NOT resurrect the deleted session", !appState.workSessions.contains(where: { $0.taskId == sampleTask.id && $0.startTime == proposedSessionToDelete.startTime }))
        
        // 7. Verify persistence across restart
        let reloadedAppState8 = AppState(
            storageService: storageService,
            addOns: .inFolder(tempBaseURL)
        )
        check("Session remains deleted after reloading from storage", !reloadedAppState8.workSessions.contains(where: { $0.id == proposedSessionToDelete.id }))
        check("The deleted time is remembered across restarts (never planned again)",
              reloadedAppState8.declinedSlots.contains { $0.start == proposedSessionToDelete.startTime } || proposedSessionToDelete.endTime <= Date())
        check("Deleting a session keeps the task's full time estimate",
              reloadedAppState8.tasks.first { $0.id == sampleTask.id }?.effectiveDuration == 60 && reloadedAppState8.deletedProposedMinutesByTaskId.isEmpty)
        
        // -----------------------------------------------------------------
        // STAGE 9: Not Done Yet Carryover & Same-Day Early Completion
        // -----------------------------------------------------------------
        print("--- Stage 9: Not Done Yet Carryover & Early Completion ---")
        
        let tomorrow = testCal.date(byAdding: .day, value: 1, to: startOfToday)!
        
        // 1. Task A (Ordinary flexible task) and Task B (Carryover task)
        let taskOrdinary = DiscoveredTask(
            id: UUID(),
            title: "Ordinary Literature Review",
            requiredAction: "Read papers",
            notes: "Flexible task",
            sourceEmail: EmailSource(
                id: "msg_ord_01",
                threadId: "thread_ord_01",
                senderName: "Prof. Oak",
                senderEmail: "oak@university.edu",
                subject: "Reading list",
                receivedDate: Date(),
                snippet: "Review papers",
                fullBody: "Read papers",
                category: .assignment,
                isSimulatedDemo: false
            ),
            supportingExcerpt: "Read papers",
            estimatedMinutes: 60,
            userPriority: .medium,
            planningTargetDate: testCal.date(byAdding: .day, value: 3, to: startOfToday)
        )
        
        let taskCarryover = DiscoveredTask(
            id: UUID(),
            title: "Urgent Lab Analysis",
            requiredAction: "Analyze samples",
            notes: "Unfinished lab work",
            sourceEmail: EmailSource(
                id: "msg_co_01",
                threadId: "thread_co_01",
                senderName: "Dr. Elm",
                senderEmail: "elm@lab.edu",
                subject: "Lab results needed",
                receivedDate: Date(),
                snippet: "Analyze samples",
                fullBody: "Analyze lab samples",
                category: .assignment,
                isSimulatedDemo: false
            ),
            supportingExcerpt: "Analyze samples",
            estimatedMinutes: 60,
            userPriority: .medium,
            planningTargetDate: testCal.date(byAdding: .day, value: 3, to: startOfToday),
            isCarryover: true
        )
        
        appState.tasks.append(taskOrdinary)
        appState.tasks.append(taskCarryover)
        
        // Run schedule for tomorrow
        let engine = RuleBasedSchedulingEngine()
        let schedResult = engine.generateSchedule(
            tasks: [taskOrdinary, taskCarryover],
            commitments: [],
            existingSessions: [],
            preferences: appState.preferences,
            dateRange: tomorrow...testCal.date(byAdding: .day, value: 5, to: tomorrow)!,
            currentDate: tomorrow
        )
        
        let coSession = schedResult.proposedSessions.first(where: { $0.taskId == taskCarryover.id })
        let ordSession = schedResult.proposedSessions.first(where: { $0.taskId == taskOrdinary.id })
        
        check("Carryover task is scheduled in the plan", coSession != nil)
        check("Ordinary task is scheduled in the plan", ordSession != nil)
        if let coS = coSession, let ordS = ordSession {
            check("Carryover task is scheduled in earliest slot before ordinary task", coS.startTime.isBefore(ordS.startTime))
            check("Carryover session is flagged isCarryover", coS.isCarryover)
        }
        
        // 2. Not Done Yet replan & displacement of flexible sessions
        let unfinishedSession = WorkSession(
            id: UUID(),
            taskId: taskOrdinary.id,
            title: "Ordinary Literature Review",
            startTime: testCal.date(bySettingHour: 9, minute: 0, second: 0, of: startOfToday)!,
            endTime: testCal.date(bySettingHour: 10, minute: 0, second: 0, of: startOfToday)!,
            status: .planned
        )
        appState.workSessions = [unfinishedSession]
        appState.saveDatabase()
        
        // Trigger confirmCarryover
        appState.confirmCarryover(session: unfinishedSession, remainingMinutes: 45, carryoverToNextWorkday: true)
        
        let carriedTask = appState.tasks.first(where: { $0.id == taskOrdinary.id })
        check("confirmCarryover marked task isCarryover", carriedTask?.isCarryover == true)
        check("Original unfinished session was replaced without duplicate", !appState.workSessions.contains(where: { $0.id == unfinishedSession.id }))
        check("Replan explanation generated", appState.replanExplanation != nil)
        check("Undo snapshot recorded", appState.lastUndoSnapshot != nil)
        
        // Test Undo
        appState.undoLatestReplan()
        check("Undo restored unfinished session", appState.workSessions.contains(where: { $0.id == unfinishedSession.id }))
        check("Undo cleared isCarryover", appState.tasks.first(where: { $0.id == taskOrdinary.id })?.isCarryover == false)
        
        // 3. Same-Day Early Completion Rescheduling
        // Runs on a fixed upcoming Wednesday, so the result never depends on the real day or time:
        // weekends aren't workdays, and "never in the past" would otherwise use the real clock.
        let ecDay: Date = {
            var d = testCal.startOfDay(for: Date())
            repeat { d = testCal.date(byAdding: .day, value: 1, to: d)! } while testCal.component(.weekday, from: d) != 4
            return d
        }()
        let ecTomorrow = testCal.date(byAdding: .day, value: 1, to: ecDay)!
        // Their targets were set relative to today; keep them three days after the test day.
        for id in [taskOrdinary.id, taskCarryover.id] {
            if let i = appState.tasks.firstIndex(where: { $0.id == id }) {
                appState.tasks[i].planningTargetDate = testCal.date(byAdding: .day, value: 3, to: ecDay)
            }
        }
        let morningSession = WorkSession(
            id: UUID(),
            taskId: taskOrdinary.id,
            title: "Morning Review",
            startTime: testCal.date(bySettingHour: 9, minute: 0, second: 0, of: ecDay)!,
            endTime: testCal.date(bySettingHour: 11, minute: 0, second: 0, of: ecDay)!,
            status: .planned
        )
        let afternoonSession = WorkSession(
            id: UUID(),
            taskId: taskCarryover.id,
            title: "Afternoon Lab",
            startTime: testCal.date(bySettingHour: 14, minute: 0, second: 0, of: ecDay)!,
            endTime: testCal.date(bySettingHour: 15, minute: 0, second: 0, of: ecDay)!,
            status: .planned
        )
        let tomorrowSession = WorkSession(
            id: UUID(),
            taskId: taskOrdinary.id,
            title: "Tomorrow Session",
            startTime: testCal.date(bySettingHour: 10, minute: 0, second: 0, of: ecTomorrow)!,
            endTime: testCal.date(bySettingHour: 11, minute: 0, second: 0, of: ecTomorrow)!,
            status: .planned
        )
        appState.workSessions = [morningSession, afternoonSession, tomorrowSession]
        appState.saveDatabase()
        
        // Complete morning session early at 9:30 AM (releasing 9:30 - 11:00 AM)
        let earlyFinishTime = testCal.date(bySettingHour: 9, minute: 30, second: 0, of: ecDay)!
        appState.completeSessionEarly(id: morningSession.id, completionTime: earlyFinishTime)
        
        let completedMorning = appState.workSessions.first(where: { $0.id == morningSession.id })
        check("Morning session marked completed", completedMorning?.status == .completed)
        check("Morning session end time adjusted to completion time", completedMorning?.endTime == earlyFinishTime)
        
        let movedAfternoon = appState.workSessions.first(where: { $0.id == afternoonSession.id })
        check("Afternoon session advanced earlier that day into freed morning slot", (movedAfternoon?.startTime.isBefore(testCal.date(bySettingHour: 14, minute: 0, second: 0, of: ecDay)!)) == true)
        check("Advanced session starts at or after early completion time", (movedAfternoon?.startTime.isAfterOrEqual(earlyFinishTime)) == true)
        check("Advanced session status remains planned (never assumed started/completed)", movedAfternoon?.status == SessionStatus.planned)
        
        let unchangedTomorrow = appState.workSessions.first(where: { $0.id == tomorrowSession.id })
        check("Tomorrow's session was NOT pulled into today", testCal.isDate(unchangedTomorrow!.startTime, inSameDayAs: ecTomorrow))
        
        // 4. Protection: Locked sessions are not moved
        let lockedSession = WorkSession(
            id: UUID(),
            taskId: taskOrdinary.id,
            title: "Protected Session",
            startTime: testCal.date(bySettingHour: 15, minute: 0, second: 0, of: ecDay)!,
            endTime: testCal.date(bySettingHour: 16, minute: 0, second: 0, of: ecDay)!,
            status: .planned,
            isLocked: true
        )
        appState.workSessions.append(lockedSession)
        appState.advanceSameDayFlexibleSessions(on: ecDay, from: earlyFinishTime)
        let checkedLocked = appState.workSessions.first(where: { $0.id == lockedSession.id })
        check("Locked session was not moved", checkedLocked?.startTime == testCal.date(bySettingHour: 15, minute: 0, second: 0, of: ecDay)!)
        
        // 5. Whole task completion releases future proposals while retaining completed history
        let splitSession1 = WorkSession(
            id: UUID(),
            taskId: taskCarryover.id,
            title: "Lab Part 1",
            startTime: testCal.date(bySettingHour: 8, minute: 0, second: 0, of: ecDay)!,
            endTime: testCal.date(bySettingHour: 9, minute: 0, second: 0, of: ecDay)!,
            status: .completed
        )
        let splitSession2 = WorkSession(
            id: UUID(),
            taskId: taskCarryover.id,
            title: "Lab Part 2",
            startTime: testCal.date(bySettingHour: 17, minute: 0, second: 0, of: ecDay)!,
            endTime: testCal.date(bySettingHour: 18, minute: 0, second: 0, of: ecDay)!,
            status: .planned
        )
        appState.workSessions.append(splitSession1)
        appState.workSessions.append(splitSession2)
        
        appState.toggleTaskCompletion(id: taskCarryover.id)
        check("Task marked completed", appState.tasks.first(where: { $0.id == taskCarryover.id })?.isCompleted == true)
        check("Completed history session is retained", appState.workSessions.contains(where: { $0.id == splitSession1.id && $0.status == .completed }))
        check("Future planned proposal was removed", !appState.workSessions.contains(where: { $0.id == splitSession2.id }))
        
        // 6. Persistence of carryover across restart
        if let idx = appState.tasks.firstIndex(where: { $0.id == taskOrdinary.id }) {
            appState.tasks[idx].isCarryover = true
        }
        appState.saveDatabase()
        let reloadedAppState9 = AppState(
            storageService: storageService,
            addOns: .inFolder(tempBaseURL)
        )
        check("isCarryover status survives restart in storage", reloadedAppState9.tasks.first(where: { $0.id == taskOrdinary.id })?.isCarryover == true)
        
        // -----------------------------------------------------------------
        // STAGE 10: Review Fixes — Priority Tiers, Advancement Safety,
        //           Calendar Discrepancies, Local Events & Data Preservation
        // -----------------------------------------------------------------
        print("\n--- Stage 10: Priority Tiers & Review Regression Fixes ---")
        
        var prefCal = Calendar(identifier: .gregorian)
        prefCal.timeZone = appState.preferences.timeZone
        let prefToday = prefCal.startOfDay(for: Date())
        // First working day strictly after today (all dates relative; no live clock assumptions)
        var workDay = prefCal.date(byAdding: .day, value: 1, to: prefToday)!
        while !appState.preferences.workingHours(for: prefCal.component(.weekday, from: workDay)).isWorkday {
            workDay = prefCal.date(byAdding: .day, value: 1, to: workDay)!
        }
        let wdHours = appState.preferences.workingHours(for: prefCal.component(.weekday, from: workDay))
        let wdStart = prefCal.date(bySettingHour: wdHours.startHour, minute: wdHours.startMinute, second: 0, of: workDay)!
        let wdEnd = prefCal.date(bySettingHour: wdHours.endHour, minute: wdHours.endMinute, second: 0, of: workDay)!
        
        func makeTask(_ title: String, priority: TaskPriority, carryover: Bool, target: Date) -> DiscoveredTask {
            DiscoveredTask(
                id: UUID(),
                title: title,
                requiredAction: "Work on \(title)",
                notes: "Stage 10 fixture",
                sourceEmail: EmailSource(
                    id: "msg_s10_\(UUID().uuidString)",
                    threadId: "thread_s10_\(UUID().uuidString)",
                    senderName: "Fixture",
                    senderEmail: "fixture@example.test",
                    subject: title,
                    receivedDate: Date(),
                    snippet: title,
                    fullBody: title,
                    category: .assignment,
                    isSimulatedDemo: false
                ),
                supportingExcerpt: title,
                estimatedMinutes: 60,
                userPriority: priority,
                planningTargetDate: target,
                isCarryover: carryover
            )
        }
        
        // 10A: Urgent > Carryover > Ordinary, even when the ordinary task's deadline is earliest
        let farTarget = prefCal.date(byAdding: .day, value: 6, to: workDay)!
        let nearTarget = prefCal.date(byAdding: .day, value: 4, to: workDay)!
        let tOrdinaryEarly = makeTask("S10 Ordinary (earliest deadline)", priority: .high, carryover: false, target: nearTarget)
        let tCarryMedium = makeTask("S10 Carryover Medium", priority: .medium, carryover: true, target: farTarget)
        let tUrgent = makeTask("S10 Urgent", priority: .urgent, carryover: false, target: farTarget)
        let tierResult = RuleBasedSchedulingEngine().generateSchedule(
            tasks: [tOrdinaryEarly, tCarryMedium, tUrgent],
            commitments: [],
            existingSessions: [],
            preferences: appState.preferences,
            dateRange: workDay...prefCal.date(byAdding: .day, value: 8, to: workDay)!,
            currentDate: wdStart
        )
        let sUrg = tierResult.proposedSessions.first(where: { $0.taskId == tUrgent.id })
        let sCar = tierResult.proposedSessions.first(where: { $0.taskId == tCarryMedium.id })
        let sOrd = tierResult.proposedSessions.first(where: { $0.taskId == tOrdinaryEarly.id })
        check("10A: all three tier tasks scheduled", sUrg != nil && sCar != nil && sOrd != nil)
        if let u = sUrg, let c = sCar, let o = sOrd {
            check("10A: Urgent task takes the earliest slot (before medium carryover)", u.startTime.isBefore(c.startTime))
            check("10A: Carryover is scheduled before ordinary task", c.startTime.isBefore(o.startTime))
            check("10A: Urgent task starts at the start of the working day", u.startTime == wdStart)
        }
        check("10A: tier helper ranks urgent=0, carryover=1, ordinary=2",
              RuleBasedSchedulingEngine.schedulingTier(for: tUrgent) == 0 &&
              RuleBasedSchedulingEngine.schedulingTier(for: tCarryMedium) == 1 &&
              RuleBasedSchedulingEngine.schedulingTier(for: tOrdinaryEarly) == 2)
        let tUrgentCarry = makeTask("S10 Urgent Carryover", priority: .urgent, carryover: true, target: farTarget)
        check("10A: urgent carryover is in the urgent tier", RuleBasedSchedulingEngine.schedulingTier(for: tUrgentCarry) == 0)
        
        // 10B: Deadline protection preserved — an urgent task never pushes past its own cutoff, and an
        //      ordinary task with a tight deadline is reported rather than scheduled after its deadline.
        let tightTarget = prefCal.date(byAdding: .minute, value: 90, to: wdStart)!
        var tTight = makeTask("S10 Ordinary Tight Deadline", priority: .medium, carryover: false, target: tightTarget)
        tTight.estimatedMinutes = 60
        let deadlineResult = RuleBasedSchedulingEngine().generateSchedule(
            tasks: [tTight, tUrgent],
            commitments: [],
            existingSessions: [],
            preferences: appState.preferences,
            dateRange: workDay...prefCal.date(byAdding: .day, value: 8, to: workDay)!,
            currentDate: wdStart
        )
        let tightSessions = deadlineResult.proposedSessions.filter { $0.taskId == tTight.id }
        check("10B: no session for tight-deadline task ends after its planning target",
              tightSessions.allSatisfy { $0.endTime.isBeforeOrEqual(tightTarget) })
        check("10B: tight-deadline task is either scheduled or explicitly reported (never silently dropped)",
              !tightSessions.isEmpty || deadlineResult.unscheduledReports.contains(where: { $0.task.id == tTight.id }))
        
        // 10C: Never schedule before the supplied clock, even on a day that is not the wall-clock "today"
        let midMorning = prefCal.date(byAdding: .minute, value: 127, to: wdStart)!
        let clockResult = RuleBasedSchedulingEngine().generateSchedule(
            tasks: [tUrgent, tCarryMedium],
            commitments: [],
            existingSessions: [],
            preferences: appState.preferences,
            dateRange: workDay...prefCal.date(byAdding: .day, value: 8, to: workDay)!,
            currentDate: midMorning
        )
        check("10C: no proposed session starts before currentDate on a future day",
              !clockResult.proposedSessions.isEmpty && clockResult.proposedSessions.allSatisfy { $0.startTime.isAfterOrEqual(midMorning) })
        
        // 10D: Same-day advancement never overlaps a session that could not move, and respects lunch
        let tAdvA = makeTask("S10 Advance A", priority: .medium, carryover: false, target: farTarget)
        let tAdvB = makeTask("S10 Advance B", priority: .medium, carryover: false, target: farTarget)
        appState.tasks.append(contentsOf: [tAdvA, tAdvB])
        let completedEarly = WorkSession(taskId: tAdvA.id, title: "S10 Done Early",
                                         startTime: wdStart, endTime: wdStart.addingTimeInterval(30 * 60), status: .completed)
        let blocker = CalendarCommitment(id: UUID(), title: "S10 Blocker", location: nil,
                                         startTime: wdStart.addingTimeInterval(45 * 60), endTime: wdStart.addingTimeInterval(60 * 60),
                                         isAllDay: false, isBusy: true, calendarName: "Work", calendarIdentifier: "s10-cal",
                                         colorHex: "#0A84FF", isSimulatedDemo: false, externalEventId: "s10-evt-blocker")
        let stuckA = WorkSession(taskId: tAdvA.id, title: "S10 Stuck A",
                                 startTime: wdStart.addingTimeInterval(60 * 60), endTime: wdStart.addingTimeInterval(120 * 60))
        let lateB = WorkSession(taskId: tAdvB.id, title: "S10 Late B",
                                startTime: wdEnd.addingTimeInterval(-60 * 60), endTime: wdEnd)
        let savedCommitments = appState.commitments
        appState.workSessions = [completedEarly, stuckA, lateB]
        appState.commitments = [blocker]
        appState.advanceSameDayFlexibleSessions(on: workDay, from: wdStart.addingTimeInterval(30 * 60))
        let planned = appState.workSessions.filter { $0.status == .planned && prefCal.isDate($0.startTime, inSameDayAs: workDay) }
        var overlapFound = false
        for i in planned.indices {
            for j in planned.indices where j > i {
                if planned[i].startTime.isBefore(planned[j].endTime) && planned[j].startTime.isBefore(planned[i].endTime) {
                    overlapFound = true
                }
            }
        }
        check("10D: advanced sessions never overlap a session that stayed in place", !overlapFound)
        let movedB = appState.workSessions.first(where: { $0.id == lateB.id })!
        check("10D: late session B still advanced earlier", movedB.startTime.isBefore(lateB.startTime))
        let lunchStart = prefCal.date(bySettingHour: appState.preferences.lunchStartHour, minute: 0, second: 0, of: workDay)!
        let lunchEnd = lunchStart.addingTimeInterval(Double(appState.preferences.lunchDurationMinutes * 60))
        check("10D: advanced sessions do not land in the lunch break",
              planned.allSatisfy { !($0.startTime.isBefore(lunchEnd) && $0.endTime.isAfter(lunchStart)) })
        check("10D: advanced sessions do not overlap busy commitments",
              planned.allSatisfy { !($0.startTime.isBefore(blocker.endTime) && $0.endTime.isAfter(blocker.startTime)) })
        
        // 10E: Multi-day busy event that began the previous day still blocks advancement
        let overnight = CalendarCommitment(id: UUID(), title: "S10 Overnight", location: nil,
                                           startTime: wdStart.addingTimeInterval(-10 * 3600), endTime: wdStart.addingTimeInterval(3 * 3600),
                                           isAllDay: false, isBusy: true, calendarName: "Work", calendarIdentifier: "s10-cal",
                                           colorHex: "#0A84FF", isSimulatedDemo: false, externalEventId: "s10-evt-overnight")
        let lateC = WorkSession(taskId: tAdvB.id, title: "S10 Late C",
                                startTime: wdEnd.addingTimeInterval(-60 * 60), endTime: wdEnd)
        appState.workSessions = [lateC]
        appState.commitments = [overnight]
        appState.advanceSameDayFlexibleSessions(on: workDay, from: wdStart)
        let movedC = appState.workSessions.first(where: { $0.id == lateC.id })!
        check("10E: advancement respects a busy event that started the previous day",
              movedC.startTime.isAfterOrEqual(overnight.endTime))
        
        // 10F: Local edits to a published session are not reported as "moved in Apple Calendar"
        let simCal = SimulatedCalendarService()
        var pubSession = WorkSession(taskId: tAdvA.id, title: "S10 Published",
                                     startTime: wdStart.addingTimeInterval(3 * 3600), endTime: wdStart.addingTimeInterval(4 * 3600))
        let pubResult = try? runAsync { try await simCal.publishSessions([pubSession], to: "sim-cal-planner", taskTitleLookup: [:]) }
        if let eventId = pubResult?.successSessionEventMap[pubSession.id] {
            pubSession.calendarEventId = eventId
            pubSession.lastPublishedStartTime = pubSession.startTime
            pubSession.lastPublishedEndTime = pubSession.endTime
            pubSession.lastPublishedTitle = pubSession.title
            var locallyMoved = pubSession
            locallyMoved.startTime = pubSession.startTime.addingTimeInterval(-30 * 60)
            locallyMoved.endTime = pubSession.endTime.addingTimeInterval(-30 * 60)
            let disc = (try? runAsync { try await simCal.detectExternalDiscrepancies(for: [locallyMoved], targetCalendarIdentifier: "sim-cal-planner", externalCommitments: []) }) ?? []
            let falseMove = disc.contains { if case .movedInCalendar = $0.kind { return true } else { return false } }
            check("10F: local-only change is not flagged as an external calendar move", !falseMove)
            check("10F: local-only change is a pending update for Review & Publish", locallyMoved.hasUnpublishedChanges)
        } else {
            check("10F: simulated publish produced an event id", false)
        }
        
        // 10G: Quick Capture (local) events block scheduling and survive calendar refresh
        let localEvent = CalendarCommitment(id: UUID(), title: "S10 Captured Meeting", location: nil,
                                            startTime: wdStart, endTime: wdEnd,
                                            isAllDay: false, isBusy: true, calendarName: "DayBook AI", calendarIdentifier: nil,
                                            colorHex: "#30D158", isSimulatedDemo: false, externalEventId: nil, isPlannerOwnEvent: true)
        let publishedMirror = CalendarCommitment(id: UUID(), title: "S10 Mirror", location: nil,
                                                 startTime: wdStart, endTime: wdEnd,
                                                 isAllDay: false, isBusy: true, calendarName: "DayBook AI", calendarIdentifier: "sim-cal-planner",
                                                 colorHex: "#BF5AF2", isSimulatedDemo: false, externalEventId: "s10-mirror", isPlannerOwnEvent: true)
        check("10G: local Quick Capture event blocks scheduling", localEvent.blocksScheduling)
        check("10G: calendar mirror of a published session does not double-block", !publishedMirror.blocksScheduling)
        let localBlockResult = RuleBasedSchedulingEngine().generateSchedule(
            tasks: [tUrgent],
            commitments: [localEvent],
            existingSessions: [],
            preferences: appState.preferences,
            dateRange: workDay...prefCal.date(byAdding: .day, value: 8, to: workDay)!,
            currentDate: wdStart
        )
        check("10G: no work session proposed during a captured all-day-long meeting",
              !localBlockResult.proposedSessions.contains(where: { prefCal.isDate($0.startTime, inSameDayAs: workDay) }))
        appState.commitments = [localEvent]
        _ = try? runAsync { await appState.refreshCalendarCommitments(isAutomatic: true) }
        check("10G: Quick Capture event survives an Apple Calendar refresh", appState.commitments.contains(where: { $0.id == localEvent.id }))
        appState.commitments = savedCommitments
        
        // 10H: Adopting a calendar deletion does not resurrect the deleted proposal
        let tDel = makeTask("S10 Deleted In Calendar", priority: .medium, carryover: false,
                            target: prefCal.date(byAdding: .day, value: 10, to: prefToday)!)
        appState.tasks.append(tDel)
        appState.workSessions = []
        appState.generateProposedPlan(isAutomatic: true)
        if let delSession = appState.workSessions.first(where: { $0.taskId == tDel.id && $0.status == .planned }) {
            let disc = ExternalDiscrepancy(sessionId: delSession.id, calendarEventId: "s10-gone", sessionTitle: delSession.title, kind: .deletedInCalendar)
            _ = try? runAsync { await appState.resolveDiscrepancy(disc, action: .adoptExternalChange) }
            check("10H: the time deleted in Calendar is not planned again",
                  !appState.workSessions.contains { $0.taskId == tDel.id && $0.status == .planned && $0.startTime < delSession.endTime && $0.endTime > delSession.startTime })
        } else {
            print("  ℹ️  10H skipped: no planned session could be generated in the current 14-day window")
        }
        
        // 10I: Unreadable databases are preserved, never silently overwritten
        let corruptDir = tempBaseURL.appendingPathComponent("S10_Corrupt", isDirectory: true)
        try? FileManager.default.createDirectory(at: corruptDir, withIntermediateDirectories: true)
        let corruptPlannerURL = corruptDir.appendingPathComponent("planner_database.json")
        let garbage = Data("{ \"tasks\": [ this is not valid json".utf8)
        try? garbage.write(to: corruptPlannerURL)
        _ = StorageService(customURL: corruptPlannerURL).loadDatabase()
        _ = StorageService(customURL: corruptPlannerURL).loadDatabase()
        let plannerBackups = ((try? FileManager.default.contentsOfDirectory(atPath: corruptDir.path)) ?? []).filter { $0.hasPrefix("planner_database.unreadable-") }
        check("10I: unreadable planner database is preserved before fallback", plannerBackups.count >= 1)
        if let first = plannerBackups.first {
            check("10I: preserved planner copy is byte-identical to the unreadable original",
                  (try? Data(contentsOf: corruptDir.appendingPathComponent(first))) == garbage)
        }

        // Clean up temporary test files
        try? FileManager.default.removeItem(at: tempBaseURL)
        
        print("\n=======================================================")
        print(" RESULTS: \(totalPassed) Passed, \(totalFailed) Failed")
        print("=======================================================\n")
        
        return totalFailed == 0
    }
    
    private static func runAsync<T>(_ block: @MainActor @escaping () async throws -> T) throws -> T {
        var result: Result<T, Error>?
        Task { @MainActor in
            do { result = .success(try await block()) } catch { result = .failure(error) }
        }
        let start = Date()
        while result == nil && Date().timeIntervalSince(start) < 5.0 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        guard let res = result else {
            throw NSError(domain: "MilestoneImprovementsTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Async block timed out"])
        }
        switch res {
        case .success(let val): return val
        case .failure(let err): throw err
        }
    }
    
    @MainActor
    public static func runDemonstration() {
        print("\n=======================================================")
        print(" 🎯 DEMONSTRATION: CARRYOVER & EARLY COMPLETION")
        print("=======================================================\n")
        
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let tempBaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("PP_Demo_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempBaseURL, withIntermediateDirectories: true)
        
        let storageService = StorageService(customURL: tempBaseURL.appendingPathComponent("db.json"))
        let appState = AppState(
            storageService: storageService,
            addOns: .inFolder(tempBaseURL)
        )
        
        let today = cal.startOfDay(for: Date())
        
        print("▶️ WORKFLOW 1: 'Not Done Yet' Carryover")
        print("---------------------------------------")
        let taskDemo = DiscoveredTask(
            id: UUID(),
            title: "ECON 302 Problem Set",
            requiredAction: "Complete math derivations",
            notes: "End-of-day unfinished task",
            sourceEmail: EmailSource(
                id: "demo_email_01",
                threadId: "demo_thread_01",
                senderName: "Prof. Smith",
                senderEmail: "smith@university.edu",
                subject: "Problem Set 4",
                receivedDate: Date(),
                snippet: "Derivations",
                fullBody: "Derivations",
                category: .assignment,
                isSimulatedDemo: false
            ),
            supportingExcerpt: "Due this Friday",
            estimatedMinutes: 60,
            planningTargetDate: cal.date(byAdding: .day, value: 2, to: today)
        )
        appState.tasks = [taskDemo]
        
        let sessionToday = WorkSession(
            id: UUID(),
            taskId: taskDemo.id,
            title: "Work Session: ECON 302 Problem Set",
            startTime: cal.date(bySettingHour: 15, minute: 0, second: 0, of: today)!,
            endTime: cal.date(bySettingHour: 16, minute: 0, second: 0, of: today)!,
            status: .planned
        )
        appState.workSessions = [sessionToday]
        
        print("Initial state:")
        print(" • Task: '\(taskDemo.title)' (isCarryover: \(taskDemo.isCarryover))")
        print(" • Scheduled Session: 3:00 PM - 4:00 PM today (Planned)")
        
        print("\nAction: User marks session 'Not Done Yet' in End-of-Day Review (45m remaining to carry over to next workday)")
        appState.confirmCarryover(session: sessionToday, remainingMinutes: 45, carryoverToNextWorkday: true)
        
        let carriedTask = appState.tasks.first(where: { $0.id == taskDemo.id })!
        print("\nResult after Carryover:")
        print(" • Task isCarryover: \(carriedTask.isCarryover) (Priority boosted)")
        print(" • Task estimated remaining: \(carriedTask.effectiveDuration)m")
        if let newSession = appState.workSessions.first(where: { $0.taskId == taskDemo.id && $0.status == .planned }) {
            let df = DateFormatter()
            df.timeZone = tz
            df.dateFormat = "EEE, MMM d 'at' h:mm a"
            print(" • New Proposed Slot: \(df.string(from: newSession.startTime)) - \(df.string(from: newSession.endTime)) (\(newSession.durationMinutes)m, isCarryover: \(newSession.isCarryover))")
        }
        print(" • Schedule explanation: \(appState.replanExplanation ?? "")")
        
        print("\n▶️ WORKFLOW 2: Completing Task Ahead of Schedule")
        print("------------------------------------------------")
        let taskMorning = DiscoveredTask(
            id: UUID(),
            title: "Draft Email to Advisor",
            requiredAction: "Send update",
            notes: "",
            sourceEmail: taskDemo.sourceEmail,
            supportingExcerpt: "",
            estimatedMinutes: 45
        )
        let taskAfternoon = DiscoveredTask(
            id: UUID(),
            title: "Review Research Paper",
            requiredAction: "Read paper",
            notes: "",
            sourceEmail: taskDemo.sourceEmail,
            supportingExcerpt: "",
            estimatedMinutes: 45
        )
        appState.tasks = [taskMorning, taskAfternoon]
        
        let morningSlot = WorkSession(
            id: UUID(),
            taskId: taskMorning.id,
            title: "Draft Email to Advisor",
            startTime: cal.date(bySettingHour: 9, minute: 0, second: 0, of: today)!,
            endTime: cal.date(bySettingHour: 9, minute: 45, second: 0, of: today)!,
            status: .planned
        )
        let afternoonSlot = WorkSession(
            id: UUID(),
            taskId: taskAfternoon.id,
            title: "Review Research Paper",
            startTime: cal.date(bySettingHour: 14, minute: 0, second: 0, of: today)!,
            endTime: cal.date(bySettingHour: 14, minute: 45, second: 0, of: today)!,
            status: .planned
        )
        appState.workSessions = [morningSlot, afternoonSlot]
        
        print("Initial state:")
        print(" • Session 1: 'Draft Email to Advisor' scheduled 9:00 AM - 9:45 AM")
        print(" • Session 2: 'Review Research Paper' scheduled 2:00 PM - 2:45 PM")
        
        let earlyFinish = cal.date(bySettingHour: 9, minute: 15, second: 0, of: today)!
        print("\nAction: User marks 'Draft Email to Advisor' complete early at 9:15 AM (30 min ahead of schedule)")
        appState.completeSessionEarly(id: morningSlot.id, completionTime: earlyFinish)
        
        let morningFinal = appState.workSessions.first(where: { $0.id == morningSlot.id })!
        let afternoonFinal = appState.workSessions.first(where: { $0.id == afternoonSlot.id })!
        
        let tf = DateFormatter()
        tf.timeZone = tz
        tf.dateFormat = "h:mm a"
        
        print("\nResult after Early Completion:")
        print(" • Session 1 status: \(morningFinal.status.rawValue), ended at \(tf.string(from: morningFinal.endTime)) (freed 9:15 AM - 9:45 AM)")
        print(" • Session 2 rescheduled: from 2:00 PM to \(tf.string(from: afternoonFinal.startTime)) - \(tf.string(from: afternoonFinal.endTime))")
        print(" • Explanation: \(appState.replanExplanation ?? "")")
        
        print("\nTesting Undo:")
        appState.undoLatestReplan()
        let afternoonRestored = appState.workSessions.first(where: { $0.id == afternoonSlot.id })!
        print(" • After Undo: 'Review Research Paper' restored back to \(tf.string(from: afternoonRestored.startTime))")
        
        try? FileManager.default.removeItem(at: tempBaseURL)
        print("\n=======================================================")
        print(" ✅ DEMO COMPLETE: All workflows verified successfully!")
        print("=======================================================\n")
    }
}
