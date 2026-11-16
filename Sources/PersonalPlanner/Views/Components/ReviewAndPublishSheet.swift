import SwiftUI

public struct ReviewAndPublishSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedAddIds: Set<UUID> = []
    @State private var selectedUpdateIds: Set<UUID> = []
    @State private var selectedRemoveIds: Set<UUID> = []
    @State private var hasInitializedSelection: Bool = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private var plan: CalendarPublicationPlan {
        appState.computePublicationPlan()
    }
    
    private var totalSelectedCount: Int {
        selectedAddIds.count + selectedUpdateIds.count + selectedRemoveIds.count
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.title2)
                            .foregroundColor(.dbNavy)
                        Text("Review & Publish to Apple Calendar")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    Text("Approve proposed work sessions before anything is written to your calendar.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.bordered)
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Destination Calendar & Provider Sync Card
                    destinationCalendarCard
                    
                    // Demo sessions exclusion notice if any demo sessions exist
                    let demoCount = appState.workSessions.filter { $0.isSimulatedDemo }.count
                    if demoCount > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "shield.lefthalf.filled")
                                .foregroundColor(.dbAccent)
                            Text("\(demoCount) demonstration session\(demoCount == 1 ? "" : "s") excluded from Apple Calendar publication.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.dbAccent.opacity(0.08))
                        .cornerRadius(8)
                    }
                    
                    // Publishing feedback / errors
                    if let error = appState.publishErrorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Publication Issue")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    if let status = appState.publishStatusMessage, appState.publishErrorMessage == nil {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(status)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        .padding(12)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Changes Overview
                    if !plan.hasChanges {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.green)
                            Text("Apple Calendar is Up to Date")
                                .font(.headline)
                            Text("All active work sessions are already synchronized with your dedicated DayBook AI calendar.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        // Batch selection bar
                        HStack {
                            Text("Proposed Calendar Modifications")
                                .font(.headline)
                            Spacer()
                            Button(totalSelectedCount == plan.totalChangeCount ? "Deselect All" : "Select All") {
                                toggleSelectAll()
                            }
                            .buttonStyle(.borderless)
                            .font(.subheadline)
                            .foregroundColor(.dbNavy)
                        }
                        
                        // 1. Sessions to Add
                        if !plan.toAdd.isEmpty {
                            changesSection(
                                title: "To Add (\(plan.toAdd.count))",
                                subtitle: "New focus sessions to create in Apple Calendar",
                                icon: "plus.circle.fill",
                                iconColor: .green
                            ) {
                                ForEach(plan.toAdd) { session in
                                    sessionRow(
                                        session: session,
                                        isSelected: selectedAddIds.contains(session.id),
                                        toggleAction: {
                                            if selectedAddIds.contains(session.id) {
                                                selectedAddIds.remove(session.id)
                                            } else {
                                                selectedAddIds.insert(session.id)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        
                        // 2. Sessions to Update
                        if !plan.toUpdate.isEmpty {
                            changesSection(
                                title: "To Update (\(plan.toUpdate.count))",
                                subtitle: "Sessions adjusted locally that need time or title updates in Apple Calendar",
                                icon: "arrow.triangle.2.circlepath.circle.fill",
                                iconColor: .orange
                            ) {
                                ForEach(plan.toUpdate) { session in
                                    sessionUpdateRow(
                                        session: session,
                                        isSelected: selectedUpdateIds.contains(session.id),
                                        toggleAction: {
                                            if selectedUpdateIds.contains(session.id) {
                                                selectedUpdateIds.remove(session.id)
                                            } else {
                                                selectedUpdateIds.insert(session.id)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        
                        // 3. Sessions to Remove
                        if !plan.toRemove.isEmpty {
                            changesSection(
                                title: "To Remove (\(plan.toRemove.count))",
                                subtitle: "Sessions deleted or replanned locally to remove from Apple Calendar",
                                icon: "minus.circle.fill",
                                iconColor: .red
                            ) {
                                ForEach(plan.toRemove) { session in
                                    sessionRemoveRow(
                                        session: session,
                                        isSelected: selectedRemoveIds.contains(session.id),
                                        toggleAction: {
                                            if selectedRemoveIds.contains(session.id) {
                                                selectedRemoveIds.remove(session.id)
                                            } else {
                                                selectedRemoveIds.insert(session.id)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            
            Divider()
            
            // Footer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(totalSelectedCount) of \(plan.totalChangeCount) change\(plan.totalChangeCount == 1 ? "" : "s") selected")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Unselected changes remain local proposals and will not touch Apple Calendar.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if appState.isPublishingCalendar {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(appState.publishStatusMessage ?? "Publishing...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.trailing, 8)
                }
                
                Button(action: {
                    Task {
                        await appState.publishApprovedSessions(
                            selectedAddSessionIds: selectedAddIds,
                            selectedUpdateSessionIds: selectedUpdateIds,
                            selectedRemoveSessionIds: selectedRemoveIds
                        )
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.doc.fill")
                        Text(plan.hasChanges ? "Publish Approved (\(totalSelectedCount))" : "Re-sync Calendar")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isPublishingCalendar || (plan.hasChanges && totalSelectedCount == 0))
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 520)
        .onAppear {
            initializeSelection()
            Task {
                await appState.setupPlannerCalendar()
            }
        }
    }
    
    private var destinationCalendarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(Color(hex: appState.publicationCalendarInfo?.colorHex ?? "#007AFF"))
                    .frame(width: 12, height: 12)
                Text(appState.publicationCalendarInfo?.title ?? "DayBook AI")
                    .font(.headline)
                Spacer()
                Text("Dedicated Calendar")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.dbNavy)
            }
            
            Text(appState.publicationCalendarInfo?.providerSyncDescription ?? "Events stay strictly local on this Mac (On My Mac). Not synced to external cloud servers.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("Privacy: Only session title and times are published. Email bodies, task excerpts, and credentials are never written to calendar.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dbSurface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func changesSection<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.headline)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 6) {
                content()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dbSurface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func sessionRow(session: WorkSession, isSelected: Bool, toggleAction: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: toggleAction) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .dbNavy : .secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(formatTimeRange(start: session.startTime, end: session.endTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("\(session.durationMinutes)m")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(8)
        .background(isSelected ? Color.dbNavy.opacity(0.04) : Color.clear)
        .cornerRadius(6)
    }
    
    private func sessionUpdateRow(session: WorkSession, isSelected: Bool, toggleAction: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: toggleAction) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .dbNavy : .secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    if let lastStart = session.lastPublishedStartTime, let lastEnd = session.lastPublishedEndTime {
                        Text(formatTimeRange(start: lastStart, end: lastEnd))
                            .font(.caption)
                            .strikethrough()
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                    Text(formatTimeRange(start: session.startTime, end: session.endTime))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
            }
            Spacer()
        }
        .padding(8)
        .background(isSelected ? Color.orange.opacity(0.04) : Color.clear)
        .cornerRadius(6)
    }
    
    private func sessionRemoveRow(session: WorkSession, isSelected: Bool, toggleAction: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: toggleAction) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .red : .secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough()
                    .foregroundColor(.secondary)
                Text(formatTimeRange(start: session.startTime, end: session.endTime))
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Spacer()
        }
        .padding(8)
        .background(isSelected ? Color.red.opacity(0.04) : Color.clear)
        .cornerRadius(6)
    }
    
    private func initializeSelection() {
        if !hasInitializedSelection {
            selectedAddIds = Set(plan.toAdd.map { $0.id })
            selectedUpdateIds = Set(plan.toUpdate.map { $0.id })
            selectedRemoveIds = Set(plan.toRemove.map { $0.id })
            hasInitializedSelection = true
        }
    }
    
    private func toggleSelectAll() {
        if totalSelectedCount == plan.totalChangeCount {
            selectedAddIds.removeAll()
            selectedUpdateIds.removeAll()
            selectedRemoveIds.removeAll()
        } else {
            selectedAddIds = Set(plan.toAdd.map { $0.id })
            selectedUpdateIds = Set(plan.toUpdate.map { $0.id })
            selectedRemoveIds = Set(plan.toRemove.map { $0.id })
        }
    }
    
    private func formatTimeRange(start: Date, end: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        df.timeZone = appState.preferences.timeZone
        let tf = DateFormatter()
        tf.dateStyle = .none
        tf.timeStyle = .short
        tf.timeZone = appState.preferences.timeZone
        let tzAbbr = appState.preferences.timeZone.abbreviation(for: start).map { " (\($0))" } ?? ""
        return "\(df.string(from: start)) – \(tf.string(from: end))\(tzAbbr)"
    }
}
