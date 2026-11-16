import SwiftUI

public struct CarryoverConfirmationSheet: View {
    @ObservedObject var appState: AppState
    let session: WorkSession
    @Environment(\.presentationMode) private var presentationMode
    
    @State private var remainingMinutes: Int
    @State private var carryoverToNextWorkday: Bool
    
    public init(appState: AppState, session: WorkSession, defaultToNextWorkday: Bool = false) {
        self.appState = appState
        self.session = session
        
        // Prefill from existing estimate or session duration
        let initialRemaining: Int
        if let taskId = session.taskId, let task = appState.tasks.first(where: { $0.id == taskId }) {
            let completed = appState.workSessions
                .filter { $0.taskId == taskId && $0.status == .completed }
                .reduce(0) { $0 + $1.durationMinutes }
            let rem = max(15, task.effectiveDuration - completed)
            initialRemaining = min(rem, session.durationMinutes > 0 ? session.durationMinutes : rem)
        } else {
            initialRemaining = session.durationMinutes > 0 ? session.durationMinutes : 45
        }
        
        _remainingMinutes = State(initialValue: initialRemaining)
        _carryoverToNextWorkday = State(initialValue: defaultToNextWorkday)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.forward")
                            .foregroundColor(.dbAccent)
                        Text("Not Done Yet: Carry Over Task")
                            .font(.headline)
                    }
                    Text(session.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            
            Divider()
            
            // Content
            VStack(alignment: .leading, spacing: 18) {
                // Remaining effort input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Remaining Effort")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        TextField("Minutes", value: $remainingMinutes, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        
                        Stepper("", value: $remainingMinutes, in: 5...480, step: 15)
                            .labelsHidden()
                        
                        Text("\(remainingMinutes) minutes (\(formatDuration(remainingMinutes)))")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    
                    Text("Prefilled from existing task estimate. Adjust if less or more time is needed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Destination slot preference
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target Slot")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    Picker("Target Slot", selection: $carryoverToNextWorkday) {
                        Text("Next available slot (today if time remains)").tag(false)
                        Text("First available slot on next working day").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                }
                
                // Explanation Note
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.dbAccent)
                        .font(.caption)
                        .padding(.top, 2)
                    Text("Carried-over tasks are prioritized before ordinary flexible tasks, moving other unlocked future sessions later when necessary.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.dbAccent.opacity(0.08))
                .cornerRadius(6)
            }
            .padding(18)
            
            Divider()
            
            // Footer Action
            HStack {
                Spacer()
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Schedule Carryover") {
                    appState.confirmCarryover(
                        session: session,
                        remainingMinutes: max(5, remainingMinutes),
                        carryoverToNextWorkday: carryoverToNextWorkday
                    )
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.dbAccent)
            }
            .padding(16)
        }
        .frame(width: 480)
    }
    
    private func formatDuration(_ mins: Int) -> String {
        let h = mins / 60
        let m = mins % 60
        if h > 0 && m > 0 {
            return "\(h)h \(m)m"
        } else if h > 0 {
            return "\(h) hr"
        } else {
            return "\(m) min"
        }
    }
}
