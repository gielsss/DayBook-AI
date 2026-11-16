import Foundation

/// Daily copies of DayBook AI's data files in `Backups/<yyyy-MM-dd>/`, keeping the newest 14 days.
/// Images (receipts, captures) aren't copied: they never change once added.
public final class BackupService {
    public let backupsDirectory: URL
    /// Files to copy, with the name each gets inside a day's folder.
    public let files: [(source: URL, name: String)]
    public let daysToKeep: Int

    public init(backupsDirectory: URL, files: [(source: URL, name: String)], daysToKeep: Int = 14) {
        self.backupsDirectory = backupsDirectory
        self.files = files
        self.daysToKeep = daysToKeep
    }

    static func folderName(for date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// Day folders, newest first.
    public func backups() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backupsDirectory.path)) ?? []
        return names.filter { $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
            .sorted(by: >)
            .map { backupsDirectory.appendingPathComponent($0, isDirectory: true) }
    }

    public var latestBackupDate: Date? {
        guard let latest = backups().first else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: latest.path))?[.modificationDate] as? Date
    }

    /// Makes today's backup if there isn't one yet. Returns true when a backup was written.
    @discardableResult
    public func backUpIfDue(now: Date = Date(), timeZone: TimeZone = .current) throws -> Bool {
        let today = backupsDirectory.appendingPathComponent(Self.folderName(for: now, timeZone: timeZone), isDirectory: true)
        if FileManager.default.fileExists(atPath: today.path) { return false }
        try backUp(now: now, timeZone: timeZone)
        return true
    }

    /// Writes (or replaces) today's backup and removes the oldest beyond `daysToKeep`.
    public func backUp(now: Date = Date(), timeZone: TimeZone = .current) throws {
        let fm = FileManager.default
        let folder = backupsDirectory.appendingPathComponent(Self.folderName(for: now, timeZone: timeZone), isDirectory: true)
        // Write into a temporary folder first so a half-finished backup never replaces a good one.
        let staging = backupsDirectory.appendingPathComponent(".incoming-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var copied = 0
        for file in files where fm.fileExists(atPath: file.source.path) {
            try fm.copyItem(at: file.source, to: staging.appendingPathComponent(file.name))
            copied += 1
        }
        guard copied > 0 else { return }
        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        try fm.moveItem(at: staging, to: folder)
        for old in backups().dropFirst(daysToKeep) {
            try? fm.removeItem(at: old)
        }
    }
}
