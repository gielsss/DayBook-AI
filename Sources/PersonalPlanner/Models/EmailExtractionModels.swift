import Foundation

/// Result of analyzing one email for tasks. Persisted inside the extraction cache.
public struct CandidateTask: Codable, Equatable {
    public let title: String
    public let requiredAction: String
    public let deadlineIso: String?
    public let deadlineIsSupportedByEmail: Bool
    public let supportingExcerpt: String
    public let estimatedDurationMinutes: Int
    public let isAmbiguous: Bool
    public let uncertainDetails: [String]
    public let isDeadlineUpdate: Bool
    public let deadlineUpdateNote: String?
    public let originalDeadlineWording: String?
    public let dateOnlyString: String?
    
    public init(
        title: String,
        requiredAction: String,
        deadlineIso: String? = nil,
        deadlineIsSupportedByEmail: Bool = false,
        supportingExcerpt: String = "",
        estimatedDurationMinutes: Int = 45,
        isAmbiguous: Bool = false,
        uncertainDetails: [String] = [],
        isDeadlineUpdate: Bool = false,
        deadlineUpdateNote: String? = nil,
        originalDeadlineWording: String? = nil,
        dateOnlyString: String? = nil
    ) {
        self.title = title
        self.requiredAction = requiredAction
        self.deadlineIso = deadlineIso
        self.deadlineIsSupportedByEmail = deadlineIsSupportedByEmail
        self.supportingExcerpt = supportingExcerpt
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.isAmbiguous = isAmbiguous
        self.uncertainDetails = uncertainDetails
        self.isDeadlineUpdate = isDeadlineUpdate
        self.deadlineUpdateNote = deadlineUpdateNote
        self.originalDeadlineWording = originalDeadlineWording
        self.dateOnlyString = dateOnlyString
    }
}

public struct EmailAnalysis: Codable, Equatable {
    public let isNewsletterOrMarketing: Bool
    public let isDirectedAtRecipient: Bool
    public let hasActionableTask: Bool
    public let reasoning: String
    public let tasks: [CandidateTask]
    
    public init(
        isNewsletterOrMarketing: Bool,
        isDirectedAtRecipient: Bool,
        hasActionableTask: Bool,
        reasoning: String,
        tasks: [CandidateTask] = []
    ) {
        self.isNewsletterOrMarketing = isNewsletterOrMarketing
        self.isDirectedAtRecipient = isDirectedAtRecipient
        self.hasActionableTask = hasActionableTask
        self.reasoning = reasoning
        self.tasks = tasks
    }
}

public struct CachedEmailExtraction: Codable, Equatable {
    public let emailId: String
    public let emailSubject: String
    public let senderEmail: String
    public let receivedDate: Date
    public let analyzedDate: Date
    public let modelUsed: String
    public let analysis: EmailAnalysis
    
    public init(
        emailId: String,
        emailSubject: String,
        senderEmail: String,
        receivedDate: Date,
        analyzedDate: Date = Date(),
        modelUsed: String,
        analysis: EmailAnalysis
    ) {
        self.emailId = emailId
        self.emailSubject = emailSubject
        self.senderEmail = senderEmail
        self.receivedDate = receivedDate
        self.analyzedDate = analyzedDate
        self.modelUsed = modelUsed
        self.analysis = analysis
    }
}

public struct AnalyzedEmailSummaryItem: Identifiable, Codable, Equatable {
    public let id: String
    public let subject: String
    public let sender: String
    public let date: Date
    public let modelUsed: String
    public let tasksDiscoveredCount: Int
    public let taskTitles: [String]
    public let statusDescription: String
    
    public init(
        id: String,
        subject: String,
        sender: String,
        date: Date,
        modelUsed: String,
        tasksDiscoveredCount: Int,
        taskTitles: [String],
        statusDescription: String
    ) {
        self.id = id
        self.subject = subject
        self.sender = sender
        self.date = date
        self.modelUsed = modelUsed
        self.tasksDiscoveredCount = tasksDiscoveredCount
        self.taskTitles = taskTitles
        self.statusDescription = statusDescription
    }
}
