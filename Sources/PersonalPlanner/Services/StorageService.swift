import Foundation

public final class StorageService: StorageServiceProtocol {
    public let databaseURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    public init(customURL: URL? = nil) {
        if let customURL = customURL {
            self.databaseURL = customURL
        } else if let envPath = ProcessInfo.processInfo.environment["PERSONAL_PLANNER_DB_PATH"], !envPath.isEmpty {
            self.databaseURL = URL(fileURLWithPath: envPath)
        } else {
            // Check if Application Support is accessible
            let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("PersonalPlanner", isDirectory: true)
            
            var chosenURL: URL? = nil
            if let dir = appSupportDir {
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let testFile = dir.appendingPathComponent(".write_test")
                    try "test".write(to: testFile, atomically: true, encoding: .utf8)
                    try? FileManager.default.removeItem(at: testFile)
                    chosenURL = dir.appendingPathComponent("planner_database.json")
                } catch {
                    // Fall back to local working directory
                    chosenURL = nil
                }
            }
            
            if let chosen = chosenURL {
                self.databaseURL = chosen
            } else {
                let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                self.databaseURL = currentDir.appendingPathComponent("planner_database.json")
            }
        }
        
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }
    
    public func loadDatabase() -> PlannerDatabase {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            // First run: generate initial seed with demonstration data
            let initialDB = DemoDataFactory.makeDemonstrationDatabase()
            try? saveDatabase(initialDB)
            return initialDB
        }
        
        do {
            let data = try Data(contentsOf: databaseURL)
            let database = try decoder.decode(PlannerDatabase.self, from: data)
            return database
        } catch {
            // Never destroy an existing database we failed to read (e.g. a schema decoding error after an
            // update). Keep a byte-for-byte copy beside it before falling back, so the user's real data
            // can always be recovered.
            let preserved = UnreadableFilePreserver.preserve(databaseURL)
            print("⚠️ Failed to load database from \(databaseURL.path): \(error). Preserved original at \(preserved?.lastPathComponent ?? "<copy failed>"). Falling back to demo data.")
            let fallbackDB = DemoDataFactory.makeDemonstrationDatabase()
            if preserved != nil {
                try? saveDatabase(fallbackDB)
            }
            return fallbackDB
        }
    }
    
    public func saveDatabase(_ db: PlannerDatabase) throws {
        let parentDir = databaseURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        let data = try encoder.encode(db)
        try data.write(to: databaseURL, options: .atomic)
    }
    
    public func resetDatabase() -> PlannerDatabase {
        let freshDB = DemoDataFactory.makeDemonstrationDatabase()
        try? saveDatabase(freshDB)
        return freshDB
    }
}

/// Copies a data file that could not be decoded to a timestamped sibling
/// (`name.unreadable-YYYYMMDD-HHmmss.ext`) so a later save can never silently destroy it.
public enum UnreadableFilePreserver {
    @discardableResult
    public static func preserve(_ url: URL, now: Date = Date()) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMdd-HHmmss"
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
        let dir = url.deletingLastPathComponent()
        // Repeated loads of the same broken file reuse one preserved copy instead of piling up duplicates.
        if let siblings = try? fm.contentsOfDirectory(atPath: dir.path) {
            for name in siblings where name.hasPrefix("\(base).unreadable-") {
                let existing = dir.appendingPathComponent(name)
                if fm.contentsEqual(atPath: existing.path, andPath: url.path) {
                    return existing
                }
            }
        }
        var candidate = dir.appendingPathComponent("\(base).unreadable-\(df.string(from: now))\(ext)")
        var counter = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base).unreadable-\(df.string(from: now))-\(counter)\(ext)")
            counter += 1
        }
        do {
            try fm.copyItem(at: url, to: candidate)
            return candidate
        } catch {
            return nil
        }
    }
}
