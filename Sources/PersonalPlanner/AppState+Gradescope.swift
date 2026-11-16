import Foundation

/// Gradescope integration (no public student API): assignments are read through the user's
/// signed-in Gradescope tab in Safari/Chrome/Arc and imported with the same rules as Canvas
/// (stable IDs, due-date updates, submitted → done, dismissed stays gone, no Canvas duplicates).
extension AppState {
    public var isGradescopeConnected: Bool { preferences.gradescopeBrowser != nil }

    private func readGradescope(_ browser: CanvasBrowser) async throws -> [GradescopeAssignment] {
        if let override = gradescopeReadOverride { return try await override(browser) }
        return try await GradescopeReader.read(browser: browser)
    }

    /// Connects through a Gradescope tab in `browser` (nil: search the open browsers), then syncs.
    public func connectGradescope(_ browser: CanvasBrowser?) async {
        gradescopeErrorMessage = nil
        var candidates: [CanvasBrowser] = browser.map { [$0] } ?? CanvasBrowser.allCases.filter { $0.isInstalled && $0.isRunning }
        if gradescopeReadOverride != nil, browser == nil { candidates = [.safari] }
        guard !candidates.isEmpty else {
            gradescopeErrorMessage = "Open Gradescope in Safari, Chrome or Arc and sign in, then try again."
            return
        }
        var firstProblem: String? = nil
        for candidate in candidates {
            gradescopeStatusMessage = "Looking for Gradescope in \(candidate.displayName)..."
            do {
                _ = try await readGradescope(candidate)
                preferences.gradescopeBrowser = candidate
                saveDatabase()
                gradescopeStatusMessage = "Connected to Gradescope through \(candidate.displayName). Keep a Gradescope tab open there when you sync."
                await syncGradescope()
                return
            } catch {
                let message = Self.gradescopeMessage(for: error, browser: candidate)
                if firstProblem == nil || message.contains("allowed") || message.contains("signed in") { firstProblem = message }
            }
        }
        gradescopeStatusMessage = nil
        gradescopeErrorMessage = firstProblem
    }

    public func disconnectGradescope() {
        preferences.gradescopeBrowser = nil
        gradescopeStatusMessage = nil
        gradescopeErrorMessage = nil
        saveDatabase()
    }

    /// Reads current Gradescope courses and updates tasks.
    public func syncGradescope(now: Date = Date()) async {
        let tracking = beginNewTaskTracking()
        defer { endNewTaskTracking(tracking) }
        guard let browser = preferences.gradescopeBrowser, !isSyncingGradescope else { return }
        isSyncingGradescope = true
        defer { isSyncingGradescope = false }
        gradescopeErrorMessage = nil
        gradescopeStatusMessage = "Reading Gradescope in \(browser.displayName)..."
        do {
            let assignments = try await readGradescope(browser)
            let counts = importCanvasDueItems(assignments.map(GradescopeReader.dueItem), now: now, from: .gradescope)
            await estimateLMSTaskTimes(now: now)
            preferences.lastGradescopeSyncDate = now
            recalculateSchedule()
            saveDatabase()
            let courses = Set(assignments.map(\.courseId)).count
            var parts = ["\(assignments.count) assignment\(assignments.count == 1 ? "" : "s") in \(courses) course\(courses == 1 ? "" : "s")",
                         "\(counts.created) new task\(counts.created == 1 ? "" : "s")"]
            if counts.updated > 0 { parts.append("\(counts.updated) due date\(counts.updated == 1 ? "" : "s") updated") }
            if counts.completed > 0 { parts.append("\(counts.completed) marked done (submitted)") }
            gradescopeStatusMessage = "Gradescope: " + parts.joined(separator: ", ") + "."
            if assignments.isEmpty {
                gradescopeErrorMessage = "No assignments found in your current Gradescope courses. If you do have some, Gradescope may have changed its page layout."
            }
        } catch {
            gradescopeStatusMessage = nil
            gradescopeErrorMessage = Self.gradescopeMessage(for: error, browser: browser)
        }
    }

    static func gradescopeMessage(for error: Error, browser: CanvasBrowser) -> String {
        let message = error.localizedDescription
        if message.contains("JavaScript from Apple Events") { return message + " " + browser.enableJavaScriptHint }
        return message
    }
}
