import Foundation

/// Recognizes a task DayBook AI has already found, whatever source it comes from again
/// (another email, a Canvas announcement, Gradescope), so syncing updates the original task
/// instead of adding a duplicate.
///
/// Two titles are the same task when, ignoring case, punctuation and filler words
/// ("submit", "reminder", "due"…), most of their words are shared and any numbers match
/// ("Lab 3" is never "Lab 4"). Tasks with the same name but due a week apart
/// (weekly quizzes) stay separate unless the new source says the deadline moved.
public enum TaskMemory {
    static let fillerWords: Set<String> = [
        "a", "an", "the", "to", "for", "of", "and", "or", "on", "in", "at", "by", "with", "your", "my", "our",
        "submit", "submission", "complete", "completing", "finish", "turn", "please", "reminder", "remember",
        "due", "deadline", "upcoming", "task", "todo", "do", "work", "new", "re", "fwd"
    ]

    /// Meaningful words of a title, lowercased.
    public static func keywords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !fillerWords.contains($0) }
    }

    /// How alike two titles are, from 0 to 1 (1 = same words). Numbers must agree.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let ta = Set(keywords(a)), tb = Set(keywords(b))
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        let na = ta.filter { $0.contains(where: \.isNumber) }, nb = tb.filter { $0.contains(where: \.isNumber) }
        // Numbers must agree: the shorter title's numbers must all appear in the other
        // ("Lab 3" fits "CS 420 Lab 3", never "Lab 4").
        if !na.isEmpty && !nb.isEmpty && !(na.isSubset(of: nb) || nb.isSubset(of: na)) { return 0 }
        let shared = Double(ta.intersection(tb).count)
        let jaccard = shared / Double(ta.union(tb).count)
        // One title containing the other ("Lab 3" / "CS 420 Lab 3 Raft Consensus") counts if it has 2+ words.
        let containment = min(ta.count, tb.count) >= 2 ? shared / Double(min(ta.count, tb.count)) : 0
        return max(jaccard, containment >= 1 ? 0.85 : containment * 0.8)
    }

    public static let matchThreshold = 0.6

    /// Index of the existing task that `title` describes, if any.
    /// - deadline: the new source's deadline; tasks due more than 3 days apart are different
    ///   occurrences unless `isDeadlineChange` (the source says the deadline moved).
    public static func findMatch(title: String, action: String = "", deadline: Date?, isDeadlineChange: Bool = false,
                                 in tasks: [DiscoveredTask]) -> Int? {
        var best: (index: Int, score: Double)? = nil
        for (i, task) in tasks.enumerated() {
            var score = max(similarity(title, task.title), similarity(title, task.displayTitle))
            if !action.isEmpty { score = max(score, similarity(action, task.requiredAction) * 0.9) }
            guard score >= matchThreshold else { continue }
            if let new = deadline, let old = task.effectiveDeadline ?? task.extractedDeadline,
               abs(new.timeIntervalSince(old)) > 3 * 86400, !isDeadlineChange {
                continue
            }
            if best == nil || score > best!.score { best = (i, score) }
        }
        return best?.index
    }

    /// Whether `title` is a task the user already dismissed and cleared.
    public static func matchesDismissed(title: String, in records: [DismissedTaskRecord]) -> Bool {
        records.contains { similarity(title, $0.title) >= 0.75 }
    }

    /// Folds new information into an existing task and records an "Updated" reminder.
    /// Returns what changed (empty when the source added nothing new). Never touches a
    /// user-set deadline, completed or dismissed tasks.
    @discardableResult
    public static func merge(into task: inout DiscoveredTask, deadline: Date?, details: String, source: String,
                             now: Date, timeZone: TimeZone) -> [String] {
        guard task.status != .completed, task.status != .dismissed, !task.isDismissed else { return [] }
        var changes: [String] = []
        let df = DateFormatter()
        df.dateFormat = "MMM d, h:mm a"
        df.timeZone = timeZone

        if let new = deadline, task.userOverriddenDeadline == nil, task.planningTargetDate == nil {
            if let old = task.extractedDeadline, task.isDeadlineSupportedByEmail {
                if abs(new.timeIntervalSince(old)) > 60 {
                    task.extractedDeadline = new
                    changes.append("Due date moved to \(df.string(from: new))")
                }
            } else {
                task.extractedDeadline = new
                task.isDeadlineSupportedByEmail = true
                changes.append("Due date set to \(df.string(from: new))")
            }
            if !changes.isEmpty {
                task.originalDeadlineWording = df.string(from: new)
                task.deadlineUpdateNote = "\(changes.last!) (from \(source))"
            }
        }

        let cleaned = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count >= 12, !isKnown(cleaned, in: task) {
            let day = DateFormatter()
            day.dateFormat = "MMM d"
            day.timeZone = timeZone
            task.notes += (task.notes.isEmpty ? "" : "\n\n") + "Update from \(source) (\(day.string(from: now))): \(cleaned)"
            changes.append("New details from \(source)")
        }

        if !changes.isEmpty {
            task.updatedAt = now
            task.syncUpdate = TaskSyncUpdate(date: now, summary: changes.joined(separator: " · "), source: source)
        }
        return changes
    }

    /// Whether the text is already in the task (so repeating the same reminder adds nothing).
    static func isKnown(_ text: String, in task: DiscoveredTask) -> Bool {
        func norm(_ s: String) -> String { keywords(s).joined(separator: " ") }
        let n = norm(text)
        guard !n.isEmpty else { return true }
        return [task.notes, task.supportingExcerpt, task.requiredAction, task.title].contains { norm($0).contains(n) }
    }
}
