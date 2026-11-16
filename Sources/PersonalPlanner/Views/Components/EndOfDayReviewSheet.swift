import SwiftUI

public struct EndOfDayReviewSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    
    @State private var sessionForCarryover: WorkSession? = nil
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "sunset.fill")
                            .foregroundColor(.orange)
                        Text("End-of-Day Review")
                            .font(.headline)
                    }
                    Text("Review incomplete sessions from today. Check off finished work or carry over remaining effort.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            
            Divider()
            
            let incomplete = appState.endOfDayIncompleteSessions
            
            if incomplete.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 44))
                    Text("You're all done for today!")
                        .font(.headline)
                    Text("All scheduled sessions for today have been completed or carried over.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(incomplete) { session in
                            sessionReviewRow(session: session)
                        }
                    }
                    .padding(16)
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                if !incomplete.isEmpty {
                    Button(action: {
                        carryOverAllToNextWorkday(sessions: incomplete)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.forward")
                            Text("Carry Over All to Next Workday")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 540, height: 420)
        .sheet(item: $sessionForCarryover) { session in
            CarryoverConfirmationSheet(appState: appState, session: session, defaultToNextWorkday: true)
        }
    }
    
    @ViewBuilder
    private func sessionReviewRow(session: WorkSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "deskclock.fill")
                .foregroundColor(session.isCarryover ? .dbAccent : .orange)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if session.isCarryover {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.system(size: 8))
                            Text("Carryover")
                        }
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.dbAccent.opacity(0.18))
                        .foregroundColor(.dbAccent)
                        .cornerRadius(3)
                    }
                }
                
                Text("\(formatTime(session.startTime)) - \(formatTime(session.endTime)) (\(session.durationMinutes)m)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action buttons: Complete or Not Done Yet
            HStack(spacing: 8) {
                Button(action: {
                    appState.toggleSessionStatus(id: session.id)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                        Text("Complete")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: {
                    sessionForCarryover = session
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.forward")
                        Text("Not Done Yet")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.dbAccent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.dbSurface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func carryOverAllToNextWorkday(sessions: [WorkSession]) {
        for s in sessions {
            appState.confirmCarryover(session: s, remainingMinutes: s.durationMinutes, carryoverToNextWorkday: true)
        }
        presentationMode.wrappedValue.dismiss()
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = appState.preferences.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
