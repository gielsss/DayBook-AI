import SwiftUI

public struct AppleCalendarSettingsCard: View {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private var statusBadge: some View {
        switch appState.calendarAuthorizationStatus {
        case .authorized:
            return Text("Connected")
     .font(.caption.weight(.medium))
     .foregroundColor(.green)
        case .notDetermined:
            return Text("Not Connected")
     .font(.caption.weight(.medium))
     .foregroundColor(.orange)
        case .denied, .restricted:
            return Text("Access Denied")
     .font(.caption.weight(.medium))
     .foregroundColor(.red)
        }
    }
    
    private func formatRefreshTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    public var body: some View {
        GroupBox(label: Label("Apple Calendar (EventKit)", systemImage: "calendar").font(.headline)) {
            VStack(alignment: .leading, spacing: 14) {
                // Header status row
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Calendar Integration")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("DayBook AI reads your local and iCloud Apple Calendar events to visualize your schedule and protect occupied time. Calendar events stay on your Mac and are never sent to external servers.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    statusBadge
                }
                
                Divider()
                
                // Content depending on authorization status
                switch appState.calendarAuthorizationStatus {
                case .notDetermined:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Connect your Apple Calendar to display real commitments for the next 14 days and schedule work around them.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            Task {
                                await appState.requestCalendarAccess()
                            }
                        }) {
                            Label("Connect Apple Calendar", systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                case .denied, .restricted:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Calendar permission was denied. macOS requires you to grant calendar access in System Settings before DayBook AI can read your schedule.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 10) {
                            Button(action: {
                                appState.openSystemCalendarSettings()
                            }) {
                                Label("Open Privacy & Security Settings", systemImage: "gearshape")
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button(action: {
                                Task {
                                    await appState.refreshCalendarCommitments(isAutomatic: false)
                                }
                            }) {
                                Label("Check Again", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                case .authorized:
                    VStack(alignment: .leading, spacing: 14) {
                        // Refresh button and last sync
                        HStack {
                            Button(action: {
                                Task {
                                    await appState.refreshCalendarCommitments(isAutomatic: false)
                                }
                            }) {
                                if appState.isRefreshingCalendar {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("Refreshing...")
                                    }
                                } else {
                                    Label("Refresh Calendar Now", systemImage: "arrow.clockwise")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(appState.isRefreshingCalendar)
                            
                            if let lastSync = appState.lastCalendarRefreshDate {
                                Text("Last refreshed: \(formatRefreshTime(lastSync))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        
                        Divider()
                        
                        // Calendar selection list
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Calendars Counting Toward Availability:")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(appState.selectedCalendarIds.count) of \(appState.availableCalendars.count) selected")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Only events from selected calendars will be displayed and treated as occupied time.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if appState.availableCalendars.isEmpty {
                                Text("No calendars discovered in Apple Calendar.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 4)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(appState.availableCalendars) { cal in
                                        let isSelected = appState.selectedCalendarIds.contains(cal.id)
                                        Button(action: {
                                            appState.toggleCalendarSelection(id: cal.id)
                                        }) {
                                            HStack(spacing: 8) {
                                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                                    .foregroundColor(isSelected ? .dbAccent : .secondary)
                                                    .font(.system(size: 14))
                                                
                                                Circle()
                                                    .fill(Color(hex: cal.colorHex))
                                                    .frame(width: 10, height: 10)
                                                
                                                Text(cal.title)
                                                    .font(.subheadline)
                                                    .foregroundColor(.primary)
                                                
                                                Text("(\(cal.sourceTitle))")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                
                                                Spacer()
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(8)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(6)
                            }
                        }
                        
                        Divider()
                        
                        // Dedicated Publication Calendar
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Dedicated Work Sessions Calendar")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("DayBook AI publishes approved work sessions to a dedicated calendar so they stay separated from your personal appointments.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            let writableCalendars = appState.availableCalendars.filter { $0.allowsModifications }
                            
                            HStack(spacing: 12) {
                                Picker("Calendar:", selection: Binding(
                                    get: {
                                        appState.preferences.publicationCalendarIdentifier ?? writableCalendars.first(where: { EventKitCalendarService.plannerCalendarTitles.contains($0.title) })?.id ?? writableCalendars.first?.id ?? ""
                                    },
                                    set: { newId in
                                        appState.preferences.publicationCalendarIdentifier = newId
                                        if let found = writableCalendars.first(where: { $0.id == newId }) {
                                            appState.publicationCalendarInfo = found
                                        }
                                        appState.saveDatabase()
                                    }
                                )) {
                                    ForEach(writableCalendars) { cal in
                                        Text("\(cal.title) (\(cal.sourceTitle))").tag(cal.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: 320)
                                
                                Button(action: {
                                    Task {
                                        await appState.setupPlannerCalendar()
                                    }
                                }) {
                                    Label("Ensure Dedicated Calendar", systemImage: "plus.circle")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            if let pubCal = appState.publicationCalendarInfo ?? writableCalendars.first(where: { $0.id == appState.preferences.publicationCalendarIdentifier }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.dbNavy)
                                        .font(.caption)
                                    Text(pubCal.providerSyncDescription)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Divider()
                        
                        // Configured Timezone
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Configured Timezone")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Deadlines and work sessions without an explicit email timezone are interpreted in this timezone.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 8) {
                                Image(systemName: "globe")
                                    .foregroundColor(.dbNavy)
                                Text("**\(appState.preferences.timeZoneIdentifier)** (\(appState.preferences.timeZone.abbreviation(for: Date()) ?? ""))")
                                    .font(.subheadline)
                                Spacer()
                                Text("Configured for Local Scheduling")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                        }
                        
                        Divider()
                        
                        // All-Day Events toggle
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("All-day events block working hours", isOn: Binding(
                                get: { appState.allDayEventsBlockTime },
                                set: { appState.setAllDayEventsBlockTime($0) }
                            ))
                            .font(.subheadline)
                            
                            Text("Default is off: all-day events are displayed in your schedule without blocking your availability. Turn on if all-day events represent full-day commitments that prevent scheduling work.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Status / Error feedback
                if let status = appState.calendarStatusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let error = appState.calendarErrorMessage {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(10)
        }
    }
}
