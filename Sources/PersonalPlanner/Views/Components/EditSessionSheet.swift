import SwiftUI

public struct EditSessionSheet: View {
    @ObservedObject var appState: AppState
    let session: WorkSession
    @Environment(\.presentationMode) var presentationMode
    
    @State private var startTime: Date
    @State private var durationMinutes: Int
    @State private var isLocked: Bool
    @State private var status: SessionStatus
    @State private var notes: String
    
    // Paid Work Classification
    @State private var isPaidWork: Bool
    @State private var selectedJob: String
    @State private var customJob: String
    @State private var hourlyRateText: String
    @State private var unpaidBreakMinutes: Int
    
    public init(appState: AppState, session: WorkSession) {
        self.appState = appState
        self.session = session
        _startTime = State(initialValue: session.startTime)
        _durationMinutes = State(initialValue: session.durationMinutes)
        _isLocked = State(initialValue: session.isLocked)
        _status = State(initialValue: session.status)
        _notes = State(initialValue: session.notes ?? "")
        
        _isPaidWork = State(initialValue: session.isPaidWork)
        _selectedJob = State(initialValue: session.paidJob ?? "Teaching Assistant")
        _customJob = State(initialValue: "")
        let rate = session.hourlyRate ?? 19
        _hourlyRateText = State(initialValue: "\(rate)")
        _unpaidBreakMinutes = State(initialValue: session.unpaidBreakMinutes)
    }
    
    private var taskTitle: String? {
        guard let taskId = session.taskId else { return nil }
        return appState.tasks.first(where: { $0.id == taskId })?.displayTitle
    }
    
    private var allJobs: [String] {
        var list: [String] = []
        list.append("Other...")
        return list
    }
    
    private var effectiveJob: String {
        if selectedJob == "Other..." {
            return customJob.trimmingCharacters(in: .whitespaces).isEmpty ? "Custom Work" : customJob
        }
        return selectedJob
    }
    
    private var rateDecimal: Decimal {
        Decimal(string: hourlyRateText) ?? 19
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Work Session")
                        .font(.title2)
                        .fontWeight(.bold)
                    if let t = taskTitle {
                        Text("Task: \(t)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text(session.title)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Done") {
                    saveChanges()
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            Form {
                Section("Schedule & Status") {
                    DatePicker("Start Time:", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                    
                    Stepper("Duration: \(durationMinutes) minutes", value: $durationMinutes, in: 15...480, step: 15)
                    
                    Picker("Status:", selection: $status) {
                        ForEach(SessionStatus.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    
                    Toggle("Lock this session (preserves during replanning)", isOn: $isLocked)
                        .help("When locked, regenerating the proposed schedule will never overwrite, move, or delete this work session.")
                }
                
            }
            .formStyle(.grouped)
            
            Divider()
            
            // Actions
            HStack {
                Button(role: .destructive, action: {
                    appState.removeSession(id: session.id)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Label("Remove Session", systemImage: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 480)
    }
    
    private func saveChanges() {
        guard let idx = appState.workSessions.firstIndex(where: { $0.id == session.id }) else { return }
        let newEndTime = startTime.addingTimeInterval(Double(durationMinutes * 60))
        
        appState.workSessions[idx].startTime = startTime
        appState.workSessions[idx].endTime = newEndTime
        appState.workSessions[idx].isLocked = isLocked
        appState.workSessions[idx].status = status
        appState.workSessions[idx].isManuallyAdjusted = true
        appState.workSessions[idx].notes = notes.isEmpty ? nil : notes
        

        appState.recalculateSchedule()
        appState.saveDatabase()
    }
}
