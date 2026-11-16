import Foundation
import AppKit

/// New tasks found by a sync: shown in an on-screen panel when the sync finishes, and kept in a
/// highlighted "New" group at the top of Tasks until you look at them ("Got It"), after which they
/// join the regular task list. Only tasks that didn't exist before the sync count (merged updates
/// to known tasks use the "Updated" tag instead); Quick Captures you add yourself never count.
extension AppState {
    /// Call at the start of a sync. Returns the task ids that existed before, or nil when this sync
    /// runs inside another one (only the outermost sync reports).
    func beginNewTaskTracking() -> Set<UUID>? {
        newTaskTrackingDepth += 1
        return newTaskTrackingDepth == 1 ? Set(tasks.map(\.id)) : nil
    }

    /// Call when the sync finishes: records the open tasks it created and shows the panel.
    func endNewTaskTracking(_ before: Set<UUID>?, automatic: Bool = false) {
        newTaskTrackingDepth = max(0, newTaskTrackingDepth - 1)
        guard let before else { return }
        let found = tasks.filter { task in
            !before.contains(task.id) && !task.isCompleted && !task.isDismissed
                && task.sourceEmail.category != .quickCapture
        }
        pruneNewlyFoundTasks()
        guard !found.isEmpty else { return }
        let known = Set(newlyFoundTaskIds)
        newlyFoundTaskIds.append(contentsOf: found.map(\.id).filter { !known.contains($0) })
        showNewTasksPanel = true
        saveDatabase()

        // When DayBook AI isn't in front (an automatic sync), also post a system notification.
        let titles = found.map(\.displayTitle)
        let title = found.count == 1 ? "1 new task found" : "\(found.count) new tasks found"
        let body = titles.prefix(3).joined(separator: ", ") + (titles.count > 3 ? " and \(titles.count - 3) more" : "")
        if let sender = newTasksNotificationSender {
            sender(title, body)
        } else if automatic || !NSApplication.shared.isActive {
            Self.postNotification(title: title, body: body)
        }
    }

    /// New tasks still waiting to be looked at, in the order they were found.
    public var newlyFoundTasks: [DiscoveredTask] {
        let byId = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return newlyFoundTaskIds.compactMap { byId[$0] }.filter { !$0.isCompleted && !$0.isDismissed }
    }

    public func isNewlyFound(_ taskId: UUID) -> Bool {
        newlyFoundTaskIds.contains(taskId)
    }

    /// "Got It" on one task: it moves to the regular list.
    public func acknowledgeNewTask(_ taskId: UUID) {
        newlyFoundTaskIds.removeAll { $0 == taskId }
        if newlyFoundTaskIds.isEmpty { showNewTasksPanel = false }
        saveDatabase()
    }

    /// "Got It" on the panel: every new task moves to the regular list.
    public func acknowledgeAllNewTasks() {
        newlyFoundTaskIds.removeAll()
        showNewTasksPanel = false
        saveDatabase()
    }

    /// Drops ids of tasks that are gone, done or dismissed.
    func pruneNewlyFoundTasks() {
        let open = Set(tasks.filter { !$0.isCompleted && !$0.isDismissed }.map(\.id))
        newlyFoundTaskIds.removeAll { !open.contains($0) }
    }
}
