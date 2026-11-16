import SwiftUI

public struct CreateActivitySheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    
    @State private var title: String = ""
    @State private var startTime: Date = Date()
    @State private var durationMinutes: Int = 60
    @State private var notes: String = ""
    
    // Paid Work Classification
    @State private var isPaidWork: Bool = false
    @State private var selectedJob: String = "Teaching Assistant"
    @State private var customJob: String = ""
    @State private var hourlyRateText: String = "19.00"
    @State private var unpaidBreakMinutes: Int = 0
    
    public init(appState: AppState, initialDate: Date = Date()) {
        self.appState = appState
        _startTime = State(initialValue: initialDate)
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
    
    private var plannedPaidHours: Decimal {
        let paidMins = max(0, durationMinutes - unpaidBreakMinutes)
        var rounded = Decimal()
        var mut = Decimal(paidMins) / 60
        NSDecimalRound(&rounded, &mut, 2, .plain)
        return rounded
    }
    
    private var expectedEarnings: Decimal {
        var rounded = Decimal()
        var mut = plannedPaidHours * rateDecimal
        NSDecimalRound(&rounded, &mut, 2, .plain)
        return rounded
    }
    
    static let subtitle = "Schedule an activity or study session"

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Planner Activity")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(Self.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            Divider()
            
            Form {
                Section("Activity Details") {
                    TextField("Activity Title:", text: $title)
                    
                    DatePicker("Start Time:", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                    
                    Stepper("Duration: \(durationMinutes) minutes (\(durationMinutes / 60)h \(durationMinutes % 60)m)", value: $durationMinutes, in: 15...480, step: 15)
                    
                    TextField("Notes (optional):", text: $notes)
                }
                
            }
            .formStyle(.grouped)
            
            Divider()
            
            // Actions
            HStack {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: {
                    let activityTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? (isPaidWork ? effectiveJob : "Work Session") : title
                    let endTime = startTime.addingTimeInterval(Double(durationMinutes * 60))
                    
                    let newSession = WorkSession(
                        title: activityTitle,
                        startTime: startTime,
                        endTime: endTime,
                        status: .planned,
                        notes: notes.isEmpty ? nil : notes,
                        isLocked: true, // Manual activities are locked against automatic replanning overwrite
                        isManuallyAdjusted: true,
                        isSimulatedDemo: false,
                        isPaidWork: isPaidWork,
                        paidJob: isPaidWork ? effectiveJob : nil,
                        hourlyRate: isPaidWork ? rateDecimal : nil,
                        unpaidBreakMinutes: isPaidWork ? unpaidBreakMinutes : 0
                    )
                    
                    appState.addWorkSession(newSession)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Label("Add Activity", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 480)
    }
}
