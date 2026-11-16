import SwiftUI

public struct UnscheduledTasksSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private var unscheduledReports: [UnscheduledTaskReport] {
        appState.lastSchedulingResult?.unscheduledReports ?? []
    }
    
    private var ambiguousTasks: [DiscoveredTask] {
        appState.lastSchedulingResult?.ambiguousTasks ?? []
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scheduling Analysis & Unscheduled Effort")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("DayBook AI guarantees work is never silently scheduled past deadlines or into booked time.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Summary stats if available
                    if let stats = appState.lastSchedulingResult?.stats {
                        HStack(spacing: 16) {
                            statPill(label: "Evaluated Tasks", count: "\(stats.tasksEvaluated)", color: .dbNavy)
                            statPill(label: "Fully Scheduled", count: "\(stats.fullyScheduledCount)", color: .green)
                            statPill(label: "Unscheduled / Tight", count: "\(stats.unscheduledCount)", color: stats.unscheduledCount > 0 ? .orange : .secondary)
                            statPill(label: "Total Planned Time", count: stats.totalPlannedHoursFormatted, color: .dbAccent)
                        }
                    }
                    
                    // Unscheduled / constrained tasks
                    if unscheduledReports.isEmpty && ambiguousTasks.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.green)
                            Text("All tasks fully scheduled!")
                                .font(.headline)
                            Text("Every discovered task fits comfortably within your working hours before its deadline.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        // Section 1: Incomplete / constrained tasks with deadlines
                        let constrained = unscheduledReports.filter { $0.primaryReason != .missingDeadline }
                        if !constrained.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Tasks With Unscheduled Effort", systemImage: "exclamationmark.triangle.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                
                                Text("These tasks could not be fully accommodated before their deadline due to booked calendar events or daily working limits:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                ForEach(constrained) { report in
                                    reportCard(report: report)
                                }
                            }
                        }
                        
                        // Section 2: Ambiguous tasks needing review (no deadline)
                        if !ambiguousTasks.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Tasks Needing Review / Deadline", systemImage: "questionmark.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.dbNavy)
                                
                                Text("These items have ambiguous requests or missing deadlines. Per product rules, deadlines are never invented and require your review before automatic scheduling:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                ForEach(ambiguousTasks) { task in
                                    ambiguousTaskCard(task: task)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 460)
    }
    
    private func statPill(label: String, count: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(count)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func reportCard(report: UnscheduledTaskReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(report.task.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(report.primaryReason.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.orange)
            }
            
            Text(report.detailedExplanation)
                .font(.caption)
                .foregroundColor(.primary)
            
            HStack(spacing: 12) {
                Text("Total: **\(report.totalEstimatedMinutes)m**")
                    .font(.caption2)
                Text("Scheduled: **\(report.scheduledMinutes)m**")
                    .font(.caption2)
                    .foregroundColor(.green)
                Text("Unscheduled: **\(report.unscheduledMinutes)m**")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(12)
        .background(Color.dbSurface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func ambiguousTaskCard(task: DiscoveredTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(task.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("Needs Deadline")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.dbNavy)
            }
            
            if let prompt = task.clarificationPrompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Sender: \(task.sourceEmail.senderName) • Subject: \(task.sourceEmail.subject)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.dbSurface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.dbNavy.opacity(0.2), lineWidth: 1)
        )
    }
}
