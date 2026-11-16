import Foundation

public final class QuickCaptureDuplicateDetector {
    public static func checkDuplicate(
        proposal: QuickCaptureProposal,
        existingTasks: [DiscoveredTask],
        existingCommitments: [CalendarCommitment],
        timeZone: TimeZone
    ) -> String? {
        let df = DateFormatter()
        df.timeZone = timeZone
        df.dateStyle = .short
        df.timeStyle = .short
        
        switch proposal.proposalType {
        case .task:
            let cleanTitle = proposal.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !cleanTitle.isEmpty else { return nil }
            
            // Check by title or supporting excerpt
            for task in existingTasks where !task.isDismissed {
                let existingTitle = task.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if cleanTitle == existingTitle || (cleanTitle.count > 10 && existingTitle.contains(cleanTitle)) || (existingTitle.count > 10 && cleanTitle.contains(existingTitle)) {
                    let deadlineStr = task.effectiveDeadline.map { " due " + df.string(from: $0) } ?? ""
                    return "Possible duplicate: Matches existing task '\(task.displayTitle)' (\(task.status.rawValue)\(deadlineStr))."
                }
                
                // If supporting excerpt is identical
                if !proposal.supportingExcerpt.isEmpty && task.supportingExcerpt.contains(proposal.supportingExcerpt) {
                    return "Possible duplicate: Excerpt matches existing task '\(task.displayTitle)'."
                }
            }
            return nil
            
        case .confirmedEvent, .tentativeEvent:
            let cleanTitle = proposal.eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !cleanTitle.isEmpty else { return nil }
            
            for commitment in existingCommitments {
                let existingTitle = commitment.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if cleanTitle == existingTitle || (cleanTitle.count > 8 && existingTitle.contains(cleanTitle)) {
                    // Check if time is on same day or within 2 hours
                    if let start = proposal.eventStartTime {
                        let diff = abs(commitment.startTime.timeIntervalSince(start))
                        if diff < 7200 { // within 2 hours
                            return "Possible duplicate: Matches existing calendar event '\(commitment.title)' on \(df.string(from: commitment.startTime))."
                        }
                    } else {
                        return "Possible duplicate: Matches existing calendar event '\(commitment.title)'."
                    }
                }
            }
            return nil
            
        case .noAction:
            return nil
        }
    }
}
