import Foundation
import CryptoKit

/// Something in Canvas with a due date (assignment, quiz, graded discussion, to-do page, planner note).
public struct CanvasDueItem: Equatable {
    public let key: String            // stable, e.g. "assignment-123"
    public let kind: String           // Canvas plannable_type
    public let title: String
    public let courseName: String
    public let dueAt: Date?
    public let pointsPossible: Double?
    public let htmlURL: String?
    public let isSubmitted: Bool
    public let isMissing: Bool
    public var descriptionText: String
    /// How it's handed in ("online_upload", "online_text_entry", "online_quiz", "on_paper", ...).
    public var submissionTypes: [String] = []
    /// Grading rubric criteria, one per line.
    public var rubricText: String = ""
    /// Canvas files linked from the instructions (ids), and what could be read from them.
    public var attachmentFileIds: [Int] = []
    public var attachmentText: String = ""
    public var attachmentNames: [String] = []
    public var unreadableAttachments: [String] = []
}

/// Free text that may contain tasks (announcement, inbox message, discussion, feedback, syllabus).
public struct CanvasTextItem: Equatable {
    public let key: String            // stable per item, e.g. "announcement-55"
    public let kind: String           // "Announcement", "Message", "Discussion", "Feedback", "Syllabus"
    public let title: String
    public let courseName: String
    public let author: String
    public let postedAt: Date
    /// Changes whenever the content changes, so edited items are re-analyzed and unchanged ones never are.
    public let version: String
    public let body: String
    public let htmlURL: String?
}

/// A dated course event (exam, lab, office hours) from the Canvas calendar.
public struct CanvasEvent: Equatable {
    public let key: String
    public let title: String
    public let courseName: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
}

public struct CanvasSnapshot {
    public var userName: String = ""
    public var dueItems: [CanvasDueItem] = []
    public var textItems: [CanvasTextItem] = []
    public var events: [CanvasEvent] = []
    /// Parts of Canvas that couldn't be read this time (the rest of the sync still runs).
    public var problems: [String] = []
}

@MainActor
public protocol CanvasReading {
    func readEverything(client: CanvasClient, now: Date) async throws -> CanvasSnapshot
}

/// Reads a student's Canvas content through read-only API calls.
@MainActor
public final class CanvasReader: CanvasReading {
    public static let lookBackDays = 14
    public static let lookAheadDays = 90
    public static let maxConversations = 25

    /// Reads files attached to upcoming assignments (nil: attachments are skipped).
    public var attachmentReader: CanvasAttachmentReader?
    public static let maxFilesPerItem = 3
    public static let maxFilesPerSync = 12

    public init(attachmentReader: CanvasAttachmentReader? = nil) {
        self.attachmentReader = attachmentReader
    }

    public func readEverything(client: CanvasClient, now: Date = Date()) async throws -> CanvasSnapshot {
        var snapshot = CanvasSnapshot()
        let since = now.addingTimeInterval(-Double(Self.lookBackDays) * 86400)
        let until = now.addingTimeInterval(Double(Self.lookAheadDays) * 86400)
        let iso = ISO8601DateFormatter()

        // Who am I? Also proves the sign-in works; failures here stop the sync.
        let me = try await client.get("/api/v1/users/self") as? [String: Any]
        snapshot.userName = (me?["short_name"] as? String) ?? (me?["name"] as? String) ?? ""

        // Each section below is independent: a failure is noted and the rest continues,
        // except an expired sign-in, which stops everything.
        func attempt(_ label: String, _ body: () async throws -> Void) async throws {
            do { try await body() } catch let e as CanvasError where e.kind == .signInRequired || e.kind == .setup {
                throw e
            } catch {
                snapshot.problems.append("\(label): \(error.localizedDescription)")
            }
        }

        var courses: [Int: String] = [:]
        try await attempt("Courses") {
            for c in try await client.getAll("/api/v1/courses", query: [URLQueryItem(name: "enrollment_state", value: "active")]) {
                if let id = Self.int(c["id"]), let name = c["name"] as? String { courses[id] = name }
            }
        }
        let contextCodes = courses.keys.sorted().map { URLQueryItem(name: "context_codes[]", value: "course_\($0)") }

        // 1. Everything with a due date, with submission status (Canvas "planner").
        try await attempt("Assignments & quizzes") {
            let items = try await client.getAll("/api/v1/planner/items", query: [
                URLQueryItem(name: "start_date", value: iso.string(from: since)),
                URLQueryItem(name: "end_date", value: iso.string(from: until))
            ])
            snapshot.dueItems = items.compactMap { Self.dueItem(from: $0, courses: courses) }
        }

        // 2. Assignment instructions, rubric and how it's handed in, to improve time estimates and catch extra requirements.
        try await attempt("Assignment descriptions") {
            var details: [String: [String: Any]] = [:]
            for courseId in courses.keys.sorted() {
                for a in try await client.getAll("/api/v1/courses/\(courseId)/assignments", query: [URLQueryItem(name: "bucket", value: "future")]) {
                    if let id = Self.int(a["id"]) { details["assignment-\(id)"] = a }
                }
            }
            for i in snapshot.dueItems.indices {
                guard let a = details[snapshot.dueItems[i].key] else { continue }
                Self.applyAssignmentDetails(a, to: &snapshot.dueItems[i])
            }
        }

        // 2b. Files linked from upcoming assignments (instructions, rubrics): their text helps estimate time.
        if let files = attachmentReader {
            try await attempt("Attached files") {
                var budget = Self.maxFilesPerSync
                for i in snapshot.dueItems.indices {
                    let item = snapshot.dueItems[i]
                    guard !item.isSubmitted, (item.dueAt ?? .distantPast) > now, !item.attachmentFileIds.isEmpty else { continue }
                    var texts: [String] = []
                    for fileId in item.attachmentFileIds.prefix(Self.maxFilesPerItem) where budget > 0 {
                        budget -= 1
                        let info: [String: Any]
                        do {
                            info = (try await client.get("/api/v1/files/\(fileId)") as? [String: Any]) ?? [:]
                        } catch let e as CanvasError where e.kind == .signInRequired || e.kind == .setup {
                            throw e
                        } catch {
                            snapshot.dueItems[i].unreadableAttachments.append("file \(fileId)")
                            continue
                        }
                        switch await files.read(fileId: fileId, info: info) {
                        case .text(let name, let text):
                            snapshot.dueItems[i].attachmentNames.append(name)
                            texts.append("Attached file \"\(name)\":\n\(text)")
                        case .unreadable(let name, _):
                            snapshot.dueItems[i].unreadableAttachments.append(name)
                        }
                    }
                    snapshot.dueItems[i].attachmentText = texts.joined(separator: "\n\n")
                }
            }
        }

        // 3. Announcements.
        if !contextCodes.isEmpty {
            try await attempt("Announcements") {
                let list = try await client.getAll("/api/v1/announcements", query: contextCodes + [
                    URLQueryItem(name: "start_date", value: iso.string(from: since)),
                    URLQueryItem(name: "end_date", value: iso.string(from: now))
                ])
                for a in list {
                    guard let id = Self.int(a["id"]) else { continue }
                    let courseId = Self.courseId(fromContextCode: a["context_code"] as? String)
                    let posted = Self.date(a["posted_at"]) ?? Self.date(a["created_at"]) ?? now
                    let body = CanvasText.plain(fromHTML: a["message"] as? String ?? "")
                    snapshot.textItems.append(CanvasTextItem(
                        key: "announcement-\(id)", kind: "Announcement",
                        title: a["title"] as? String ?? "Announcement",
                        courseName: courseId.flatMap { courses[$0] } ?? "",
                        author: (a["author"] as? [String: Any])?["display_name"] as? String ?? (a["user_name"] as? String ?? ""),
                        postedAt: posted,
                        version: CanvasText.fingerprint(body),
                        body: body, htmlURL: a["html_url"] as? String))
                }
            }
        }

        // 4. Canvas Inbox conversations (full message bodies).
        try await attempt("Inbox") {
            let conversations = try await client.getAll("/api/v1/conversations", query: [URLQueryItem(name: "scope", value: "inbox")])
            let recent = conversations
                .filter { (Self.date($0["last_message_at"]) ?? .distantPast) >= since }
                .prefix(Self.maxConversations)
            for c in recent {
                guard let id = Self.int(c["id"]) else { continue }
                let detail = try await client.get("/api/v1/conversations/\(id)") as? [String: Any] ?? [:]
                let participants = Dictionary(uniqueKeysWithValues: ((detail["participants"] as? [[String: Any]]) ?? []).compactMap { p -> (Int, String)? in
                    guard let pid = Self.int(p["id"]), let name = p["name"] as? String else { return nil }
                    return (pid, name)
                })
                let messages = ((detail["messages"] as? [[String: Any]]) ?? []).sorted { (Self.date($0["created_at"]) ?? .distantPast) < (Self.date($1["created_at"]) ?? .distantPast) }
                let body = messages.map { m in
                    let who = Self.int(m["author_id"]).flatMap { participants[$0] } ?? "Someone"
                    return "\(who): \(m["body"] as? String ?? "")"
                }.joined(separator: "\n\n")
                let last = messages.last
                snapshot.textItems.append(CanvasTextItem(
                    key: "conversation-\(id)", kind: "Message",
                    title: c["subject"] as? String ?? "Canvas message",
                    courseName: c["context_name"] as? String ?? "",
                    author: Self.int(last?["author_id"]).flatMap { participants[$0] } ?? "",
                    postedAt: Self.date(c["last_message_at"]) ?? now,
                    version: CanvasText.fingerprint(body),
                    body: body, htmlURL: "/conversations/\(id)"))
            }
        }

        // 5. Discussions and instructor feedback from the activity stream.
        try await attempt("Discussions & feedback") {
            let stream = try await client.getAll("/api/v1/users/self/activity_stream", query: [URLQueryItem(name: "only_active_courses", value: "true")])
            for s in stream {
                let type = s["type"] as? String ?? ""
                let updated = Self.date(s["updated_at"]) ?? Self.date(s["created_at"]) ?? now
                guard updated >= since, let id = Self.int(s["id"]) else { continue }
                let courseName = Self.int(s["course_id"]).flatMap { courses[$0] } ?? ""
                if type == "DiscussionTopic" {
                    let body = CanvasText.plain(fromHTML: s["message"] as? String ?? "")
                    snapshot.textItems.append(CanvasTextItem(
                        key: "discussion-\(Self.int(s["discussion_topic_id"]) ?? id)", kind: "Discussion",
                        title: s["title"] as? String ?? "Discussion", courseName: courseName, author: "",
                        postedAt: updated, version: CanvasText.fingerprint(body), body: body, htmlURL: s["html_url"] as? String))
                } else if type == "Submission", let comments = s["submission_comments"] as? [[String: Any]], !comments.isEmpty {
                    let assignmentName = (s["assignment"] as? [String: Any])?["name"] as? String ?? "an assignment"
                    let body = comments.map { "\($0["author_name"] as? String ?? "Instructor"): \($0["comment"] as? String ?? "")" }.joined(separator: "\n")
                    snapshot.textItems.append(CanvasTextItem(
                        key: "feedback-\(Self.int(s["assignment_id"]) ?? id)", kind: "Feedback",
                        title: "Feedback on \(assignmentName)", courseName: courseName, author: comments.last?["author_name"] as? String ?? "",
                        postedAt: updated, version: CanvasText.fingerprint(body), body: body, htmlURL: s["html_url"] as? String))
                }
            }
        }

        // 6. Syllabi (readings and prep that aren't separate assignments).
        try await attempt("Syllabi") {
            for courseId in courses.keys.sorted() {
                let course = try await client.get("/api/v1/courses/\(courseId)", query: [URLQueryItem(name: "include[]", value: "syllabus_body")]) as? [String: Any]
                let body = CanvasText.plain(fromHTML: course?["syllabus_body"] as? String ?? "")
                guard !body.isEmpty else { continue }
                snapshot.textItems.append(CanvasTextItem(
                    key: "syllabus-\(courseId)", kind: "Syllabus", title: "Syllabus", courseName: courses[courseId] ?? "",
                    author: "", postedAt: now, version: CanvasText.fingerprint(body), body: body,
                    htmlURL: "/courses/\(courseId)/assignments/syllabus"))
            }
        }

        // 7. Course calendar events (exams, labs).
        if !contextCodes.isEmpty {
            try await attempt("Course events") {
                let list = try await client.getAll("/api/v1/calendar_events", query: contextCodes + [
                    URLQueryItem(name: "type", value: "event"),
                    URLQueryItem(name: "start_date", value: iso.string(from: now)),
                    URLQueryItem(name: "end_date", value: iso.string(from: now.addingTimeInterval(30 * 86400)))
                ])
                for e in list {
                    guard let id = Self.int(e["id"]), let start = Self.date(e["start_at"]) else { continue }
                    let courseId = Self.courseId(fromContextCode: e["context_code"] as? String)
                    snapshot.events.append(CanvasEvent(
                        key: "event-\(id)", title: e["title"] as? String ?? "Course event",
                        courseName: courseId.flatMap { courses[$0] } ?? "",
                        start: start, end: Self.date(e["end_at"]) ?? start.addingTimeInterval(3600),
                        isAllDay: e["all_day"] as? Bool ?? false,
                        location: (e["location_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }))
                }
            }
        }

        return snapshot
    }

    // MARK: Parsing helpers

    nonisolated static func dueItem(from item: [String: Any], courses: [Int: String]) -> CanvasDueItem? {
        let type = item["plannable_type"] as? String ?? ""
        guard ["assignment", "quiz", "discussion_topic", "wiki_page", "planner_note"].contains(type),
              let plannableId = int(item["plannable_id"]) else { return nil }
        let plannable = item["plannable"] as? [String: Any] ?? [:]
        let title = (plannable["title"] as? String) ?? (plannable["name"] as? String) ?? "Canvas item"
        let due = date(plannable["due_at"]) ?? date(plannable["todo_date"]) ?? date(item["plannable_date"])
        var submitted = false
        var missing = false
        if let subs = item["submissions"] as? [String: Any] {
            submitted = (subs["submitted"] as? Bool ?? false) || (subs["excused"] as? Bool ?? false)
            missing = subs["missing"] as? Bool ?? false
        }
        if let override = item["planner_override"] as? [String: Any], override["marked_complete"] as? Bool == true {
            submitted = true
        }
        let courseName = int(item["course_id"]).flatMap { courses[$0] } ?? (item["context_name"] as? String ?? "")
        // Planner links are usually paths ("/courses/5/assignments/7"); they're resolved against the Canvas
        // address when the task is made. Build one from the course when Canvas leaves it out.
        var url = (item["html_url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if url == nil, let courseId = int(item["course_id"]) {
            switch type {
            case "assignment": url = "/courses/\(courseId)/assignments/\(plannableId)"
            case "quiz": url = "/courses/\(courseId)/quizzes/\(plannableId)"
            case "discussion_topic": url = "/courses/\(courseId)/discussion_topics/\(plannableId)"
            default: break
            }
        }
        return CanvasDueItem(
            key: "\(type == "quiz" ? "quiz" : type == "discussion_topic" ? "discussion" : type == "wiki_page" ? "page" : type == "planner_note" ? "note" : "assignment")-\(plannableId)",
            kind: type, title: title, courseName: courseName, dueAt: due,
            pointsPossible: plannable["points_possible"] as? Double,
            htmlURL: url, isSubmitted: submitted, isMissing: missing,
            descriptionText: CanvasText.plain(fromHTML: plannable["details"] as? String ?? ""))
    }

    /// Instructions, submission types, rubric and linked file ids from an assignment (Canvas `/assignments`).
    nonisolated static func applyAssignmentDetails(_ a: [String: Any], to item: inout CanvasDueItem) {
        let html = a["description"] as? String ?? ""
        if !html.isEmpty { item.descriptionText = CanvasText.plain(fromHTML: html) }
        item.submissionTypes = (a["submission_types"] as? [String] ?? []).filter { $0 != "none" }
        if let rubric = a["rubric"] as? [[String: Any]] {
            item.rubricText = rubric.compactMap { c -> String? in
                let name = (c["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = CanvasText.plain(fromHTML: c["long_description"] as? String ?? "")
                let points = (c["points"] as? NSNumber).map { " (\($0) pts)" } ?? ""
                guard !name.isEmpty || !detail.isEmpty else { return nil }
                return "- \(name)\(points)" + (detail.isEmpty ? "" : ": \(detail)")
            }.joined(separator: "\n")
        }
        item.attachmentFileIds = fileIds(inHTML: html)
    }

    /// Canvas file ids linked from HTML ("/courses/5/files/123", "/files/123/download", API endpoints), in order.
    nonisolated static func fileIds(inHTML html: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"/files/(\d+)"#) else { return [] }
        var ids: [Int] = []
        for m in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            if let r = Range(m.range(at: 1), in: html), let id = Int(html[r]), !ids.contains(id) { ids.append(id) }
        }
        return ids
    }

    nonisolated static func int(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let s = value as? String { return Int(s) }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    nonisolated static func date(_ value: Any?) -> Date? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return ISO8601DateFormatter().date(from: s) ?? withFraction.date(from: s)
    }

    nonisolated static func courseId(fromContextCode code: String?) -> Int? {
        guard let code = code, code.hasPrefix("course_") else { return nil }
        return Int(code.dropFirst("course_".count))
    }
}

/// Text helpers for Canvas HTML content.
public enum CanvasText {
    /// Converts Canvas HTML to readable plain text (paragraphs and list items become new lines).
    public static func plain(fromHTML html: String) -> String {
        guard !html.isEmpty else { return "" }
        var text = html
        let breaks = ["<br>", "<br/>", "<br />", "</p>", "</div>", "</li>", "</h1>", "</h2>", "</h3>", "</h4>", "</tr>"]
        for tag in breaks { text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive) }
        text = text.replacingOccurrences(of: "<li[^>]*>", with: "• ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>", with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”", "&ndash;": "–", "&mdash;": "—"]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n\\s*\\n\\s*\\n+", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func fingerprint(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
