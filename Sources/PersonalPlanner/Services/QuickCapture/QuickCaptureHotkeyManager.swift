import AppKit

@MainActor
public final class QuickCaptureHotkeyManager {
    public static let shared = QuickCaptureHotkeyManager()
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var appState: AppState?
    
    public init() {}
    
    public func register(appState: AppState) {
        self.appState = appState
        unregister()
        
        // Local Monitor: Works whenever PersonalPlanner is frontmost
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.matchesConfiguredShortcut(event: event) == true {
                DispatchQueue.main.async {
                    self?.appState?.openQuickCapture(fromClipboard: true)
                }
                return nil
            }
            return event
        }
        
        // Global Monitor: Attempts to monitor when other applications are active
        // (Note: If Accessibility permission is pending, macOS safely returns nil)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.matchesConfiguredShortcut(event: event) == true {
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    self?.appState?.openQuickCapture(fromClipboard: true)
                }
            }
        }
    }
    
    public func unregister() {
        if let g = globalMonitor {
            NSEvent.removeMonitor(g)
            globalMonitor = nil
        }
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
            localMonitor = nil
        }
    }
    
    private func matchesConfiguredShortcut(event: NSEvent) -> Bool {
        guard let shortcut = appState?.preferences.quickCaptureShortcut else {
            // Default: Command + Shift + C
            return event.modifierFlags.contains([.command, .shift]) &&
                   event.charactersIgnoringModifiers?.lowercased() == "c"
        }
        
        switch shortcut {
        case "Option+Space":
            return event.modifierFlags.contains(.option) && event.keyCode == 49 // Space
        case "Control+Option+C":
            return event.modifierFlags.contains([.control, .option]) &&
                   event.charactersIgnoringModifiers?.lowercased() == "c"
        case "Command+Shift+C":
            fallthrough
        default:
            return event.modifierFlags.contains([.command, .shift]) &&
                   event.charactersIgnoringModifiers?.lowercased() == "c"
        }
    }
}
