import Foundation

public enum EmailCategory: String, Codable, CaseIterable {
    case assignment = "Clear Assignment"
    case ambiguous = "Ambiguous Request"
    case newsletter = "Newsletter / Informational"
    case deadlineChange = "Deadline Change Update"
    case quickCapture = "Quick Capture"
    case canvas = "Canvas"
    case gradescope = "Gradescope"
}

public struct EmailSource: Identifiable, Codable, Hashable {
    public let id: String
    public let threadId: String
    public let senderName: String
    public let senderEmail: String
    public let subject: String
    public let receivedDate: Date
    public let snippet: String
    public let fullBody: String
    public let category: EmailCategory
    public var isSimulatedDemo: Bool
    public var webLink: String?
    
    public init(
        id: String,
        threadId: String,
        senderName: String,
        senderEmail: String,
        subject: String,
        receivedDate: Date,
        snippet: String,
        fullBody: String,
        category: EmailCategory,
        isSimulatedDemo: Bool = true,
        webLink: String? = nil
    ) {
        self.id = id
        self.threadId = threadId
        self.senderName = senderName
        self.senderEmail = senderEmail
        self.subject = subject
        self.receivedDate = receivedDate
        self.snippet = snippet
        self.fullBody = fullBody
        self.category = category
        self.isSimulatedDemo = isSimulatedDemo
        self.webLink = webLink ?? (isSimulatedDemo || !EmailSource.isGmailMessageId(id, category: category) ? nil : EmailSource.gmailURL(forMessageId: id))
    }
    
    /// True when `id` is a Gmail message id (not a Canvas/Gradescope/Quick Capture/manual source).
    public static func isGmailMessageId(_ id: String, category: EmailCategory) -> Bool {
        guard ![.canvas, .gradescope, .quickCapture].contains(category) else { return false }
        let localPrefixes = ["msg-", "manual-", "qc-", "canvas-", "gradescope-", "demo-"]
        return !id.isEmpty && !localPrefixes.contains { id.hasPrefix($0) } && !id.contains("@")
    }

    /// Opens the exact message in Gmail. `#all` finds it even after it was archived or labeled.
    public static func gmailURL(forMessageId id: String) -> String {
        "https://mail.google.com/mail/u/0/#all/\(id)"
    }

    /// The original message in Gmail (email sources only).
    public var messageURL: URL? {
        guard !isSimulatedDemo, Self.isGmailMessageId(id, category: category) else { return nil }
        return URL(string: Self.gmailURL(forMessageId: id))
    }
}
