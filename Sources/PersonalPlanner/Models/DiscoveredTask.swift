import Foundation

public enum TaskStatus: String, Codable, CaseIterable {
    case discovered = "Discovered"
    case needsClarification = "Needs Clarification"
    case ready = "Ready to Schedule"
    case completed = "Completed"
    case dismissed = "Dismissed"
}

public enum DeadlineProvenance: String, Codable, CaseIterable {
    case explicitDateTime = "Explicit Date & Time"
    case dateOnly = "Date-Only Deadline"
    case relativeWindow = "Relative Time Window"
    case userTarget = "User-Selected Target"
    case userOverridden = "User-Overridden Deadline"
    case unsupported = "No Deadline in Email"
    
    public var badgeTitle: String {
        switch self {
        case .explicitDateTime: return "Email Deadline"
        case .dateOnly: return "Date Only"
        case .relativeWindow: return "Relative Window"
        case .userTarget: return "User Target"
        case .userOverridden: return "User Deadline"
        case .unsupported: return "No Deadline"
        }
    }
}

public enum SchedulingEligibility: Equatable {
    case eligible(provenance: DeadlineProvenance)
    case needsPlanningTarget
    case needsActionClarification(reason: String)
    case deadlinePassed(deadline: Date)
    case completed
    case dismissed
}

public enum TaskPriority: String, Codable, CaseIterable, Comparable {
    case urgent = "Urgent"
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    
    public var sortOrder: Int {
        switch self {
        case .urgent: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }
    
    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// "Updated" reminder shown next to a task when a later sync brought new information
/// (a moved due date, new details) instead of creating a duplicate task.
public struct TaskSyncUpdate: Codable, Hashable {
    public var date: Date
    /// What changed, e.g. "Due date moved to Nov 12, 11:59 PM · New details from Canvas".
    public var summary: String
    /// Where it came from: "Email", "Canvas", "Gradescope".
    public var source: String
    /// Set when the user dismisses the reminder.
    public var isSeen: Bool

    public init(date: Date, summary: String, source: String, isSeen: Bool = false) {
        self.date = date
        self.summary = summary
        self.source = source
        self.isSeen = isSeen
    }
}

public struct DiscoveredTask: Identifiable, Codable, Hashable {
    public let id: UUID
    public var title: String
    public var requiredAction: String
    public var notes: String
    public var sourceEmail: EmailSource
    public var extractedDeadline: Date?
    public var isDeadlineSupportedByEmail: Bool
    public var supportingExcerpt: String
    public var estimatedMinutes: Int
    public var status: TaskStatus
    public var uncertainDetails: [String]
    public var clarificationPrompt: String?
    public var isClarified: Bool
    public var deadlineUpdateNote: String?
    public var isDismissed: Bool
    
    // User edits / overrides preserved across scans
    public var userOverriddenTitle: String?
    public var userOverriddenDeadline: Date?
    public var userOverriddenDuration: Int?
    public var userPriority: TaskPriority
    public var isDateOnlyDeadline: Bool
    public var planningTargetDate: Date?
    public var isCarryover: Bool
    
    // Timezone & Wording metadata
    public var originalDeadlineWording: String?
    public var dateOnlyDeadlineString: String?
    public var timeZoneAssumption: String?
    
    public var createdAt: Date
    public var updatedAt: Date
    
    /// Latest sync update merged into this task (see `TaskMemory`).
    public var syncUpdate: TaskSyncUpdate?
    
    /// Why the time estimate is what it is, when the local AI estimated it
    /// (e.g. "AI estimate: 5 proofs plus a short write-up"). Nil = not estimated by AI yet.
    public var estimateNote: String?
    
    /// Estimate before it was adjusted from your past actual times (nil = not adjusted).
    public var rawEstimateMinutes: Int?
    /// e.g. "Adjusted +40% from your last 3 ECON problem sets".
    public var calibrationNote: String?

    /// What Canvas says the assignment asks for: instructions, how it's handed in, rubric and the
    /// text of attached files. Refreshed every sync; used for the time estimate.
    public var assignmentDetails: String? = nil
    /// Fingerprint of what the last AI estimate was based on: a change means it's estimated again.
    public var estimateInputKey: String? = nil
    /// How sure the AI was: "low", "medium", "high", or "confirmed" once you've checked it.
    public var estimateConfidence: String? = nil

    /// An AI estimate worth a second look: made with little to go on, and you haven't set or confirmed the time.
    public var needsEstimateCheck: Bool {
        estimateConfidence == "low" && userOverriddenDuration == nil && !isCompleted && !isDismissed
    }
    
    /// Shown as "Updated" until dismissed, for up to a week.
    public var hasUnseenUpdate: Bool {
        guard let u = syncUpdate, !u.isSeen else { return false }
        return Date().timeIntervalSince(u.date) < 7 * 86400
    }
    
    public init(
        id: UUID = UUID(),
        title: String,
        requiredAction: String = "",
        notes: String = "",
        sourceEmail: EmailSource,
        extractedDeadline: Date? = nil,
        isDeadlineSupportedByEmail: Bool = false,
        supportingExcerpt: String = "",
        estimatedMinutes: Int = 45,
        status: TaskStatus = .discovered,
        uncertainDetails: [String] = [],
        clarificationPrompt: String? = nil,
        isClarified: Bool = false,
        deadlineUpdateNote: String? = nil,
        isDismissed: Bool = false,
        userOverriddenTitle: String? = nil,
        userOverriddenDeadline: Date? = nil,
        userOverriddenDuration: Int? = nil,
        userPriority: TaskPriority = .medium,
        isDateOnlyDeadline: Bool = false,
        planningTargetDate: Date? = nil,
        isCarryover: Bool = false,
        originalDeadlineWording: String? = nil,
        dateOnlyDeadlineString: String? = nil,
        timeZoneAssumption: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.requiredAction = requiredAction.isEmpty ? title : requiredAction
        self.notes = notes
        self.sourceEmail = sourceEmail
        self.extractedDeadline = extractedDeadline
        self.isDeadlineSupportedByEmail = isDeadlineSupportedByEmail || (extractedDeadline != nil)
        self.supportingExcerpt = supportingExcerpt.isEmpty ? sourceEmail.snippet : supportingExcerpt
        self.estimatedMinutes = estimatedMinutes
        self.status = status
        self.uncertainDetails = uncertainDetails
        self.clarificationPrompt = clarificationPrompt
        self.isClarified = isClarified
        self.deadlineUpdateNote = deadlineUpdateNote
        self.isDismissed = isDismissed
        self.userOverriddenTitle = userOverriddenTitle
        self.userOverriddenDeadline = userOverriddenDeadline
        self.userOverriddenDuration = userOverriddenDuration
        self.userPriority = userPriority
        self.planningTargetDate = planningTargetDate
        self.isCarryover = isCarryover
        self.originalDeadlineWording = originalDeadlineWording
        self.dateOnlyDeadlineString = dateOnlyDeadlineString
        self.timeZoneAssumption = timeZoneAssumption
        
        // Auto-detect if extracted deadline is date-only (00:00:00)
        if let dl = extractedDeadline {
            let cal = Calendar.current
            let hour = cal.component(.hour, from: dl)
            let minute = cal.component(.minute, from: dl)
            self.isDateOnlyDeadline = isDateOnlyDeadline || (dateOnlyDeadlineString != nil) || (hour == 0 && minute == 0)
        } else {
            self.isDateOnlyDeadline = isDateOnlyDeadline || (dateOnlyDeadlineString != nil)
        }
        
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, requiredAction, notes, sourceEmail, extractedDeadline
        case isDeadlineSupportedByEmail, supportingExcerpt, estimatedMinutes, status
        case uncertainDetails, clarificationPrompt, isClarified, deadlineUpdateNote, isDismissed
        case userOverriddenTitle, userOverriddenDeadline, userOverriddenDuration
        case userPriority, isDateOnlyDeadline, planningTargetDate, isCarryover
        case originalDeadlineWording, dateOnlyDeadlineString, timeZoneAssumption
        case createdAt, updatedAt, syncUpdate, estimateNote, rawEstimateMinutes, calibrationNote
        case assignmentDetails, estimateInputKey, estimateConfidence
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.requiredAction = try container.decodeIfPresent(String.self, forKey: .requiredAction) ?? ""
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.sourceEmail = try container.decode(EmailSource.self, forKey: .sourceEmail)
        self.extractedDeadline = try container.decodeIfPresent(Date.self, forKey: .extractedDeadline)
        self.isDeadlineSupportedByEmail = try container.decodeIfPresent(Bool.self, forKey: .isDeadlineSupportedByEmail) ?? (extractedDeadline != nil)
        self.supportingExcerpt = try container.decodeIfPresent(String.self, forKey: .supportingExcerpt) ?? ""
        self.estimatedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes) ?? 45
        self.status = try container.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .discovered
        self.uncertainDetails = try container.decodeIfPresent([String].self, forKey: .uncertainDetails) ?? []
        self.clarificationPrompt = try container.decodeIfPresent(String.self, forKey: .clarificationPrompt)
        self.isClarified = try container.decodeIfPresent(Bool.self, forKey: .isClarified) ?? false
        self.deadlineUpdateNote = try container.decodeIfPresent(String.self, forKey: .deadlineUpdateNote)
        self.isDismissed = try container.decodeIfPresent(Bool.self, forKey: .isDismissed) ?? false
        self.userOverriddenTitle = try container.decodeIfPresent(String.self, forKey: .userOverriddenTitle)
        self.userOverriddenDeadline = try container.decodeIfPresent(Date.self, forKey: .userOverriddenDeadline)
        self.userOverriddenDuration = try container.decodeIfPresent(Int.self, forKey: .userOverriddenDuration)
        self.userPriority = try container.decodeIfPresent(TaskPriority.self, forKey: .userPriority) ?? .medium
        self.isDateOnlyDeadline = try container.decodeIfPresent(Bool.self, forKey: .isDateOnlyDeadline) ?? false
        self.planningTargetDate = try container.decodeIfPresent(Date.self, forKey: .planningTargetDate)
        self.isCarryover = try container.decodeIfPresent(Bool.self, forKey: .isCarryover) ?? false
        self.originalDeadlineWording = try container.decodeIfPresent(String.self, forKey: .originalDeadlineWording)
        self.dateOnlyDeadlineString = try container.decodeIfPresent(String.self, forKey: .dateOnlyDeadlineString)
        self.timeZoneAssumption = try container.decodeIfPresent(String.self, forKey: .timeZoneAssumption)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        self.syncUpdate = try container.decodeIfPresent(TaskSyncUpdate.self, forKey: .syncUpdate)
        self.estimateNote = try container.decodeIfPresent(String.self, forKey: .estimateNote)
        self.rawEstimateMinutes = try container.decodeIfPresent(Int.self, forKey: .rawEstimateMinutes)
        self.calibrationNote = try container.decodeIfPresent(String.self, forKey: .calibrationNote)
        self.assignmentDetails = try container.decodeIfPresent(String.self, forKey: .assignmentDetails)
        self.estimateInputKey = try container.decodeIfPresent(String.self, forKey: .estimateInputKey)
        self.estimateConfidence = try container.decodeIfPresent(String.self, forKey: .estimateConfidence)
    }
    
    public var displayTitle: String {
        userOverriddenTitle ?? title
    }
    
    public var effectiveDeadline: Date? {
        planningTargetDate ?? userOverriddenDeadline ?? (isDeadlineSupportedByEmail ? extractedDeadline : nil)
    }
    
    public var originalDeadlineProvenance: DeadlineProvenance {
        guard let _ = extractedDeadline, isDeadlineSupportedByEmail else {
            return .unsupported
        }
        let lower = supportingExcerpt.lowercased()
        if lower.contains("within") && (lower.contains("hour") || lower.contains("day")) {
            return .relativeWindow
        }
        if isDateOnlyDeadline || dateOnlyDeadlineString != nil {
            return .dateOnly
        }
        return .explicitDateTime
    }
    
    public var activeDeadlineProvenance: DeadlineProvenance {
        if planningTargetDate != nil {
            return .userTarget
        }
        if userOverriddenDeadline != nil {
            return .userOverridden
        }
        return originalDeadlineProvenance
    }
    
    public var isOriginalDeadlineOverdue: Bool {
        guard let dl = extractedDeadline, isDeadlineSupportedByEmail else { return false }
        return dl.timeIntervalSinceReferenceDate < Date().timeIntervalSinceReferenceDate
    }
    
    public var isOverdue: Bool {
        guard let dl = effectiveDeadline else { return false }
        return dl.timeIntervalSinceReferenceDate < Date().timeIntervalSinceReferenceDate
    }
    
    public var hasPlanningTarget: Bool {
        planningTargetDate != nil
    }
    
    public var effectiveDuration: Int {
        userOverriddenDuration ?? estimatedMinutes
    }
    
    public var isCompleted: Bool {
        status == .completed
    }
    
    public var isActionUnclear: Bool {
        let trimmed = requiredAction.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if status == .needsClarification && !isClarified {
            let nonDeadlineUncertainties = uncertainDetails.filter { detail in
                let lower = detail.lowercased()
                return !lower.contains("deadline") && !lower.contains("time limit") && !lower.contains("due date")
            }
            return !nonDeadlineUncertainties.isEmpty
        }
        return false
    }
    
    public func schedulingEligibility(asOf currentDate: Date = Date()) -> SchedulingEligibility {
        if isDismissed { return .dismissed }
        if isCompleted { return .completed }
        if isActionUnclear {
            let reason = uncertainDetails.first(where: { detail in
                let l = detail.lowercased()
                return !l.contains("deadline") && !l.contains("time limit") && !l.contains("due date")
            }) ?? "Required action or scope requires user clarification."
            return .needsActionClarification(reason: reason)
        }
        guard let dl = effectiveDeadline else {
            return .needsPlanningTarget
        }
        if dl.timeIntervalSinceReferenceDate <= currentDate.timeIntervalSinceReferenceDate {
            return .deadlinePassed(deadline: dl)
        }
        return .eligible(provenance: activeDeadlineProvenance)
    }
    
    public var schedulingEligibility: SchedulingEligibility {
        schedulingEligibility(asOf: Date())
    }
    
    public func isEligibleForScheduling(asOf currentDate: Date = Date()) -> Bool {
        if case .eligible = schedulingEligibility(asOf: currentDate) { return true }
        return false
    }
    
    public var isEligibleForScheduling: Bool {
        isEligibleForScheduling(asOf: Date())
    }
    
    public var isAmbiguous: Bool {
        isActionUnclear || (effectiveDeadline == nil && !isClarified)
    }
}
