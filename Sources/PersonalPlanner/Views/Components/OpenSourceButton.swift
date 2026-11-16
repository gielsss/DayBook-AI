import SwiftUI
import AppKit

extension AppState {
    /// Where this task was found (Gmail message, Canvas or Gradescope page), or nil.
    public func sourceLink(for task: DiscoveredTask) -> TaskSourceLink? {
        TaskSourceLink.forTask(task, canvasBase: canvasBaseURL)
    }

    /// Opens the task's source in the default browser.
    public func openSource(of task: DiscoveredTask) {
        guard let link = sourceLink(for: task) else { return }
        NSWorkspace.shared.open(link.url)
    }
}

/// "Open in Gmail / Canvas / Gradescope" for a task. Hidden when the task has no outside source.
public struct OpenSourceButton: View {
    @ObservedObject var appState: AppState
    let task: DiscoveredTask
    var compact: Bool = false

    public init(appState: AppState, task: DiscoveredTask, compact: Bool = false) {
        self.appState = appState
        self.task = task
        self.compact = compact
    }

    public var body: some View {
        if let link = appState.sourceLink(for: task) {
            if compact {
                Button {
                    NSWorkspace.shared.open(link.url)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("\(link.title): \(link.detail)")
                .accessibilityLabel(link.title)
            } else {
                Button {
                    NSWorkspace.shared.open(link.url)
                } label: {
                    Label(link.title, systemImage: link.systemImage)
                }
                .buttonStyle(.bordered)
                .help(link.detail)
            }
        }
    }
}

/// Context-menu item with the same action, for rows.
public struct OpenSourceMenuItem: View {
    @ObservedObject var appState: AppState
    let task: DiscoveredTask

    public init(appState: AppState, task: DiscoveredTask) {
        self.appState = appState
        self.task = task
    }

    public var body: some View {
        if let link = appState.sourceLink(for: task) {
            Button {
                NSWorkspace.shared.open(link.url)
            } label: {
                Label(link.title, systemImage: link.systemImage)
            }
        }
    }
}
