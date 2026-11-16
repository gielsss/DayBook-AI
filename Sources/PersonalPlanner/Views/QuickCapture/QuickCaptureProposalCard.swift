import SwiftUI

public struct QuickCaptureProposalCard: View {
    @Binding public var proposal: QuickCaptureProposal
    public let timeZone: TimeZone
    public let onSaveTask: (QuickCaptureProposal) -> Void
    public let onSaveEvent: (QuickCaptureProposal) -> Void
    public let onDiscard: (UUID) -> Void
    
    @State private var hasPlanningTarget: Bool = false
    @State private var showDetails: Bool = false
    
    public init(
        proposal: Binding<QuickCaptureProposal>,
        timeZone: TimeZone,
        onSaveTask: @escaping (QuickCaptureProposal) -> Void,
        onSaveEvent: @escaping (QuickCaptureProposal) -> Void,
        onDiscard: @escaping (UUID) -> Void
    ) {
        self._proposal = proposal
        self.timeZone = timeZone
        self.onSaveTask = onSaveTask
        self.onSaveEvent = onSaveEvent
        self.onDiscard = onDiscard
        self._hasPlanningTarget = State(initialValue: proposal.wrappedValue.planningTargetDate != nil)
    }
    
    private var typeBadgeColor: Color {
        switch proposal.proposalType {
        case .task: return .dbNavy
        case .confirmedEvent: return .green
        case .tentativeEvent: return .orange
        case .noAction: return .secondary
        }
    }
    
    private var formattedDeadline: String {
        guard let d = proposal.extractedDeadline else {
            if let dateOnly = proposal.dateOnlyString {
                return "\(dateOnly) (Date-Only)"
            }
            return "No deadline in content"
        }
        let df = DateFormatter()
        df.timeZone = timeZone
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: d)
    }
    
    private var formattedEventTiming: String {
        guard let start = proposal.eventStartTime else { return "Timing not specified" }
        let df = DateFormatter()
        df.timeZone = timeZone
        df.dateStyle = .medium
        df.timeStyle = .short
        let startStr = df.string(from: start)
        if let end = proposal.eventEndTime {
            let tf = DateFormatter()
            tf.timeZone = timeZone
            tf.timeStyle = .short
            return "\(startStr) – \(tf.string(from: end))"
        }
        return startStr
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row: Type Badge + Duplicate Warning + Discard
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: proposal.proposalType == .task ? "checklist" : (proposal.isTentative ? "calendar.badge.clock" : "calendar"))
                        .font(.caption2)
                    Text(proposal.proposalType.badgeTitle)
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(typeBadgeColor.opacity(0.15))
                .foregroundColor(typeBadgeColor)
                .cornerRadius(5)
                
                if proposal.isTentative {
                    Text("Tentative")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                if proposal.isSaved {
                    Label("Saved to Planner", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if proposal.isDiscarded {
                    Text("Discarded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Button(action: {
                        onDiscard(proposal.id)
                    }) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Discard proposal")
                }
            }
            
            // Duplicate Warning Banner
            if let warning = proposal.duplicateWarning, !proposal.isSaved {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(warning)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Title & Content Fields
            if proposal.proposalType == .task {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Task Title", text: $proposal.title)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    if !proposal.requiredAction.isEmpty {
                        HStack(alignment: .top, spacing: 4) {
                            Text("Action:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Required Action", text: $proposal.requiredAction)
                                .textFieldStyle(.plain)
                                .font(.caption)
                        }
                    }
                    
                    // Deadline & Duration Row
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formattedDeadline)
                                .font(.caption)
                                .foregroundColor(proposal.extractedDeadline == nil ? .secondary : .primary)
                        }
                        
                        // Provenance Badge
                        Text(proposal.deadlineProvenance.badgeTitle)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                        
                        Spacer()
                        
                        // Duration Picker
                        HStack(spacing: 4) {
                            Text("Effort:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Picker("", selection: $proposal.estimatedDurationMinutes) {
                                Text("15m").tag(15)
                                Text("30m").tag(30)
                                Text("45m").tag(45)
                                Text("60m (1h)").tag(60)
                                Text("90m (1.5h)").tag(90)
                                Text("120m (2h)").tag(120)
                                Text("180m (3h)").tag(180)
                            }
                            .labelsHidden()
                            .frame(width: 80)
                            
                            if proposal.isDurationInferred {
                                Text("(Inferred)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Planning Target (When Deadline is missing/unsupported)
                    if proposal.extractedDeadline == nil {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Set User-Selected Planning Target", isOn: $hasPlanningTarget)
                                .font(.caption)
                                .onChange(of: hasPlanningTarget) { enabled in
                                    if enabled {
                                        if proposal.planningTargetDate == nil {
                                            proposal.planningTargetDate = Date().addingTimeInterval(86400 * 2)
                                        }
                                    } else {
                                        proposal.planningTargetDate = nil
                                    }
                                }
                            
                            if hasPlanningTarget {
                                DatePicker(
                                    "Target:",
                                    selection: Binding(
                                        get: { proposal.planningTargetDate ?? Date().addingTimeInterval(86400 * 2) },
                                        set: { proposal.planningTargetDate = $0 }
                                    ),
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .datePickerStyle(.compact)
                                .font(.caption)
                            }
                        }
                        .padding(6)
                        .background(Color.dbNavy.opacity(0.06))
                        .cornerRadius(6)
                    }
                }
            } else if proposal.proposalType == .confirmedEvent || proposal.proposalType == .tentativeEvent {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Event Title", text: $proposal.eventTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formattedEventTiming)
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        if let orig = proposal.originalTimingWording {
                            Text("(\"\(orig)\")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let loc = proposal.location, !loc.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(loc)
                                .font(.caption)
                        }
                    }
                    
                    if !proposal.attendees.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(proposal.attendees.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Supporting Excerpt
            if !proposal.supportingExcerpt.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Text("“")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(proposal.supportingExcerpt)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                        .lineLimit(2)
                }
            }
            
            // Action Buttons
            HStack {
                if !proposal.inferredDetails.isEmpty {
                    Text(proposal.inferredDetails.first ?? "")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !proposal.isSaved && !proposal.isDiscarded {
                    if proposal.proposalType == .task {
                        Button("Add Task") {
                            onSaveTask(proposal)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else if proposal.proposalType == .confirmedEvent || proposal.proposalType == .tentativeEvent {
                        Button(proposal.isTentative ? "Add Tentative Event" : "Add Event") {
                            onSaveEvent(proposal)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.dbSurface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(proposal.isSaved ? Color.green.opacity(0.4) : (proposal.duplicateWarning != nil ? Color.orange.opacity(0.4) : Color.secondary.opacity(0.15)), lineWidth: 1)
        )
    }
}
