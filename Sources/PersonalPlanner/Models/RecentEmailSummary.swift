import Foundation

public struct RecentEmailSummary: Identifiable, Codable, Hashable {
    public let id: String
    public let subject: String
    public let sender: String
    public let date: Date
    public let snippet: String
    
    public init(
        id: String,
        subject: String,
        sender: String,
        date: Date,
        snippet: String
    ) {
        self.id = id
        self.subject = subject
        self.sender = sender
        self.date = date
        self.snippet = snippet
    }
}
