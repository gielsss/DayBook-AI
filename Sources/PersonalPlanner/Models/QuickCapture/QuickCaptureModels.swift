import Foundation

public enum QuickCaptureContentType: String, Codable, CaseIterable {
    case text = "Text"
    case image = "Image"
}

public enum QuickCaptureProposalType: String, Codable, CaseIterable {
    case task = "Task"
    case confirmedEvent = "Confirmed Event"
    case tentativeEvent = "Tentative Event"
    case noAction = "No Action"
    
    public var badgeTitle: String {
        switch self {
        case .task: return "Task"
        case .confirmedEvent: return "Event"
        case .tentativeEvent: return "Tentative Event"
        case .noAction: return "No Action"
        }
    }
}

public struct QuickCaptureProposal: Identifiable, Codable, Hashable {
    public let id: UUID
    public var proposalType: QuickCaptureProposalType
    
    // Task properties
    public var title: String
    public var requiredAction: String
    public var extractedDeadline: Date?
    public var dateOnlyString: String?
    public var originalDeadlineWording: String?
    public var deadlineProvenance: DeadlineProvenance
    public var timeZoneAssumption: String?
    public var estimatedDurationMinutes: Int
    public var isDurationInferred: Bool
    public var planningTargetDate: Date?
    public var isAmbiguous: Bool
    public var clarificationPrompt: String?
    
    // Event properties
    public var eventTitle: String
    public var eventStartTime: Date?
    public var eventEndTime: Date?
    public var isAllDay: Bool
    public var location: String?
    public var attendees: [String]
    public var originalTimingWording: String?
    public var isTentative: Bool
    
    // Common metadata
    public var supportingExcerpt: String
    public var notes: String
    public var inferredDetails: [String]
    
    // Review and duplicate status
    public var isSaved: Bool
    public var isDiscarded: Bool
    public var duplicateWarning: String?
    public var savedTaskId: UUID?
    public var savedCommitmentId: UUID?
    
    public init(
        id: UUID = UUID(),
        proposalType: QuickCaptureProposalType,
        title: String = "",
        requiredAction: String = "",
        extractedDeadline: Date? = nil,
        dateOnlyString: String? = nil,
        originalDeadlineWording: String? = nil,
        deadlineProvenance: DeadlineProvenance = .unsupported,
        timeZoneAssumption: String? = nil,
        estimatedDurationMinutes: Int = 45,
        isDurationInferred: Bool = false,
        planningTargetDate: Date? = nil,
        isAmbiguous: Bool = false,
        clarificationPrompt: String? = nil,
        eventTitle: String = "",
        eventStartTime: Date? = nil,
        eventEndTime: Date? = nil,
        isAllDay: Bool = false,
        location: String? = nil,
        attendees: [String] = [],
        originalTimingWording: String? = nil,
        isTentative: Bool = false,
        supportingExcerpt: String = "",
        notes: String = "",
        inferredDetails: [String] = [],
        isSaved: Bool = false,
        isDiscarded: Bool = false,
        duplicateWarning: String? = nil,
        savedTaskId: UUID? = nil,
        savedCommitmentId: UUID? = nil
    ) {
        self.id = id
        self.proposalType = proposalType
        self.title = title.isEmpty && !eventTitle.isEmpty ? eventTitle : title
        self.requiredAction = requiredAction
        self.extractedDeadline = extractedDeadline
        self.dateOnlyString = dateOnlyString
        self.originalDeadlineWording = originalDeadlineWording
        self.deadlineProvenance = deadlineProvenance
        self.timeZoneAssumption = timeZoneAssumption
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.isDurationInferred = isDurationInferred
        self.planningTargetDate = planningTargetDate
        self.isAmbiguous = isAmbiguous
        self.clarificationPrompt = clarificationPrompt
        self.eventTitle = eventTitle.isEmpty ? title : eventTitle
        self.eventStartTime = eventStartTime
        self.eventEndTime = eventEndTime
        self.isAllDay = isAllDay
        self.location = location
        self.attendees = attendees
        self.originalTimingWording = originalTimingWording
        self.isTentative = isTentative || proposalType == .tentativeEvent
        self.supportingExcerpt = supportingExcerpt
        self.notes = notes
        self.inferredDetails = inferredDetails
        self.isSaved = isSaved
        self.isDiscarded = isDiscarded
        self.duplicateWarning = duplicateWarning
        self.savedTaskId = savedTaskId
        self.savedCommitmentId = savedCommitmentId
    }
}

public struct QuickCaptureDraft: Identifiable, Codable {
    public let id: UUID
    public var createdAt: Date
    public var contentType: QuickCaptureContentType
    public var rawText: String
    public var imageData: Data?
    public var imageMimeType: String?
    public var referenceDate: Date
    public var referenceTimeZoneIdentifier: String
    public var proposals: [QuickCaptureProposal]
    public var reasoning: String
    public var errorMessage: String?
    public var isAnalyzing: Bool
    
    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        contentType: QuickCaptureContentType = .text,
        rawText: String = "",
        imageData: Data? = nil,
        imageMimeType: String? = nil,
        referenceDate: Date = Date(),
        referenceTimeZoneIdentifier: String = TimeZone.current.identifier,
        proposals: [QuickCaptureProposal] = [],
        reasoning: String = "",
        errorMessage: String? = nil,
        isAnalyzing: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.contentType = contentType
        self.rawText = rawText
        self.imageData = imageData
        self.imageMimeType = imageMimeType
        self.referenceDate = referenceDate
        self.referenceTimeZoneIdentifier = referenceTimeZoneIdentifier
        self.proposals = proposals
        self.reasoning = reasoning
        self.errorMessage = errorMessage
        self.isAnalyzing = isAnalyzing
    }
}

public struct QuickCaptureRawProposalItem: Codable {
    public let proposalType: String // "task", "confirmedEvent", "tentativeEvent", "noAction"
    public let title: String?
    public let requiredAction: String?
    public let deadlineIso: String?
    public let dateOnlyString: String?
    public let originalDeadlineWording: String?
    public let deadlineProvenance: String?
    public let timeZoneAssumption: String?
    public let estimatedDurationMinutes: Int?
    public let isDurationInferred: Bool?
    public let eventStartIso: String?
    public let eventEndIso: String?
    public let isAllDay: Bool?
    public let location: String?
    public let attendees: [String]?
    public let originalTimingWording: String?
    public let isTentative: Bool?
    public let supportingExcerpt: String?
    public let notes: String?
    public let inferredDetails: [String]?
    public let isAmbiguous: Bool?
    public let clarificationPrompt: String?
}

public struct QuickCaptureExtractionResponse: Codable {
    public let proposals: [QuickCaptureRawProposalItem]
    public let reasoning: String?
}
