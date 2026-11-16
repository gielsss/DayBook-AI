import SwiftUI

public struct SettingsView: View {
    @ObservedObject var appState: AppState
    
    @State private var startHour: Int = 9
    @State private var endHour: Int = 17
    @State private var sessionMinutes: Int = 45
    @State private var minSessionMinutes: Int = 25
    @State private var breakMinutes: Int = 15
    @State private var lunchHour: Int = 12
    @State private var lunchDuration: Int = 60
    @State private var maxDailyHours: Double = 6.0
    @State private var deadlineBufferMinutes: Int = 60
    @State private var dateOnlyPolicy: DateOnlyDeadlinePolicy = .endOfWorkday
    @State private var includeDemoData: Bool = false
    @State private var weekdaySchedule: [Int: WeekdayHours] = WeekdayHours.defaultSchedule
    
    @State private var showSavedAlert: Bool = false
    
    private let weekdayNames: [(id: Int, name: String)] = [
        (2, "Monday"),
        (3, "Tuesday"),
        (4, "Wednesday"),
        (5, "Thursday"),
        (6, "Friday"),
        (7, "Saturday"),
        (1, "Sunday")
    ]
    
    public init(appState: AppState) {
        self.appState = appState
        _startHour = State(initialValue: appState.preferences.workStartHour)
        _endHour = State(initialValue: appState.preferences.workEndHour)
        _sessionMinutes = State(initialValue: appState.preferences.defaultSessionMinutes)
        _minSessionMinutes = State(initialValue: appState.preferences.minSessionMinutes)
        _breakMinutes = State(initialValue: appState.preferences.breakMinutes)
        _lunchHour = State(initialValue: appState.preferences.lunchStartHour)
        _lunchDuration = State(initialValue: appState.preferences.lunchDurationMinutes)
        _maxDailyHours = State(initialValue: Double(appState.preferences.maxDailyWorkMinutes) / 60.0)
        _deadlineBufferMinutes = State(initialValue: appState.preferences.deadlineBufferMinutes)
        _dateOnlyPolicy = State(initialValue: appState.preferences.dateOnlyDeadlinePolicy)
        _includeDemoData = State(initialValue: appState.preferences.includeDemoDataInPlan)
        _weekdaySchedule = State(initialValue: appState.preferences.weekdayWorkingHours)
    }
    
    private var databaseFilePath: String {
        appState.storageService.databaseURL.path
    }
    
    private var databaseFileSizeFormatted: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: databaseFilePath),
              let size = attrs[.size] as? Int64 else {
            return "File created on save"
        }
        let kb = Double(size) / 1024.0
        return String(format: "%.1f KB", kb)
    }
    
    @AppStorage(DayBookAppearance.storageKey) private var appearance: DayBookAppearance = .system

    private func prefBinding(_ key: WritableKeyPath<UserPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { appState.preferences[keyPath: key] },
            set: { value in
                var prefs = appState.preferences
                prefs[keyPath: key] = value
                appState.updatePreferences(prefs)
            }
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                DayBookPageHeader("Settings", subtitle: "Working hours, scheduling, connections and storage")

                GroupBox(label: Label("Appearance", systemImage: "paintpalette").font(.headline)) {
                    HStack {
                        Text("Look")
                        Spacer()
                        Picker("", selection: $appearance) {
                            ForEach(DayBookAppearance.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    .padding(10)
                }
                
                GroupBox(label: Label("Backups", systemImage: "clock.arrow.circlepath").font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if let last = appState.lastBackupDate {
                                Text("Last backup: \(last.formatted(date: .abbreviated, time: .shortened))")
                            } else {
                                Text("No backup yet")
                            }
                            Spacer()
                            Button("Show in Finder") { appState.revealBackupsInFinder() }
                            Button("Back Up Now") { appState.backUpNow() }
                        }
                        Text(Self.backupExplanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let error = appState.backupErrorMessage {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Label("Sync", systemImage: "arrow.triangle.2.circlepath").font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Sync automatically at 8 AM, 1 PM and 6 PM", isOn: Binding(
                            get: { appState.preferences.autoSyncEnabled },
                            set: { enabled in
                                var prefs = appState.preferences
                                prefs.autoSyncEnabled = enabled
                                appState.updatePreferences(prefs)
                            }
                        ))
                        Toggle("Morning summary notification", isOn: Binding(
                            get: { appState.preferences.morningSummaryEnabled },
                            set: { enabled in
                                var prefs = appState.preferences
                                prefs.morningSummaryEnabled = enabled
                                appState.updatePreferences(prefs)
                            }
                        ))
                        Toggle("Keep today's plan steady after the morning summary", isOn: prefBinding(\.keepTodaySteady))
                        Toggle("Learn from how long tasks actually take", isOn: prefBinding(\.learnFromActualTime))
                        Toggle("Evening check-in at 6 PM (Done / Not Done Yet)", isOn: prefBinding(\.eveningCheckInEnabled))
                        Toggle("Estimate Canvas and Gradescope work time with AI", isOn: Binding(
                            get: { appState.preferences.aiTimeEstimatesEnabled },
                            set: { enabled in
                                var prefs = appState.preferences
                                prefs.aiTimeEstimatesEnabled = enabled
                                appState.updatePreferences(prefs)
                            }
                        ))
                        Text("Sync Everything refreshes Apple Calendar, Canvas, Gradescope and email, then re-plans and shows on Today what changed. The morning summary arrives after the 8 AM sync: today's work sessions, what's due, events and tasks that need you. Time estimates are asked of your local model once per assignment and never replace a duration you set. From 8 AM, syncs leave today's sessions where they are and only use free time (Plan My Day still re-plans everything). Finished tasks teach DayBook how far off its estimates are, by kind of work and course. The evening check-in asks about today's sessions you haven't marked done. If Canvas or Gradescope isn't open in your browser, DayBook AI opens it in the background and closes it afterwards. Automatic syncs run while DayBook AI is open; a time missed while your Mac was asleep runs when it wakes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 1. Working Hours for each weekday
                GroupBox(label: Label("Weekday Working Hours", systemImage: "calendar.badge.clock").font(.headline)) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Define your working days and daily working windows:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 8) {
                            ForEach(weekdayNames, id: \.id) { day in
                                let isWorkdayBinding = Binding<Bool>(
                                    get: { weekdaySchedule[day.id]?.isWorkday ?? false },
                                    set: { val in
                                        var current = weekdaySchedule[day.id] ?? WeekdayHours(isWorkday: val)
                                        current.isWorkday = val
                                        weekdaySchedule[day.id] = current
                                    }
                                )
                                let startBinding = Binding<Int>(
                                    get: { weekdaySchedule[day.id]?.startHour ?? startHour },
                                    set: { val in
                                        var current = weekdaySchedule[day.id] ?? WeekdayHours()
                                        current.startHour = val
                                        weekdaySchedule[day.id] = current
                                    }
                                )
                                let endBinding = Binding<Int>(
                                    get: { weekdaySchedule[day.id]?.endHour ?? endHour },
                                    set: { val in
                                        var current = weekdaySchedule[day.id] ?? WeekdayHours()
                                        current.endHour = val
                                        weekdaySchedule[day.id] = current
                                    }
                                )
                                
                                HStack(spacing: 12) {
                                    Toggle(day.name, isOn: isWorkdayBinding)
                                        .frame(width: 120, alignment: .leading)
                                    
                                    if isWorkdayBinding.wrappedValue {
                                        Stepper("Start: \(startBinding.wrappedValue):00 AM", value: startBinding, in: 6...12)
                                        Spacer()
                                        Stepper("End: \(endBinding.wrappedValue > 12 ? endBinding.wrappedValue - 12 : endBinding.wrappedValue):00 PM", value: endBinding, in: 13...22)
                                    } else {
                                        Text("Off / Non-working day")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(isWorkdayBinding.wrappedValue ? Color(NSColor.textBackgroundColor) : Color.clear)
                                .cornerRadius(6)
                            }
                        }
                        
                        Divider()
                        
                        // Lunch Block
                        HStack {
                            Stepper("Lunch Start: \(lunchHour > 12 ? lunchHour - 12 : lunchHour):00 PM", value: $lunchHour, in: 11...14)
                            Spacer()
                            Stepper("Lunch Duration: \(lunchDuration) min", value: $lunchDuration, in: 30...90, step: 15)
                        }
                    }
                    .padding(10)
                }
                
                // 2. Scheduling Rules & Constraints
                GroupBox(label: Label("Scheduling Rules & Limits", systemImage: "slider.horizontal.3").font(.headline)) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Max planned work per day
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Maximum planned work per day:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(String(format: "%.1f hours (%d mins)", maxDailyHours, Int(maxDailyHours * 60)))
                                    .foregroundColor(.dbAccent)
                                    .fontWeight(.bold)
                            }
                            Slider(value: $maxDailyHours, in: 2.0...10.0, step: 0.5)
                            Text("Prevents scheduling burnout. Work sessions scheduled on any single day will never exceed this cap.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Session lengths: preferred & minimum useful
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Preferred Session Duration")
                                Spacer()
                                Picker("", selection: $sessionMinutes) {
                                    Text("30 minutes").tag(30)
                                    Text("45 minutes (recommended)").tag(45)
                                    Text("60 minutes").tag(60)
                                    Text("90 minutes").tag(90)
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .fixedSize()
                            }
                            
                            HStack {
                                Text("Minimum Useful Session")
                                Spacer()
                                Picker("", selection: $minSessionMinutes) {
                                    Text("15 minutes").tag(15)
                                    Text("25 minutes (recommended)").tag(25)
                                    Text("30 minutes").tag(30)
                                    Text("45 minutes").tag(45)
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .fixedSize()
                            }
                        }
                        
                        Divider()
                        
                        // Break duration
                        HStack {
                            Text("Break Duration Between Sessions")
                            Spacer()
                            Picker("", selection: $breakMinutes) {
                                Text("10 minutes").tag(10)
                                Text("15 minutes (recommended)").tag(15)
                                Text("20 minutes").tag(20)
                                Text("30 minutes").tag(30)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }
                        
                        Divider()
                        
                        // Buffer before deadlines
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Buffer Before Deadlines")
                                Spacer()
                                Picker("", selection: $deadlineBufferMinutes) {
                                    Text("None").tag(0)
                                    Text("30 minutes").tag(30)
                                    Text("1 hour (recommended)").tag(60)
                                    Text("2 hours").tag(120)
                                    Text("4 hours").tag(240)
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .fixedSize()
                            }
                            Text("All planned work sessions must finish at least this far in advance of the deadline.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Date-only deadline policy
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Date-Only Deadline Cutoff")
                                Spacer()
                                Picker("", selection: $dateOnlyPolicy) {
                                    ForEach(DateOnlyDeadlinePolicy.allCases) { policy in
                                        Text(policy.shortTitle).tag(policy)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .fixedSize()
                            }
                            Text(dateOnlyPolicy.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Demonstration data in plan toggle
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Include sample demonstration tasks and commitments in proposed plan", isOn: $includeDemoData)
                                .font(.subheadline)
                            Text("Off by default: ensures test assignments and demo calendar events do not affect your real plan.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if appState.tasks.contains(where: { $0.sourceEmail.isSimulatedDemo }) {
                                Button(role: .destructive) {
                                    appState.removeDemonstrationData()
                                } label: {
                                    Label("Remove All Demonstration Tasks", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .padding(.top, 4)
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            Spacer()
                            Button("Apply & Generate Proposed Schedule") {
                                savePreferences()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(10)
                }
                
                // 3. Gmail Connection (Desktop OAuth 2.0)
                GmailConnectionCard(appState: appState)
                
                // 4. Local AI (Ollama) for email scanning, Quick Capture and receipts
                AISettingsCard(appState: appState)
                
                // 5. Canvas LMS
                CanvasSettingsCard(appState: appState)
                GradescopeSettingsCard(appState: appState)
                
                // 5. Apple Calendar Connection (EventKit)
                AppleCalendarSettingsCard(appState: appState)
                
                // 6. Quick Capture Configuration
                QuickCaptureSettingsCard(appState: appState)
                

                // 6. Other External Connections
                GroupBox(label: Label("Other System Integrations", systemImage: "network").font(.headline)) {
                    VStack(alignment: .leading, spacing: 14) {
                        connectionRow(
                            name: "macOS Keychain",
                            statusText: "Ready & Active",
                            description: "Google OAuth credentials are securely stored in your native macOS Keychain (`Security.framework`).",
                            statusColor: .green,
                            systemImage: "lock.shield"
                        )
                    }
                    .padding(10)
                }
                
                // 7. Local Storage & Persistence Diagnostics
                GroupBox(label: Label("Local Storage & Persistence", systemImage: "internaldrive").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Persistent Local File Location:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(databaseFilePath)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                        
                        HStack(spacing: 20) {
                            Text("Database Size: **\(databaseFileSizeFormatted)**")
                                .font(.caption)
                            Text("Tasks: **\(appState.tasks.count)**")
                                .font(.caption)
                            Text("Work Sessions: **\(appState.workSessions.count)**")
                                .font(.caption)
                            Text("Commitments: **\(appState.commitments.count)**")
                                .font(.caption)
                            Spacer()
                        }
                        
                        Divider()
                        
                        HStack(spacing: 12) {
                            Button("Reload from Disk") {
                                appState.loadDatabase()
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Reset to Demonstration Data") {
                                appState.resetToDemoData()
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Open Storage Folder in Finder") {
                                let dir = URL(fileURLWithPath: databaseFilePath).deletingLastPathComponent()
                                NSWorkspace.shared.selectFile(databaseFilePath, inFileViewerRootedAtPath: dir.path)
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                        }
                    }
                    .padding(10)
                }
            }
            .padding(24)
        }
        .alert("Preferences Saved", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your weekday hours, scheduling constraints, and session preferences have been saved locally to disk and work sessions have been replanned.")
        }
    }
    
    static let backupExplanation = "Every day DayBook AI copies your planner into a Backups folder and keeps the last 14 days."

    private func savePreferences() {
        var prefs = appState.preferences
        prefs.workStartHour = startHour
        prefs.workEndHour = endHour
        prefs.defaultSessionMinutes = sessionMinutes
        prefs.minSessionMinutes = minSessionMinutes
        prefs.breakMinutes = breakMinutes
        prefs.lunchStartHour = lunchHour
        prefs.lunchDurationMinutes = lunchDuration
        prefs.maxDailyWorkMinutes = Int(maxDailyHours * 60)
        prefs.deadlineBufferMinutes = deadlineBufferMinutes
        prefs.dateOnlyDeadlinePolicy = dateOnlyPolicy
        prefs.includeDemoDataInPlan = includeDemoData
        prefs.weekdayWorkingHours = weekdaySchedule
        appState.updatePreferences(prefs)
        showSavedAlert = true
    }
    
    private func connectionRow(
        name: String,
        statusText: String,
        description: String,
        statusColor: Color,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundColor(statusColor)
                .font(.title3)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(statusText)
                        .font(.caption.weight(.medium))
                        .foregroundColor(statusColor)
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
