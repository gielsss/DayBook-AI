import Foundation

/// Checks time estimates against the real local model (needs Ollama running).
/// Run with: DayBookAI --eval-estimates [model]
/// Each case is a realistic assignment with a range a typical student would need; the ranges are
/// judgment calls, so read the output as a sanity check, not a score to optimize.
@MainActor
enum EstimateEvaluator {
    struct Case {
        let title: String
        let points: Double?
        let details: String?
        let range: ClosedRange<Int>
        let expectLowConfidence: Bool
    }

    static let cases: [Case] = [
        Case(title: "Seminar Series Reflection 3", points: 5, details: nil, range: 20...90, expectLowConfidence: true),
        Case(title: "Seminar Series Reflection 3", points: 5,
             details: "Instructions:\nWrite a one-page reflection (about 400 words) on this week's seminar talk: summarize the main argument and pose one question for the speaker.",
             range: 30...90, expectLowConfidence: false),
        Case(title: "Problem Set 4", points: 20,
             details: "Instructions:\nComplete problems 1-8 from chapter 5. Show all derivations. Problems 6-8 require short proofs.\n\nHanded in as: upload",
             range: 150...420, expectLowConfidence: false),
        Case(title: "Final Project", points: 100, details: nil, range: 240...600, expectLowConfidence: true),
        Case(title: "Final Project", points: 100,
             details: "Handed in as: upload\n\nAttached file \"final_project.pdf\":\nReplicate Table 2 of the assigned paper in a Jupyter notebook.\nEstimate three regressions, add two robustness checks, and interpret the results.\nSubmit the notebook and an 8-10 page report with figures.",
             range: 480...600, expectLowConfidence: false),
        Case(title: "Reading Quiz 5", points: 10,
             details: "Instructions:\n10 multiple-choice questions on chapter 6. Time limit: 20 minutes. One attempt.",
             range: 15...45, expectLowConfidence: false),
        Case(title: "Discussion Post: Week 6", points: 10,
             details: "Instructions:\nPost a 250-word response to the prompt, then reply to two classmates (50+ words each).",
             range: 30...90, expectLowConfidence: false),
        Case(title: "Lab 4: Linked Lists", points: 50,
             details: "Instructions:\nImplement a singly linked list in C with insert, delete and search. Write unit tests for each function and a short README.\n\nRubric:\n- Correctness (30 pts)\n- Tests (15 pts)\n- Style (5 pts)",
             range: 150...420, expectLowConfidence: false),
        Case(title: "Argumentative Essay", points: 100,
             details: "Instructions:\nWrite a 1500-word argumentative essay on a trade policy question of your choice. Use at least five scholarly sources and Chicago citations.",
             range: 300...600, expectLowConfidence: false),
        Case(title: "Reading Response: Chapter 7", points: 5,
             details: "Instructions:\nRead chapter 7 (pages 180-215) and write a 200-word response.",
             range: 75...180, expectLowConfidence: false)
    ]

    static func run(model requested: String?) async -> Bool {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DayBook_Eval_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = AppState(storageService: StorageService(customURL: dir.appendingPathComponent("db.json")), addOns: .inFolder(dir))
        let model = requested ?? app.ollamaModel
        let service = OllamaExtractionService()
        // Other assignments in the course, so points can be compared like in the app.
        let filler = [10.0, 20, 20, 10].enumerated().map { i, p in
            var t = DiscoveredTask(title: "Homework \(i + 1)", sourceEmail: source("filler-\(i)"), estimatedMinutes: 60, status: .completed)
            t.notes = "Course: ECON 101\nPoints: \(AppState.pointsText(p))"
            return t
        }
        app.tasks = filler
        print("\nEstimates from \(model) (\(cases.count) assignments)\n")
        var inRange = 0, confidenceRight = 0, failures = 0
        for (i, c) in cases.enumerated() {
            var task = DiscoveredTask(title: c.title, sourceEmail: source("case-\(i)"), estimatedMinutes: 60, status: .ready)
            task.notes = "Course: ECON 101" + (c.points.map { "\nPoints: \(AppState.pointsText($0))" } ?? "")
            task.assignmentDetails = c.details
            task.requiredAction = "Submit assignment: \(c.title)"
            let started = Date()
            do {
                guard let e = try await service.estimateTaskMinutes(title: c.title, context: app.estimateContext(for: task),
                                                                     baseURL: OllamaDefaults.baseURL, model: model) else { continue }
                let hasInstructions = (c.details ?? "").count >= 50
                let minutes = hasInstructions ? e.plannedMinutes : max(e.plannedMinutes, AppState.ruleOfThumbMinutes(for: task))
                let confidence = hasInstructions ? (e.confidence ?? "medium") : "low"
                let ok = c.range.contains(minutes)
                let confOK = (confidence == "low") == c.expectLowConfidence
                inRange += ok ? 1 : 0
                confidenceRight += confOK ? 1 : 0
                let label = c.title + (c.details == nil ? " (title only)" : "")
                print("\(ok ? "✅" : "❌") \(label.padding(toLength: 42, withPad: " ", startingAt: 0)) \(AppState.durationText(minutes).padding(toLength: 10, withPad: " ", startingAt: 0)) expected \(AppState.durationText(c.range.lowerBound))–\(AppState.durationText(c.range.upperBound)), \(confidence)\(confOK ? "" : " (!)") · \(Int(Date().timeIntervalSince(started)))s")
                print("     \(e.reason)")
            } catch {
                failures += 1
                print("⚠️ \(c.title): \(error.localizedDescription)")
                if let ai = error as? AIServiceError, ai.isFatalForScan { break }
            }
        }
        print("\nIn range: \(inRange)/\(cases.count) · confidence as expected: \(confidenceRight)/\(cases.count)\(failures > 0 ? " · \(failures) failed" : "")\n")
        return failures == 0
    }

    private static func source(_ id: String) -> EmailSource {
        EmailSource(id: id, threadId: id, senderName: "ECON 101", senderEmail: "canvas@local", subject: id, receivedDate: Date(),
                    snippet: "", fullBody: "", category: .canvas, isSimulatedDemo: false)
    }
}
