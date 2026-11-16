import Foundation
import AppKit

@MainActor
public final class QuickCaptureTester {
    public static func runAllTests() -> Bool {
        print("\n=======================================================")
        print(" ⚡️ PERSONAL PLANNER QUICK CAPTURE TEST SUITE")
        print(" Text/Screenshot Ingestion, Task vs Event Classification")
        print("=======================================================\n")
        
        var passedCount = 0
        var totalCount = 0
        
        func check(_ name: String, _ condition: Bool, _ details: String = "") {
            totalCount += 1
            if condition {
                passedCount += 1
                print("  ✅ [PASS] \(name)")
            } else {
                print("  ❌ [FAIL] \(name)")
                if !details.isEmpty {
                    print("     Details: \(details)")
                }
            }
        }
        
        let pacificTZ = TimeZone(identifier: "America/Los_Angeles")!
        let refDate = Date(timeIntervalSince1970: 1793750400) // Tuesday, Nov 3, 2026, 16:00:00 PST
        
        let tempTestDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PP_QC_Test_\(UUID().uuidString)")
        let storageService = StorageService(customURL: tempTestDir.appendingPathComponent("database.json"))
        let qcStorage = QuickCaptureStorageService(customBaseURL: tempTestDir.appendingPathComponent("QuickCaptures"))
        let qcService = QuickCaptureService()
        
        let appState = AppState(
            storageService: storageService,
            calendarService: SimulatedCalendarService(),
            quickCaptureService: qcService,
            quickCaptureStorageService: qcStorage
        )
        appState.preferences.timeZoneIdentifier = "America/Los_Angeles"
        
        // ----------------------------------------------------
        // Stage 1: Task Classification, Explicit Timezone & Duration
        // ----------------------------------------------------
        print("\n--- Stage 1: Task Proposal & Explicit Timezone ---")
        qcService.simulationHandler = { text, img, ref, tz in
            return QuickCaptureExtractionResponse(
                proposals: [
                    QuickCaptureRawProposalItem(
                        proposalType: "task",
                        title: "Submit quarterly budget report",
                        requiredAction: "Finalize and submit quarterly budget spreadsheet",
                        deadlineIso: "2026-11-05T22:00:00Z", // 5:00 PM EST on Nov 5
                        dateOnlyString: nil,
                        originalDeadlineWording: "Thursday at 5:00 PM EST",
                        deadlineProvenance: "explicitDateTime",
                        timeZoneAssumption: "Explicit EST",
                        estimatedDurationMinutes: 120,
                        isDurationInferred: false,
                        eventStartIso: nil,
                        eventEndIso: nil,
                        isAllDay: false,
                        location: nil,
                        attendees: [],
                        originalTimingWording: nil,
                        isTentative: false,
                        supportingExcerpt: "Please submit the quarterly budget report by Thursday at 5:00 PM EST.",
                        notes: "Finalize and submit quarterly budget spreadsheet.",
                        inferredDetails: [],
                        isAmbiguous: false,
                        clarificationPrompt: nil
                    )
                ],
                reasoning: "Actionable report submission task with explicit Eastern deadline."
            )
        }
        
        appState.quickCaptureDraft.rawText = "Please submit the quarterly budget report by Thursday at 5:00 PM EST. Estimated effort: 2 hours."
        appState.quickCaptureDraft.referenceDate = refDate
        
        _ = try! runAsync { await appState.analyzeQuickCapture() }
        
        check("Extracted 1 proposal", appState.quickCaptureProposals.count == 1)
        let p1 = appState.quickCaptureProposals.first!
        check("Proposal classified as .task", p1.proposalType == .task)
        check("Title is 'Submit quarterly budget report'", p1.title == "Submit quarterly budget report")
        check("Explicit EST deadline resolved to 2026-11-05T22:00:00Z", p1.extractedDeadline == Date(timeIntervalSince1970: 1793916000))
        check("Provenance is .explicitDateTime", p1.deadlineProvenance == .explicitDateTime)
        check("Timezone assumption is 'Explicit EST'", p1.timeZoneAssumption == "Explicit EST")
        check("Duration is 120 min (2h)", p1.estimatedDurationMinutes == 120)
        
        // Save Task
        let tasksBefore = appState.tasks.count
        appState.saveQuickCaptureTask(proposal: p1)
        check("Task saved to planner database", appState.tasks.count == tasksBefore + 1)
        let savedTask = appState.tasks.last!
        check("Saved task has source category .quickCapture", savedTask.sourceEmail.category == .quickCapture)
        check("Saved task status is .ready", savedTask.status == .ready)
        
        // ----------------------------------------------------
        // Stage 2: Event Proposal & Attendance
        // ----------------------------------------------------
        print("\n--- Stage 2: Event Classification & Attendance ---")
        qcService.simulationHandler = { text, img, ref, tz in
            return QuickCaptureExtractionResponse(
                proposals: [
                    QuickCaptureRawProposalItem(
                        proposalType: "confirmedEvent",
                        title: "Economics Department Seminar",
                        requiredAction: nil,
                        deadlineIso: nil,
                        dateOnlyString: nil,
                        originalDeadlineWording: nil,
                        deadlineProvenance: nil,
                        timeZoneAssumption: "Assumed America/Los_Angeles",
                        estimatedDurationMinutes: nil,
                        isDurationInferred: nil,
                        eventStartIso: "2026-11-10T22:00:00Z", // 2:00 PM PST
                        eventEndIso: "2026-11-10T23:30:00Z",   // 3:30 PM PST
                        isAllDay: false,
                        location: "Room 402",
                        attendees: ["Dr. Henderson"],
                        originalTimingWording: "Tuesday Nov 10 from 2:00 PM to 3:30 PM",
                        isTentative: false,
                        supportingExcerpt: "Economics Department Seminar: Dr. Henderson on Macro Shocks. Tuesday Nov 10 from 2:00 PM to 3:30 PM in Room 402.",
                        notes: "Guest lecture by Dr. Henderson.",
                        inferredDetails: [],
                        isAmbiguous: false,
                        clarificationPrompt: nil
                    )
                ],
                reasoning: "Calendar seminar event with definite location and timing."
            )
        }
        
        appState.resetQuickCaptureDraft()
        appState.quickCaptureDraft.rawText = "Economics Department Seminar: Dr. Henderson on Macro Shocks. Tuesday Nov 10 from 2:00 PM to 3:30 PM in Room 402."
        appState.quickCaptureDraft.referenceDate = refDate
        
        _ = try! runAsync { await appState.analyzeQuickCapture() }
        
        check("Extracted 1 event proposal", appState.quickCaptureProposals.count == 1)
        let p2 = appState.quickCaptureProposals.first!
        check("Classified as .confirmedEvent", p2.proposalType == .confirmedEvent)
        check("Event start is 2026-11-10T22:00:00Z (2pm PST)", p2.eventStartTime == Date(timeIntervalSince1970: 1794348000))
        check("Location is 'Room 402'", p2.location == "Room 402")
        check("Attendees list includes 'Dr. Henderson'", p2.attendees.contains("Dr. Henderson"))
        check("Not tentative", !p2.isTentative)
        
        // Save Event
        let commitmentsBefore = appState.commitments.count
        appState.saveQuickCaptureEvent(proposal: p2)
        check("Commitment saved to planner", appState.commitments.count == commitmentsBefore + 1)
        let savedCommitment = appState.commitments.last!
        check("Commitment is marked isPlannerOwnEvent", savedCommitment.isPlannerOwnEvent)
        check("Commitment isBusy == true", savedCommitment.isBusy)
        
        // ----------------------------------------------------
        // Stage 3: Multiple Proposals (Task vs Meeting Distinction)
        // ----------------------------------------------------
        print("\n--- Stage 3: Multiple Proposals: Signup Task vs Meeting Event ---")
        qcService.simulationHandler = { text, img, ref, tz in
            return QuickCaptureExtractionResponse(
                proposals: [
                    QuickCaptureRawProposalItem(
                        proposalType: "task",
                        title: "Sign up to meet with Tim Richards",
                        requiredAction: "Submit office hours signup form",
                        deadlineIso: "2026-11-07T01:00:00Z", // Friday Nov 6 at 5:00 PM PST
                        dateOnlyString: nil,
                        originalDeadlineWording: "Friday at 5:00 PM",
                        deadlineProvenance: "explicitDateTime",
                        timeZoneAssumption: "Assumed America/Los_Angeles",
                        estimatedDurationMinutes: 15,
                        isDurationInferred: false,
                        eventStartIso: nil,
                        eventEndIso: nil,
                        isAllDay: false,
                        location: nil,
                        attendees: [],
                        originalTimingWording: nil,
                        isTentative: false,
                        supportingExcerpt: "Sign up to meet with Tim Richards by Friday at 5:00 PM.",
                        notes: "Fill out the Google form before Friday.",
                        inferredDetails: [],
                        isAmbiguous: false,
                        clarificationPrompt: nil
                    ),
                    QuickCaptureRawProposalItem(
                        proposalType: "confirmedEvent",
                        title: "Meeting with Tim Richards",
                        requiredAction: nil,
                        deadlineIso: nil,
                        dateOnlyString: nil,
                        originalDeadlineWording: nil,
                        deadlineProvenance: nil,
                        timeZoneAssumption: "Assumed America/Los_Angeles",
                        estimatedDurationMinutes: nil,
                        isDurationInferred: nil,
                        eventStartIso: "2026-11-10T22:00:00Z", // Next Tuesday 2:00 PM PST
                        eventEndIso: "2026-11-10T23:00:00Z",   // Next Tuesday 3:00 PM PST
                        isAllDay: false,
                        location: "Tim's Office",
                        attendees: ["Tim Richards"],
                        originalTimingWording: "next Tuesday from 2:00 PM to 3:00 PM",
                        isTentative: false,
                        supportingExcerpt: "The office hours meeting will be held next Tuesday from 2:00 PM to 3:00 PM in Tim's Office.",
                        notes: "Office hours slot.",
                        inferredDetails: [],
                        isAmbiguous: false,
                        clarificationPrompt: nil
                    )
                ],
                reasoning: "Content contains both an actionable deadline to sign up and the scheduled meeting itself."
            )
        }
        
        appState.resetQuickCaptureDraft()
        appState.quickCaptureDraft.rawText = "Sign up to meet with Tim Richards by Friday at 5:00 PM. The office hours meeting will be held next Tuesday from 2:00 PM to 3:00 PM in Tim's Office."
        appState.quickCaptureDraft.referenceDate = refDate
        
        _ = try! runAsync { await appState.analyzeQuickCapture() }
        
        check("Single capture yields exactly 2 proposals", appState.quickCaptureProposals.count == 2)
        let taskProp = appState.quickCaptureProposals.first(where: { $0.proposalType == .task })!
        let eventProp = appState.quickCaptureProposals.first(where: { $0.proposalType == .confirmedEvent })!
        
        check("Task deadline is Friday 5pm (NOT Tuesday)", taskProp.extractedDeadline == Date(timeIntervalSince1970: 1794013200))
        check("Event start time is Tuesday 2pm (NOT Friday)", eventProp.eventStartTime == Date(timeIntervalSince1970: 1794348000))
        check("Task title is 'Sign up to meet with Tim Richards'", taskProp.title == "Sign up to meet with Tim Richards")
        check("Event title is 'Meeting with Tim Richards'", eventProp.eventTitle == "Meeting with Tim Richards")
        
        // ----------------------------------------------------
        // Stage 4: Tentative Meeting Proposal
        // ----------------------------------------------------
        print("\n--- Stage 4: Tentative Meeting Proposal ---")
        qcService.simulationHandler = { text, img, ref, tz in
            return QuickCaptureExtractionResponse(
                proposals: [
                    QuickCaptureRawProposalItem(
                        proposalType: "tentativeEvent",
                        title: "Coffee Chat with Sarah",
                        requiredAction: nil,
                        deadlineIso: nil,
                        dateOnlyString: nil,
                        originalDeadlineWording: nil,
                        deadlineProvenance: nil,
                        timeZoneAssumption: "Assumed America/Los_Angeles",
                        estimatedDurationMinutes: nil,
                        isDurationInferred: nil,
                        eventStartIso: "2026-11-05T23:00:00Z", // Thursday 3:00 PM PST
                        eventEndIso: "2026-11-05T23:30:00Z",   // Thursday 3:30 PM PST (30m inferred)
                        isAllDay: false,
                        location: "Campus Café",
                        attendees: ["Sarah"],
                        originalTimingWording: "Thursday around 3pm",
                        isTentative: true,
                        supportingExcerpt: "Could we maybe sync up sometime Thursday around 3pm? Let me know if that works.",
                        notes: "Tentative coffee chat proposal.",
                        inferredDetails: ["Estimated 30m duration inferred"],
                        isAmbiguous: false,
                        clarificationPrompt: nil
                    )
                ],
                reasoning: "Tentative meeting suggestion requiring user confirmation."
            )
        }
        
        appState.resetQuickCaptureDraft()
        appState.quickCaptureDraft.rawText = "Could we maybe sync up sometime Thursday around 3pm? Let me know if that works."
        appState.quickCaptureDraft.referenceDate = refDate
        
        _ = try! runAsync { await appState.analyzeQuickCapture() }
        
        check("Classified as .tentativeEvent", appState.quickCaptureProposals.first?.proposalType == .tentativeEvent)
        let p4 = appState.quickCaptureProposals.first!
        check("isTentative is true", p4.isTentative)
        check("Inferred 30m duration labeled", p4.inferredDetails.contains(where: { $0.contains("30m") }))
        
        // Saving tentative event does NOT mark isBusy == true
        appState.saveQuickCaptureEvent(proposal: p4)
        let tentativeCommitment = appState.commitments.last!
        check("Tentative event saved with isBusy == false", !tentativeCommitment.isBusy)
        check("Tentative event title prefixed with [Tentative]", tentativeCommitment.title.hasPrefix("[Tentative]"))
        
        // ----------------------------------------------------
        // Stage 5: Ambiguous Dates & Planning Target Support
        // ----------------------------------------------------
        print("\n--- Stage 5: No Deadline in Text & Planning Target ---")
        qcService.simulationHandler = { text, img, ref, tz in
            return QuickCaptureExtractionResponse(
                proposals: [
                    QuickCaptureRawProposalItem(
                        proposalType: "task",
                        title: "Review slide 8 architecture diagrams",
                        requiredAction: "Review slide 8 architecture and decide on overhaul",
                        deadlineIso: nil,
                        dateOnlyString: nil,
                        originalDeadlineWording: "None stated",
                        deadlineProvenance: "unsupported",
                        timeZoneAssumption: "None",
                        estimatedDurationMinutes: 45,
                        isDurationInferred: true,
                        eventStartIso: nil,
                        eventEndIso: nil,
                        isAllDay: false,
                        location: nil,
                        attendees: [],
                        originalTimingWording: nil,
                        isTentative: false,
                        supportingExcerpt: "Whenever you get some breathing room this week or next, take a quick pass at slide 8.",
                        notes: "No deadline specified.",
                        inferredDetails: [],
                        isAmbiguous: true,
                        clarificationPrompt: "No deadline specified in text."
                    )
                ],
                reasoning: "Ambiguous request without deadline."
            )
        }
        
        appState.resetQuickCaptureDraft()
        appState.quickCaptureDraft.rawText = "Whenever you get some breathing room this week or next, take a quick pass at slide 8."
        appState.quickCaptureDraft.referenceDate = refDate
        
        _ = try! runAsync { await appState.analyzeQuickCapture() }
        
        var p5 = appState.quickCaptureProposals.first!
        check("Extracted deadline is nil", p5.extractedDeadline == nil)
        check("Provenance is .unsupported", p5.deadlineProvenance == .unsupported)
        
        // Set user planning target
        let targetDate = Date(timeIntervalSince1970: 1793916000) // Nov 5 2:00 PM PST
        p5.planningTargetDate = targetDate
        appState.saveQuickCaptureTask(proposal: p5)
        let targetTask = appState.tasks.last!
        check("Task saved with confirmed planning target", targetTask.planningTargetDate == targetDate)
        check("Original extracted deadline remains nil", targetTask.extractedDeadline == nil)
        check("Task is eligible for scheduling via planning target", targetTask.isEligibleForScheduling(asOf: refDate))
        
        // ----------------------------------------------------
        // Stage 6: Relative Weekday Resolution against Assumed Timezone
        // ----------------------------------------------------
        print("\n--- Stage 6: Relative 'Tomorrow at 6pm' against Configured Timezone ---")
        qcService.simulationHandler = { text, img, ref, tz in
            // "Tomorrow at 6pm" relative to refDate (Tuesday Nov 3 at 4pm) -> Wednesday Nov 4 at 6pm PST (2026-11-05T02:00:00Z)
            return QuickCaptureExtractionResponse(
                proposals: [
                    QuickCaptureRawProposalItem(
                        proposalType: "task",
                        title: "Server migration dry run",
                        requiredAction: "Execute dry run database migration",
                        deadlineIso: "2026-11-05T02:00:00Z", // 6pm Wednesday PST
                        dateOnlyString: nil,
                        originalDeadlineWording: "tomorrow at 6:00 PM",
                        deadlineProvenance: "relativeWindow",
                        timeZoneAssumption: "Assumed America/Los_Angeles",
                        estimatedDurationMinutes: 60,
                        isDurationInferred: false,
                        eventStartIso: nil,
                        eventEndIso: nil,
                        isAllDay: false,
                        location: nil,
                        attendees: [],
                        originalTimingWording: nil,
                        isTentative: false,
                        supportingExcerpt: "The server migration dry run will happen tomorrow at 6:00 PM.",
                        notes: "",
                        inferredDetails: [],
                        isAmbiguous: false,
                        clarificationPrompt: nil
                    )
                ],
                reasoning: "Relative timing resolved using reference date."
            )
        }
        
        appState.resetQuickCaptureDraft()
        appState.quickCaptureDraft.rawText = "The server migration dry run will happen tomorrow at 6:00 PM."
        appState.quickCaptureDraft.referenceDate = refDate
        
        _ = try! runAsync { await appState.analyzeQuickCapture() }
        
        let p6 = appState.quickCaptureProposals.first!
        check("Wednesday 6pm PST resolved to 2026-11-05T02:00:00Z", p6.extractedDeadline == Date(timeIntervalSince1970: 1793844000))
        check("Assumed timezone is America/Los_Angeles", p6.timeZoneAssumption == "Assumed America/Los_Angeles")
        
        // ----------------------------------------------------
        // Stage 7: Duplicate Detection & Non-Blocking Safety
        // ----------------------------------------------------
        print("\n--- Stage 7: Duplicate Detection ---")
        let dupCheck = QuickCaptureDuplicateDetector.checkDuplicate(
            proposal: p1,
            existingTasks: appState.tasks,
            existingCommitments: appState.commitments,
            timeZone: pacificTZ
        )
        check("Duplicate detected against previously saved task", dupCheck != nil && dupCheck!.contains("Submit quarterly budget report"))
        
        // Safe repeated save
        let taskCountBeforeReAdd = appState.tasks.count
        appState.saveQuickCaptureTask(proposal: p1)
        check("Duplicate task safely added without crashing", appState.tasks.count >= taskCountBeforeReAdd)
        
        // ----------------------------------------------------
        // Stage 8: Error Recovery & Draft Preservation
        // ----------------------------------------------------
        print("\n--- Stage 8: Error Recovery & Draft Preservation ---")
        qcService.simulationHandler = { text, img, ref, tz in
            throw AIServiceError(kind: .serverError, statusCode: 500, message: "Ollama had an internal error (500): rate limit test")
        }
        
        appState.resetQuickCaptureDraft()
        appState.quickCaptureDraft.rawText = "Important meeting notes that must not be lost."
        appState.quickCaptureDraft.referenceDate = refDate
        
        _ = try! runAsync { await appState.analyzeQuickCapture() }
        
        check("Analysis failure records error message", appState.quickCaptureError != nil && appState.quickCaptureError!.contains("rate limit"))
        check("User draft text remains 100% intact after error", appState.quickCaptureDraft.rawText == "Important meeting notes that must not be lost.")
        
        // ----------------------------------------------------
        // Stage 9: Source Content Retention & Local Deletion
        // ----------------------------------------------------
        print("\n--- Stage 9: Source Retention & Deletion ---")
        let testCapId = "test_cap_001"
        let retainedMeta = try? qcStorage.retainCapture(
            id: testCapId,
            text: "Retained secret project notes",
            imageData: nil,
            mimeType: nil
        )
        check("Source retention saves metadata file", retainedMeta != nil)
        let listBefore = qcStorage.listRetainedCaptures()
        check("Storage lists retained capture", listBefore.contains(where: { $0.id == testCapId }))
        
        qcStorage.deleteRetainedCapture(id: testCapId)
        let listAfter = qcStorage.listRetainedCaptures()
        check("Delete retained capture cleans up from disk", !listAfter.contains(where: { $0.id == testCapId }))
        
        // ----------------------------------------------------
        // Stage 10: Input Deletion & Draft Reset (Accidental Input Protection)
        // ----------------------------------------------------
        print("\n--- Stage 10: Deleting Accidentally Input PNG & Text ---")
        appState.quickCaptureDraft.rawText = "Accidentally pasted wrong sensitive text"
        let fakePngData = "FAKE_PNG_BYTES".data(using: .utf8)!
        appState.quickCaptureDraft.imageData = fakePngData
        appState.quickCaptureDraft.imageMimeType = "image/png"
        appState.quickCaptureDraft.contentType = .image
        
        check("Initial draft contains text and image", !appState.quickCaptureDraft.rawText.isEmpty && appState.quickCaptureDraft.imageData != nil)
        
        // Delete image / PNG
        appState.clearQuickCaptureImage()
        check("Deleting image removes PNG data", appState.quickCaptureDraft.imageData == nil)
        check("Deleting image removes image MIME type", appState.quickCaptureDraft.imageMimeType == nil)
        check("Draft text remains intact after deleting image", appState.quickCaptureDraft.rawText == "Accidentally pasted wrong sensitive text")
        
        // Delete text
        appState.clearQuickCaptureText()
        check("Deleting text leaves draft rawText completely empty", appState.quickCaptureDraft.rawText.isEmpty)
        
        // Reset everything
        appState.quickCaptureDraft.rawText = "Some other text"
        appState.quickCaptureDraft.imageData = fakePngData
        appState.resetQuickCaptureDraft()
        check("Reset draft wipes all text", appState.quickCaptureDraft.rawText.isEmpty)
        check("Reset draft wipes all image data", appState.quickCaptureDraft.imageData == nil)
        check("Reset draft wipes proposals", appState.quickCaptureProposals.isEmpty)
        
        // ----------------------------------------------------
        // Stage 11: Preferred Model Selection, Live Settings Changes & Fallback Protection
        // ----------------------------------------------------
        print("\n--- Stage 11: Preferred Model Selection & Settings Dynamic Switching ---")
        var attemptedModels: [String] = []
        qcService.onModelAttempt = { attemptedModels.append($0) }
        
        qcService.simulationHandler = { text, img, ref, tz in
            return QuickCaptureExtractionResponse(
                proposals: [
                    QuickCaptureRawProposalItem(
                        proposalType: "task",
                        title: "Test preferred model",
                        requiredAction: "Action",
                        deadlineIso: nil,
                        dateOnlyString: nil,
                        originalDeadlineWording: nil,
                        deadlineProvenance: "unsupported",
                        timeZoneAssumption: "Assumed America/Los_Angeles",
                        estimatedDurationMinutes: 30,
                        isDurationInferred: true,
                        eventStartIso: nil,
                        eventEndIso: nil,
                        isAllDay: false,
                        location: nil,
                        attendees: [],
                        originalTimingWording: nil,
                        isTentative: false,
                        supportingExcerpt: "Test",
                        notes: nil,
                        inferredDetails: [],
                        isAmbiguous: false,
                        clarificationPrompt: nil
                    )
                ],
                reasoning: "Tested model selection"
            )
        }
        
        // 11A: The configured local model is the one used
        appState.setOllamaModel("qwen3-vl:8b")
        appState.quickCaptureDraft.rawText = "Follow up with client tomorrow"
        attemptedModels.removeAll()
        
        _ = try! runAsync { await appState.analyzeQuickCapture() }
        
        check("Quick Capture uses the configured local model", attemptedModels.first == "qwen3-vl:8b")
        check("Active model indicator shows the local model", appState.quickCaptureActiveModel == "qwen3-vl:8b")
        
        // 11B: Settings change while Quick Capture draft remains open
        appState.setOllamaModel("gemma3:12b")
        attemptedModels.removeAll()
        
        _ = try! runAsync { await appState.analyzeQuickCapture() }
        
        check("Live Settings change immediately used without reopening window", attemptedModels.first == "gemma3:12b")
        check("Active model indicator updated", appState.quickCaptureActiveModel == "gemma3:12b")
        
        // 11C: A model that can't read images is explained clearly
        qcService.simulationHandler = { _, _, _, _ in
            throw OllamaClient.classify(statusCode: 400, data: Data("{\"error\":\"model does not support image input\"}".utf8), model: "llama3.1:8b")
        }
        _ = try! runAsync { await appState.analyzeQuickCapture() }
        check("Non-vision model error explains how to fix it", appState.quickCaptureError?.contains("can't read images") == true)
        
        // 11D: Ollama not running is explained clearly
        qcService.simulationHandler = { _, _, _, _ in throw OllamaClient.notRunningError() }
        _ = try! runAsync { await appState.analyzeQuickCapture() }
        check("Ollama not running explained", appState.quickCaptureError?.contains("Ollama isn't running") == true)
        
        // 11F: Stale error cleared when new attempt succeeds, draft preserved
        check("User draft text preserved through failure", appState.quickCaptureDraft.rawText == "Follow up with client tomorrow")
        qcService.simulationHandler = { _, _, _, _ in
            return QuickCaptureExtractionResponse(proposals: [], reasoning: "OK")
        }
        _ = try! runAsync { await appState.analyzeQuickCapture() }
        check("Stale error cleared upon new attempt", appState.quickCaptureError == nil)
        
        // Clean up temp directories
        try? FileManager.default.removeItem(at: tempTestDir)
        
        print("\n=======================================================")
        if passedCount == totalCount {
            print(" 🎉 ALL QUICK CAPTURE CHECKS PASSED (\(passedCount)/\(totalCount))!")
        } else {
            print(" ⚠️ SOME CHECKS FAILED (\(passedCount)/\(totalCount)).")
        }
        print("=======================================================\n")
        
        return passedCount == totalCount
    }
    
    private static func runAsync<T>(_ block: @MainActor @escaping () async throws -> T) throws -> T {
        var result: Result<T, Error>?
        Task { @MainActor in
            do {
                let val = try await block()
                result = .success(val)
            } catch {
                result = .failure(error)
            }
        }
        let start = Date()
        while result == nil && Date().timeIntervalSince(start) < 5.0 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        guard let res = result else {
            throw NSError(domain: "QuickCaptureTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Async block timed out"])
        }
        switch res {
        case .success(let val): return val
        case .failure(let err): throw err
        }
    }
}
