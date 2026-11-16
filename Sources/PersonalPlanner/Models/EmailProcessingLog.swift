import Foundation

public enum DiscoveryAction: String, Codable, CaseIterable {
    case taskCreated = "Task Discovered"
    case taskNeedsClarification = "Flagged for Clarification"
    case taskUpdated = "Deadline / Details Updated"
    case ignoredNewsletter = "Filtered Out (Informational / Newsletter)"
    case taskDismissed = "Task Dismissed / Cleared"
}

public struct EmailProcessingLog: Identifiable, Codable, Hashable {
    public let id: UUID
    public let emailId: String
    public let sender: String
    public let subject: String
    public let timestamp: Date
    public let action: DiscoveryAction
    public let explanation: String
    public let extractedTaskId: UUID?
    
    public init(
        id: UUID = UUID(),
        emailId: String,
        sender: String,
        subject: String,
        timestamp: Date = Date(),
        action: DiscoveryAction,
        explanation: String,
        extractedTaskId: UUID? = nil
    ) {
        self.id = id
        self.emailId = emailId
        self.sender = sender
        self.subject = subject
        self.timestamp = timestamp
        self.action = action
        self.explanation = explanation
        self.extractedTaskId = extractedTaskId
    }
}
