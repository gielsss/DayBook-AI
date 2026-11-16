import Foundation

/// Where a task was found, as something to open: the exact Gmail message, or the Canvas / Gradescope page
/// (assignment, quiz, discussion, announcement, inbox message, syllabus).
public struct TaskSourceLink: Equatable {
    public let url: URL
    /// Button title, e.g. "Open in Gmail", "Open in Canvas".
    public let title: String
    public let systemImage: String
    /// Shown as help: what exactly opens.
    public let detail: String

    /// The link for a task, or nil when it has no outside source (Quick Capture, typed in by hand, sample data).
    /// `canvasBase` resolves Canvas links saved as paths ("/courses/5/assignments/7").
    public static func forTask(_ task: DiscoveredTask, canvasBase: URL?) -> TaskSourceLink? {
        let source = task.sourceEmail
        guard !source.isSimulatedDemo else { return nil }
        switch source.category {
        case .canvas:
            let kind = canvasKind(source)
            if let link = resolve(source.webLink, base: canvasBase), !isGmail(link) {
                return TaskSourceLink(url: link, title: "Open in Canvas", systemImage: "graduationcap",
                                      detail: "Opens the \(kind) in your browser")
            }
            // Older tasks saved without a page link: Canvas itself is the closest place.
            guard let base = canvasBase else { return nil }
            let path = kind == "inbox message" ? "conversations" : ""
            return TaskSourceLink(url: path.isEmpty ? base : base.appendingPathComponent(path), title: "Open in Canvas",
                                  systemImage: "graduationcap",
                                  detail: "This task was saved before DayBook kept page links; opens Canvas. Sync again to link the exact \(kind).")
        case .gradescope:
            let link = resolve(source.webLink, base: URL(string: "https://www.gradescope.com"))
                .flatMap { isGmail($0) ? nil : $0 } ?? URL(string: "https://www.gradescope.com/account")!
            return TaskSourceLink(url: link, title: "Open in Gradescope", systemImage: "doc.text.magnifyingglass",
                                  detail: "Opens the assignment in your browser")
        case .quickCapture:
            return nil
        default:
            guard let url = source.messageURL else { return nil }
            return TaskSourceLink(url: url, title: "Open in Gmail", systemImage: "envelope",
                                  detail: "Opens “\(source.subject)” from \(source.senderName) in Gmail")
        }
    }

    /// Absolute URL from a saved link: full URLs as they are, paths against `base`.
    public static func resolve(_ link: String?, base: URL?) -> URL? {
        guard let raw = link?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
        guard raw.hasPrefix("/"), let base else { return nil }
        return URL(string: raw, relativeTo: base)?.absoluteURL
    }

    static func isGmail(_ url: URL) -> Bool { url.host?.hasSuffix("mail.google.com") ?? false }

    /// "assignment", "quiz", "announcement", … from the source id and subject.
    static func canvasKind(_ source: EmailSource) -> String {
        let id = source.threadId.isEmpty ? source.id : source.threadId
        let kinds: [(String, String)] = [("canvas-assignment-", "assignment"), ("canvas-quiz-", "quiz"),
                                         ("canvas-discussion-", "discussion"), ("canvas-page-", "page"),
                                         ("canvas-note-", "to-do"), ("canvas-announcement-", "announcement"),
                                         ("canvas-conversation-", "inbox message"), ("canvas-feedback-", "feedback"),
                                         ("canvas-syllabus-", "syllabus")]
        for (prefix, kind) in kinds where id.hasPrefix(prefix) || source.id.hasPrefix(prefix) { return kind }
        return "page"
    }
}
