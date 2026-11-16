import AppKit
import SwiftUI

public final class QuickCapturePanelController: NSObject, NSWindowDelegate {
    public static let shared = QuickCapturePanelController()
    
    private var panel: NSPanel?
    private var appState: AppState?
    
    public override init() {
        super.init()
    }
    
    public func show(appState: AppState) {
        self.appState = appState
        
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 580),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.title = "Quick Capture"
        newPanel.titleVisibility = .visible
        newPanel.titlebarAppearsTransparent = false
        newPanel.isReleasedWhenClosed = false
        newPanel.minSize = NSSize(width: 480, height: 420)
        newPanel.delegate = self
        
        let hostingView = NSHostingView(
            rootView: QuickCaptureView(appState: appState, onClose: { [weak newPanel] in
                newPanel?.close()
            })
        )
        newPanel.contentView = hostingView
        newPanel.center()
        newPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        self.panel = newPanel
    }
    
    public func close() {
        panel?.close()
    }
    
    public func windowWillClose(_ notification: Notification) {
        // Clean up or save draft state
    }
}
