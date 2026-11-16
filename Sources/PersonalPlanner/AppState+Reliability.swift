import Foundation
import AppKit

/// Daily backups.
extension AppState {
    // MARK: - Daily backups

    /// planner_database.json (and any add-on databases), copied once a day into
    /// Backups/<date>/ next to the planner database; the newest 14 days are kept.
    public var backupService: BackupService {
        let base = storageService.databaseURL.deletingLastPathComponent()
        var files: [(source: URL, name: String)] = [(storageService.databaseURL, "planner_database.json")]
        return BackupService(backupsDirectory: base.appendingPathComponent("Backups", isDirectory: true), files: files)
    }

    /// Makes today's backup if it hasn't been made yet (at launch and every few minutes after).
    public func runDailyBackupIfDue(now: Date = Date()) {
        do {
            if try backupService.backUpIfDue(now: now, timeZone: preferences.timeZone) {
                lastBackupDate = now
            }
            backupErrorMessage = nil
        } catch {
            backupErrorMessage = "Couldn't make today's backup: \(error.localizedDescription)"
        }
    }

    /// "Back Up Now": saves first so the copy is current, then replaces today's backup.
    public func backUpNow() {
        saveDatabase()
        do {
            try backupService.backUp(timeZone: preferences.timeZone)
            lastBackupDate = Date()
            backupErrorMessage = nil
        } catch {
            backupErrorMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    public func revealBackupsInFinder() {
        let dir = backupService.backupsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}
