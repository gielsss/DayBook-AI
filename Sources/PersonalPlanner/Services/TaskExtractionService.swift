import Foundation

public final class SimulatedTaskExtractionService: TaskExtractionServiceProtocol {
    public init() {}
    
    public func extractTasks(
        from emails: [EmailSource],
        existingTasks: [DiscoveredTask]
    ) async throws -> TaskExtractionResult {
        // Simulates model processing latency
        try await Task.sleep(nanoseconds: 400_000_000) // 0.4s
        
        var newTasks: [DiscoveredTask] = []
        var updatedTasks: [DiscoveredTask] = []
        var logs: [EmailProcessingLog] = []
        
        // Track task mapping by threadId
        var taskByThread: [String: DiscoveredTask] = [:]
        for task in existingTasks {
            taskByThread[task.sourceEmail.threadId] = task
        }
        
        for email in emails {
            switch email.category {
            case .assignment:
                // Check if already extracted
                if taskByThread[email.threadId] != nil {
                    // Already have it
                    continue
                }
                let taskId = UUID()
                let deadline = DemoDataFactory.makeDate(daysFromNow: 4, hour: 23, minute: 59)
                let task = DiscoveredTask(
                    id: taskId,
                    title: "CS 420 Lab 3: Raft Consensus Implementation",
                    requiredAction: "Implement leader election, heartbeats, and log replication",
                    notes: "Implement leader election, heartbeats, and log replication. Grading harness in starter repo.",
                    sourceEmail: email,
                    extractedDeadline: deadline,
                    isDeadlineSupportedByEmail: true,
                    supportingExcerpt: "Submission Deadline: This Friday at 11:59 PM. Estimated effort: 3 hours.",
                    estimatedMinutes: 180,
                    status: .ready,
                    uncertainDetails: [],
                    clarificationPrompt: nil,
                    isClarified: true,
                    deadlineUpdateNote: nil,
                    createdAt: email.receivedDate,
                    updatedAt: email.receivedDate
                )
                newTasks.append(task)
                taskByThread[email.threadId] = task
                
                let log = EmailProcessingLog(
                    emailId: email.id,
                    sender: email.senderName,
                    subject: email.subject,
                    timestamp: email.receivedDate,
                    action: .taskCreated,
                    explanation: "Discovered clear assignment. Extracted deadline and estimated duration (180 min). Status: Ready to Schedule.",
                    extractedTaskId: taskId
                )
                logs.append(log)
                
            case .ambiguous:
                if taskByThread[email.threadId] != nil {
                    continue
                }
                let taskId = UUID()
                let task = DiscoveredTask(
                    id: taskId,
                    title: "Review & clarify slide 8 architecture diagrams",
                    requiredAction: "Review slide 8 architecture diagram and decide on full overhaul vs minor callouts",
                    notes: "Client requested cloud redundancy on slide 8. Need decision on full overhaul vs minor callouts.",
                    sourceEmail: email,
                    extractedDeadline: nil,
                    isDeadlineSupportedByEmail: false,
                    supportingExcerpt: "Whenever you get some breathing room this week or next, could you take a quick pass at slide 8?",
                    estimatedMinutes: 45,
                    status: .needsClarification,
                    uncertainDetails: [
                        "No deadline specified in email ('this week or next')",
                        "Scope is open-ended: full diagram overhaul vs minor callouts"
                    ],
                    clarificationPrompt: "No deadline specified ('this week or next') and scope is open-ended. Specify target completion date and whether full overhaul is needed.",
                    isClarified: false,
                    deadlineUpdateNote: nil,
                    createdAt: email.receivedDate,
                    updatedAt: email.receivedDate
                )
                newTasks.append(task)
                taskByThread[email.threadId] = task
                
                let log = EmailProcessingLog(
                    emailId: email.id,
                    sender: email.senderName,
                    subject: email.subject,
                    timestamp: email.receivedDate,
                    action: .taskNeedsClarification,
                    explanation: "Discovered request lacking deadline and concrete scope. Flagged for user clarification.",
                    extractedTaskId: taskId
                )
                logs.append(log)
                
            case .newsletter:
                // Newsletter: the model identifies broadcast with no action items
                let log = EmailProcessingLog(
                    emailId: email.id,
                    sender: email.senderName,
                    subject: email.subject,
                    timestamp: email.receivedDate,
                    action: .ignoredNewsletter,
                    explanation: "Classified as newsletter / informational broadcast. No commitments, tasks, or deadlines found. Filtered out from task list.",
                    extractedTaskId: nil
                )
                logs.append(log)
                
            case .deadlineChange:
                // Find matching task by threadId or title
                if var targetTask = taskByThread[email.threadId] ?? existingTasks.first(where: { $0.title.contains("Lab 3") }) {
                    let extendedDeadline = DemoDataFactory.makeDate(daysFromNow: 6, hour: 23, minute: 59)
                    targetTask.extractedDeadline = extendedDeadline
                    targetTask.deadlineUpdateNote = "Deadline extended to Sunday (+48h) due to cluster maintenance."
                    targetTask.updatedAt = email.receivedDate
                    updatedTasks.append(targetTask)
                    taskByThread[email.threadId] = targetTask
                    
                    let log = EmailProcessingLog(
                        emailId: email.id,
                        sender: email.senderName,
                        subject: email.subject,
                        timestamp: email.receivedDate,
                        action: .taskUpdated,
                        explanation: "Detected deadline update for 'CS 420 Lab 3'. Matched thread '\(email.threadId)'. Extended deadline to Sunday 11:59 PM.",
                        extractedTaskId: targetTask.id
                    )
                    logs.append(log)
                }
                
            case .quickCapture, .canvas, .gradescope:
                break
            }
        }
        
        return TaskExtractionResult(
            newTasks: newTasks,
            updatedTasks: updatedTasks,
            logs: logs
        )
    }
}
