import SwiftUI

public struct CalendarDiscrepancySheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private var discrepancies: [ExternalDiscrepancy] {
        appState.externalDiscrepancies
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                            .font(.title2)
                            .foregroundColor(.orange)
                        Text("Apple Calendar Discrepancies")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    Text("External changes were detected in Apple Calendar. Review each item and choose how to reconcile.")
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
            
            if discrepancies.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    Text("No Calendar Discrepancies")
                        .font(.headline)
                    Text("All work sessions are in sync with your Apple Calendar events and have no external conflicts.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(discrepancies) { item in
                            discrepancyCard(item: item)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 460)
    }
    
    private func discrepancyCard(item: ExternalDiscrepancy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.sessionTitle)
                    .font(.headline)
                Spacer()
                kindBadge(for: item.kind)
            }
            
            switch item.kind {
            case .movedInCalendar(let newStart, let newEnd):
                VStack(alignment: .leading, spacing: 4) {
                    Text("This event was moved or rescheduled directly in Apple Calendar:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .foregroundColor(.dbNavy)
                        Text("New Calendar Time: \(formatTimeRange(start: newStart, end: newEnd))")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                
                HStack(spacing: 10) {
                    Button("Adopt Calendar Change") {
                        Task {
                            await appState.resolveDiscrepancy(item, action: .adoptExternalChange)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Restore Planner Version") {
                        Task {
                            await appState.resolveDiscrepancy(item, action: .restorePlannerVersion)
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Dismiss") {
                        Task {
                            await appState.resolveDiscrepancy(item, action: .dismissAlert)
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                }
                .padding(.top, 4)
                
            case .deletedInCalendar:
                VStack(alignment: .leading, spacing: 4) {
                    Text("This event was deleted directly in Apple Calendar.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("DayBook AI will never automatically overwrite external deletions or recreate deleted events without your explicit choice.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 10) {
                    Button("Adopt Deletion (Remove in Planner)") {
                        Task {
                            await appState.resolveDiscrepancy(item, action: .adoptExternalChange)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Re-publish to Calendar") {
                        Task {
                            await appState.resolveDiscrepancy(item, action: .restorePlannerVersion)
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Dismiss") {
                        Task {
                            await appState.resolveDiscrepancy(item, action: .dismissAlert)
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                }
                .padding(.top, 4)
                
            case .externalConflict(let confTitle, let confStart, let confEnd):
                VStack(alignment: .leading, spacing: 4) {
                    Text("A new or modified external event conflicts with this planned session:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .foregroundColor(.red)
                        Text("\(confTitle) (\(formatTimeRange(start: confStart, end: confEnd)))")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                    }
                }
                
                HStack(spacing: 10) {
                    Button("Replan Schedule Around Conflict") {
                        Task {
                            await appState.resolveDiscrepancy(item, action: .adoptExternalChange)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                    
                    Button("Dismiss Alert") {
                        Task {
                            await appState.resolveDiscrepancy(item, action: .dismissAlert)
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                }
                .padding(.top, 4)
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
    
    private func kindBadge(for kind: ExternalDiscrepancyKind) -> some View {
        switch kind {
        case .movedInCalendar:
            return Text("Moved in Calendar")
     .font(.caption.weight(.medium))
     .foregroundColor(.dbNavy)
        case .deletedInCalendar:
            return Text("Deleted in Calendar")
     .font(.caption.weight(.medium))
     .foregroundColor(.orange)
        case .externalConflict:
            return Text("External Conflict")
     .font(.caption.weight(.medium))
     .foregroundColor(.red)
        }
    }
    
    private func formatTimeRange(start: Date, end: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        let tf = DateFormatter()
        tf.dateStyle = .none
        tf.timeStyle = .short
        return "\(df.string(from: start)) – \(tf.string(from: end))"
    }
}
