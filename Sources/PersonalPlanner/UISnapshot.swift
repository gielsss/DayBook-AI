import SwiftUI
import AppKit

/// `--render-ui <folder>`: draws each tab with demo data into PNGs (light and dark) so design
/// changes can be reviewed without screen-recording permission. Uses a throwaway data folder.
@MainActor
enum UISnapshot {
    static func run() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-ui"), i + 1 < args.count else {
            print("Usage: --render-ui <output folder>")
            return false
        }
        let out = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("DayBook_UI_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        // Renders use the shared appearance setting; put the user's choice back afterwards.
        let defaults = UserDefaults.standard
        let savedLook = defaults.string(forKey: DayBookAppearance.storageKey)
        defer {
            if let savedLook { defaults.set(savedLook, forKey: DayBookAppearance.storageKey) }
            else { defaults.removeObject(forKey: DayBookAppearance.storageKey) }
        }

        let looks: [(String, NSAppearance.Name, DayBookAppearance)] = [
            ("light", .aqua, .light), ("dark", .darkAqua, .dark), ("colorful", .aqua, .colorful)
        ]
        for appearance in looks {
            defaults.set(appearance.2.rawValue, forKey: DayBookAppearance.storageKey)
            DayBookAppearance.current = appearance.2
            for tab in AppTab.allCases {
                let state = AppState(
                    storageService: StorageService(customURL: temp.appendingPathComponent("planner_database.json")),
                    addOns: .inFolder(temp),
                    quickCaptureStorageService: QuickCaptureStorageService(customBaseURL: temp)
                )
                state.selectedTab = tab
                // Show the "new tasks found" panel (Today) and the New section (Tasks) for review.
                state.newlyFoundTaskIds = Array(state.tasks.filter { !$0.isCompleted && !$0.isDismissed }.prefix(2).map(\.id))
                state.showNewTasksPanel = tab == .today
                if tab == .tasks, let i = state.tasks.firstIndex(where: { !$0.isCompleted }) {
                    // An AI estimate made from a title alone.
                    state.tasks[i].estimateNote = "AI estimate: 4 h — from the title only"
                    state.tasks[i].estimateConfidence = "low"
                }
                if tab == .today || tab == .week {
                    // A missed session (Catch Up) and two tasks with nothing planned (Unplanned), for review.
                    func source(_ id: String) -> EmailSource {
                        EmailSource(id: id, threadId: id, senderName: "Prof. Vance", senderEmail: "vance@university.edu", subject: id,
                                    receivedDate: Date(), snippet: "", fullBody: "", category: .assignment, isSimulatedDemo: false)
                    }
                    let reading = DiscoveredTask(title: "Read Chapter 7", sourceEmail: source("ui-reading"),
                                                 extractedDeadline: Date().addingTimeInterval(5 * 86400), isDeadlineSupportedByEmail: true,
                                                 estimatedMinutes: 60, status: .ready, isClarified: true)
                    let lab = DiscoveredTask(title: "Lab Report Draft", sourceEmail: source("ui-lab"),
                                             extractedDeadline: Date().addingTimeInterval(-2 * 86400), isDeadlineSupportedByEmail: true,
                                             estimatedMinutes: 90, status: .ready, isClarified: true)
                    let survey = DiscoveredTask(title: "Fill out the course survey", sourceEmail: source("ui-survey"),
                                                estimatedMinutes: 15, status: .ready, isClarified: true)
                    state.tasks += [reading, lab, survey]
                    // A finished task waiting for "How long did it take?".
                    var essay = DiscoveredTask(title: "Policy Memo", sourceEmail: source("ui-memo"), estimatedMinutes: 120, status: .completed, isClarified: true)
                    essay.updatedAt = Date()
                    state.tasks.append(essay)
                    state.timeQuestions = [TimeQuestion(taskId: essay.id, title: essay.title, plannedMinutes: 120, suggestedMinutes: 150, askedAt: Date())]
                    let yesterday = Date().addingTimeInterval(-86400)
                    state.workSessions.append(WorkSession(taskId: reading.id, title: "Work Session: Read Chapter 7",
                                                          startTime: yesterday, endTime: yesterday.addingTimeInterval(3600)))
                }
                let size = NSSize(width: 1280, height: 860)
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                      styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance.1)
                let host = NSHostingView(rootView: MainView(appState: state).frame(width: size.width, height: size.height))
                window.contentView = host
                window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
                window.orderFrontRegardless()
                RunLoop.main.run(until: Date().addingTimeInterval(1.2))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                let file = out.appendingPathComponent("\(tab.rawValue.lowercased())-\(appearance.0).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: file)
                window.orderOut(nil)
                print("Rendered \(file.lastPathComponent)")
            }
        }
        return true
    }
}
