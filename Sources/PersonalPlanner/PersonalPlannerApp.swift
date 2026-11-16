import SwiftUI

@main
struct PersonalPlannerApp: App {
    /// One app state for the whole app, created at launch, so automatic sync, backups and notifications
    /// keep running even when no window is open (and every window shows the same data).
    @MainActor static let sharedState = AppState()

    init() {
        if CommandLine.arguments.contains("--render-ui") {
            let success = MainActor.assumeIsolated { UISnapshot.run() }
            exit(success ? 0 : 1)
        }
        if CommandLine.arguments.contains("--test-persistence") {
            let success = PersistenceTester.runAllTests()
            exit(success ? 0 : 1)
        }
        if CommandLine.arguments.contains("--test-quick-capture") {
            let success = MainActor.assumeIsolated {
                QuickCaptureTester.runAllTests()
            }
            exit(success ? 0 : 1)
        }
        if CommandLine.arguments.contains("--test-email-discovery") {
            let success = MainActor.assumeIsolated {
                EmailDiscoveryTester.runAllTests()
            }
            exit(success ? 0 : 1)
        }
        if CommandLine.arguments.contains("--test-canvas") {
            let success = MainActor.assumeIsolated {
                CanvasTester.runAllTests()
            }
            exit(success ? 0 : 1)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--eval-estimates") {
            let args = CommandLine.arguments
            let model = args.indices.contains(i + 1) && !args[i + 1].hasPrefix("-") ? args[i + 1] : nil
            var success = false
            var done = false
            Task { @MainActor in
                success = await EstimateEvaluator.run(model: model)
                done = true
            }
            while !done { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05)) }
            exit(success ? 0 : 1)
        }
        if CommandLine.arguments.contains("--test-ollama") {
            let success = MainActor.assumeIsolated {
                OllamaTester.runAllTests()
            }
            exit(success ? 0 : 1)
        }
        if CommandLine.arguments.contains("--test-milestone-improvements") {
            let success = MainActor.assumeIsolated {
                MilestoneImprovementsTest.runAllTests()
            }
            exit(success ? 0 : 1)
        }
        if CommandLine.arguments.contains("--demo-carryover") {
            MainActor.assumeIsolated {
                MilestoneImprovementsTest.runDemonstration()
            }
            exit(0)
        }
        
        // Start the app state now rather than when the first window opens.
        _ = MainActor.assumeIsolated { Self.sharedState }
        
        // Ensure application icon is set for runtime Dock and App Switcher
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainView(appState: Self.sharedState)
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(DayBookBrand.name)") { DayBookBrand.showAboutPanel() }
            }
        }
    }
}
