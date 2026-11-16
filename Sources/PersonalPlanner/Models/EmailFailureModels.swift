import Foundation

public enum EmailFailureStage: String, Codable, CaseIterable {
    case retrieval = "retrieval"
    case decoding = "decoding"
    case analysis = "gemini" // raw value kept so saved failure records still load
    case validation = "validation"
    case saving = "saving"
    
    public var userFacingTitle: String {
        switch self {
        case .retrieval: return "Gmail Retrieval"
        case .decoding: return "Message Decoding"
        case .analysis: return "AI Analysis"
        case .validation: return "Schema Validation"
        case .saving: return "Task Saving"
        }
    }
    
    public var iconName: String {
        switch self {
        case .retrieval: return "arrow.down.circle"
        case .decoding: return "doc.text.magnifyingglass"
        case .analysis: return "sparkles"
        case .validation: return "checklist"
        case .saving: return "externaldrive.badge.xmark"
        }
    }
}

public struct FailedEmailRecord: Identifiable, Codable, Equatable {
    public let id: String // Gmail message ID
    public let threadId: String
    public var subject: String
    public var sender: String
    public var receivedDate: Date
    public var failureStage: EmailFailureStage
    public var failureReason: String
    public var firstFailedAt: Date
    public var lastAttemptAt: Date
    public var attemptCount: Int
    
    public var gmailWebLink: String {
        return "https://mail.google.com/mail/u/0/#inbox/\(id)"
    }
    
    public init(
        id: String,
        threadId: String,
        subject: String,
        sender: String,
        receivedDate: Date,
        failureStage: EmailFailureStage,
        failureReason: String,
        firstFailedAt: Date = Date(),
        lastAttemptAt: Date = Date(),
        attemptCount: Int = 1
    ) {
        self.id = id
        self.threadId = threadId
        self.subject = subject
        self.sender = sender
        self.receivedDate = receivedDate
        self.failureStage = failureStage
        self.failureReason = failureReason
        self.firstFailedAt = firstFailedAt
        self.lastAttemptAt = lastAttemptAt
        self.attemptCount = attemptCount
    }
    
    public func isOutsideScanWindow(hours: Double = 72, relativeTo referenceDate: Date = Date()) -> Bool {
        let threshold = referenceDate.addingTimeInterval(-hours * 3600)
        return receivedDate < threshold
    }
    
    // Kept for backward compatibility
    public func isOutsideSevenDays(relativeTo referenceDate: Date = Date()) -> Bool {
        return isOutsideScanWindow(hours: 7 * 24, relativeTo: referenceDate)
    }
}
