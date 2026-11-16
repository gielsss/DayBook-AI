import Foundation

public struct DismissedTaskRecord: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var requiredAction: String
    public var sourceEmailId: String?
    public var sourceThreadId: String?
    public var sourceSubject: String?
    public var sourceSender: String?
    public var sourceCategory: String?
    public var quickCaptureRetentionId: String?
    public var dismissedAt: Date
    public var notes: String?
    
    public init(
        id: UUID = UUID(),
        title: String,
        requiredAction: String,
        sourceEmailId: String? = nil,
        sourceThreadId: String? = nil,
        sourceSubject: String? = nil,
        sourceSender: String? = nil,
        sourceCategory: String? = nil,
        quickCaptureRetentionId: String? = nil,
        dismissedAt: Date = Date(),
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.requiredAction = requiredAction
        self.sourceEmailId = sourceEmailId
        self.sourceThreadId = sourceThreadId
        self.sourceSubject = sourceSubject
        self.sourceSender = sourceSender
        self.sourceCategory = sourceCategory
        self.quickCaptureRetentionId = quickCaptureRetentionId
        self.dismissedAt = dismissedAt
        self.notes = notes
    }
}
