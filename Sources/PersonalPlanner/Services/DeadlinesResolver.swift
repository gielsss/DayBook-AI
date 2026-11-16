import Foundation

public struct ResolvedDeadlineResult: Equatable {
    public let deadlineDate: Date?
    public let originalWording: String?
    public let dateOnlyString: String? // "YYYY-MM-DD" if date-only
    public let isDateOnly: Bool
    public let timeZoneAssumption: String
    public let provenance: DeadlineProvenance
    public let isSupported: Bool
    
    public init(
        deadlineDate: Date?,
        originalWording: String?,
        dateOnlyString: String? = nil,
        isDateOnly: Bool = false,
        timeZoneAssumption: String,
        provenance: DeadlineProvenance,
        isSupported: Bool
    ) {
        self.deadlineDate = deadlineDate
        self.originalWording = originalWording
        self.dateOnlyString = dateOnlyString
        self.isDateOnly = isDateOnly
        self.timeZoneAssumption = timeZoneAssumption
        self.provenance = provenance
        self.isSupported = isSupported
    }
}

public enum DeadlinesResolver {
    private static let timezoneMap: [String: String] = [
        "EST": "America/New_York",
        "EDT": "America/New_York",
        "ET": "America/New_York",
        "CST": "America/Chicago",
        "CDT": "America/Chicago",
        "CT": "America/Chicago",
        "MST": "America/Denver",
        "MDT": "America/Denver",
        "MT": "America/Denver",
        "PST": "America/Los_Angeles",
        "PDT": "America/Los_Angeles",
        "PT": "America/Los_Angeles",
        "UTC": "UTC",
        "GMT": "GMT",
        "JST": "Asia/Tokyo"
    ]
    
    public static func resolve(
        rawDeadlineIso: String?,
        supportingExcerpt: String,
        emailReceivedDate: Date,
        configuredTimeZone: TimeZone,
        dateOnlyPolicy: DateOnlyDeadlinePolicy = .endOfWorkday,
        workdayEndHour: Int = 17,
        workdayEndMinute: Int = 0,
        workdayStartHour: Int = 9,
        workdayStartMinute: Int = 0
    ) -> ResolvedDeadlineResult {
        let excerpt = supportingExcerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerExcerpt = excerpt.lowercased()
        
        // 1. Check for unsupported / no deadline
        let noDeadlineKeywords = ["whenever", "no explicit deadline", "sometime soon", "breathing room", "no rush", "if interested"]
        let containsNoDeadlineKeyword = noDeadlineKeywords.contains { lowerExcerpt.contains($0) }
        let hasNoRawDeadline = (rawDeadlineIso == nil || rawDeadlineIso?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)
        
        let hasDeadlineSignifiers = lowerExcerpt.contains("within") || lowerExcerpt.contains("by ") || lowerExcerpt.contains("deadline") || lowerExcerpt.contains("closing") || lowerExcerpt.contains("due")
        
        if (containsNoDeadlineKeyword && hasNoRawDeadline) || (hasNoRawDeadline && !hasDeadlineSignifiers) {
            return ResolvedDeadlineResult(
                deadlineDate: nil,
                originalWording: "None stated in email",
                dateOnlyString: nil,
                isDateOnly: false,
                timeZoneAssumption: "None (Email contains no deadline)",
                provenance: .unsupported,
                isSupported: false
            )
        }
        
        // 2. Check for Relative Elapsed Window ("within 24 hours")
        if let hours = extractRelativeHours(from: lowerExcerpt) {
            let wording = extractRelativeWording(from: excerpt) ?? "within \(hours) hours"
            let elapsedDeadline = emailReceivedDate.addingTimeInterval(Double(hours * 3600))
            return ResolvedDeadlineResult(
                deadlineDate: elapsedDeadline,
                originalWording: wording,
                dateOnlyString: nil,
                isDateOnly: false,
                timeZoneAssumption: "Elapsed \(hours) hours from email receipt timestamp",
                provenance: .relativeWindow,
                isSupported: true
            )
        }
        
        // 3. Check for Explicit Timezone in Excerpt
        var explicitTz: TimeZone? = nil
        var explicitTzName: String? = nil
        for (code, tzId) in timezoneMap {
            let pattern = "\\b\(code)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: excerpt, range: NSRange(location: 0, length: excerpt.utf16.count)) != nil {
                if let tz = TimeZone(identifier: tzId) {
                    explicitTz = tz
                    explicitTzName = code
                    break
                }
            }
        }
        
        let targetTz = explicitTz ?? configuredTimeZone
        let tzAssumption = (explicitTz != nil)
            ? "Explicit in email: \(explicitTzName!)"
            : "\(configuredTimeZone.identifier) (Assumed from user preferences; no timezone in email)"
        
        // 4. Check for Date-Only Deadlines vs Timed Deadlines
        let hasExplicitTimeWords = lowerExcerpt.contains(" at ") || lowerExcerpt.contains("pm") || lowerExcerpt.contains("am") || lowerExcerpt.contains("o'clock") || lowerExcerpt.contains("noon") || lowerExcerpt.contains("midnight") || hasColonTime(lowerExcerpt)
        
        if !hasExplicitTimeWords && isDateOnlyText(lowerExcerpt, rawIso: rawDeadlineIso) {
            let dateOnlyStr = extractCalendarDateString(rawIso: rawDeadlineIso, excerpt: lowerExcerpt, receivedDate: emailReceivedDate, timeZone: targetTz)
            let wording = extractDateOnlyWording(from: excerpt) ?? "Date-only deadline from email"
            
            let cutoffDate = calculateDateOnlyCutoff(
                dateStr: dateOnlyStr,
                timeZone: targetTz,
                policy: dateOnlyPolicy,
                endHour: workdayEndHour,
                endMinute: workdayEndMinute,
                startHour: workdayStartHour,
                startMinute: workdayStartMinute
            )
            
            let assumption = "\(targetTz.identifier) (Evaluated with \(dateOnlyPolicy.shortTitle) policy)"
            
            return ResolvedDeadlineResult(
                deadlineDate: cutoffDate,
                originalWording: wording,
                dateOnlyString: dateOnlyStr,
                isDateOnly: true,
                timeZoneAssumption: assumption,
                provenance: .dateOnly,
                isSupported: true
            )
        }
        
        // 5. Timed Deadline: Parse in target timezone
        if let parsedTimed = parseTimedDeadline(excerpt: excerpt, lowerExcerpt: lowerExcerpt, rawIso: rawDeadlineIso, receivedDate: emailReceivedDate, targetTz: targetTz) {
            return ResolvedDeadlineResult(
                deadlineDate: parsedTimed.date,
                originalWording: parsedTimed.wording,
                dateOnlyString: nil,
                isDateOnly: false,
                timeZoneAssumption: tzAssumption,
                provenance: .explicitDateTime,
                isSupported: true
            )
        }
        
        // 6. Fallback to ISO string if provided
        if let raw = rawDeadlineIso, let isoDate = parseISO8601(raw) {
            let wording = extractTimedWording(from: excerpt) ?? raw
            return ResolvedDeadlineResult(
                deadlineDate: isoDate,
                originalWording: wording,
                dateOnlyString: nil,
                isDateOnly: false,
                timeZoneAssumption: tzAssumption,
                provenance: .explicitDateTime,
                isSupported: true
            )
        }
        
        return ResolvedDeadlineResult(
            deadlineDate: nil,
            originalWording: "None stated in email",
            dateOnlyString: nil,
            isDateOnly: false,
            timeZoneAssumption: "None (Email contains no deadline)",
            provenance: .unsupported,
            isSupported: false
        )
    }
    
    // MARK: - Helper Methods
    
    private static func hasColonTime(_ text: String) -> Bool {
        let pattern = "\\b\\d{1,2}:\\d{2}\\b"
        if let regex = try? NSRegularExpression(pattern: pattern),
           regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) != nil {
            return true
        }
        return false
    }
    
    private static func isDateOnlyText(_ lower: String, rawIso: String?) -> Bool {
        if lower.contains("closing on") || lower.contains("due on") || lower.contains("deadline:") || lower.contains("by monday") || lower.contains("by friday") {
            return true
        }
        if let raw = rawIso {
            if raw.count == 10 && raw.contains("-") { return true }
            if raw.contains("T00:00:00") || raw.contains("T23:59:00") { return true }
        }
        return false
    }
    
    private static func extractRelativeHours(from text: String) -> Int? {
        // e.g. "within 24 hours", "within 48 hrs", "within 1 day"
        let pattern = "within\\s+(\\d+)\\s*(hour|hr|day)s?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) else {
            return nil
        }
        
        guard let numRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let num = Int(text[numRange]) else {
            return nil
        }
        
        let unit = text[unitRange].lowercased()
        if unit.hasPrefix("day") {
            return num * 24
        }
        return num
    }
    
    private static func extractRelativeWording(from text: String) -> String? {
        let pattern = "within\\s+\\d+\\s*(hour|hr|day)s?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return String(text[range])
    }
    
    private static func extractDateOnlyWording(from text: String) -> String? {
        let patterns = [
            "closing on [A-Za-z]+[\\s]+[A-Za-z]+[\\s]+\\d+(?:st|nd|rd|th)?",
            "due on [A-Za-z]+[\\s]+[A-Za-z]+[\\s]+\\d+(?:st|nd|rd|th)?",
            "by [A-Za-z]+[\\s]+[A-Za-z]+[\\s]+\\d+(?:st|nd|rd|th)?",
            "[A-Za-z]+[\\s]+[A-Za-z]+[\\s]+\\d+(?:st|nd|rd|th)?"
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)),
               let range = Range(match.range, in: text) {
                return String(text[range])
            }
        }
        return nil
    }
    
    private static func extractTimedWording(from text: String) -> String? {
        let patterns = [
            "\\b(?:by|at)?\\s*([A-Za-z]+\\s+at\\s+\\d{1,2}(?::\\d{2})?\\s*(?:am|pm)?(?:\\s+[A-Za-z]{2,4})?)",
            "\\b([A-Za-z]+\\s+by\\s+\\d{1,2}(?::\\d{2})?\\s*(?:am|pm)?(?:\\s+[A-Za-z]{2,4})?)",
            "\\b(\\d{1,2}(?::\\d{2})?\\s*(?:am|pm)\\s+[A-Za-z]{2,4})\\b",
            "\\b(\\d{1,2}(?::\\d{2})?\\s*(?:am|pm))\\b"
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) {
                let targetRange = (match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound)
                    ? match.range(at: 1)
                    : match.range
                if let range = Range(targetRange, in: text) {
                    return String(text[range]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
    
    public static func extractCalendarDateString(rawIso: String?, excerpt: String, receivedDate: Date, timeZone: TimeZone) -> String {
        // If rawIso contains YYYY-MM-DD
        if let raw = rawIso, raw.count >= 10 {
            if raw.contains("T"), let parsed = parseISO8601(raw) {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = timeZone
                let y = cal.component(.year, from: parsed)
                let m = cal.component(.month, from: parsed)
                let d = cal.component(.day, from: parsed)
                return String(format: "%04d-%02d-%02d", y, m, d)
            }
            let prefix = String(raw.prefix(10))
            let parts = prefix.split(separator: "-")
            if parts.count == 3, let _ = Int(parts[0]), let _ = Int(parts[1]), let _ = Int(parts[2]) {
                return prefix
            }
        }
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        
        let monthMap = [
            "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
            "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
        ]
        
        for (mPrefix, mNum) in monthMap {
            let pattern = "\(mPrefix)[a-z]*\\s+(\\d{1,2})"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: excerpt, range: NSRange(location: 0, length: excerpt.utf16.count)),
               let dayRange = Range(match.range(at: 1), in: excerpt),
               let dayNum = Int(excerpt[dayRange]) {
                let year = cal.component(.year, from: receivedDate)
                return String(format: "%04d-%02d-%02d", year, mNum, dayNum)
            }
        }
        
        // Fallback to received date in timeZone
        let year = cal.component(.year, from: receivedDate)
        let month = cal.component(.month, from: receivedDate)
        let day = cal.component(.day, from: receivedDate)
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
    
    public static func calculateDateOnlyCutoff(
        dateStr: String,
        timeZone: TimeZone,
        policy: DateOnlyDeadlinePolicy,
        endHour: Int = 17,
        endMinute: Int = 0,
        startHour: Int = 9,
        startMinute: Int = 0
    ) -> Date {
        let parts = dateStr.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return Date()
        }
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        
        var comp = DateComponents()
        comp.year = parts[0]
        comp.month = parts[1]
        comp.day = parts[2]
        comp.timeZone = timeZone
        
        switch policy {
        case .endOfWorkday:
            comp.hour = endHour
            comp.minute = endMinute
            comp.second = 0
        case .endOfDay:
            comp.hour = 23
            comp.minute = 59
            comp.second = 59
        case .startOfWorkday:
            comp.hour = startHour
            comp.minute = startMinute
            comp.second = 0
        }
        
        return cal.date(from: comp) ?? Date()
    }
    
    private static func parseTimedDeadline(
        excerpt: String,
        lowerExcerpt: String,
        rawIso: String?,
        receivedDate: Date,
        targetTz: TimeZone
    ) -> (date: Date, wording: String)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = targetTz
        
        // Parse time of day (e.g. "6pm", "11:59 pm", "18:00", "5:00 PM")
        guard let time = parseHourMinute(from: lowerExcerpt) else {
            return nil
        }
        
        // Parse weekday (e.g. "Wednesday", "Friday")
        let weekdayNames = [
            ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
            ("thursday", 5), ("friday", 6), ("saturday", 7)
        ]
        
        var targetWeekday: Int? = nil
        for (name, num) in weekdayNames {
            if lowerExcerpt.contains(name) {
                targetWeekday = num
                break
            }
        }
        
        let wording = extractTimedWording(from: excerpt) ?? "Timed deadline from email"
        
        var comp = DateComponents()
        comp.timeZone = targetTz
        comp.hour = time.hour
        comp.minute = time.minute
        comp.second = 0
        
        if lowerExcerpt.contains("tomorrow") {
            guard let resolvedDay = cal.date(byAdding: .day, value: 1, to: receivedDate) else {
                return nil
            }
            comp.year = cal.component(.year, from: resolvedDay)
            comp.month = cal.component(.month, from: resolvedDay)
            comp.day = cal.component(.day, from: resolvedDay)
        } else if lowerExcerpt.contains("today") || lowerExcerpt.contains("tonight") {
            comp.year = cal.component(.year, from: receivedDate)
            comp.month = cal.component(.month, from: receivedDate)
            comp.day = cal.component(.day, from: receivedDate)
        } else if let targetWd = targetWeekday {
            // Find target weekday relative to received date in targetTz
            let recvWeekday = cal.component(.weekday, from: receivedDate)
            var daysToAdd = (targetWd - recvWeekday)
            if daysToAdd < 0 {
                daysToAdd += 7
            }
            
            // If same weekday, check if time has already passed on that day
            if daysToAdd == 0 {
                let recvHour = cal.component(.hour, from: receivedDate)
                let recvMin = cal.component(.minute, from: receivedDate)
                if recvHour > time.hour || (recvHour == time.hour && recvMin >= time.minute) {
                    daysToAdd = 7
                }
            }
            
            guard let resolvedDay = cal.date(byAdding: .day, value: daysToAdd, to: receivedDate) else {
                return nil
            }
            
            comp.year = cal.component(.year, from: resolvedDay)
            comp.month = cal.component(.month, from: resolvedDay)
            comp.day = cal.component(.day, from: resolvedDay)
        } else {
            // No weekday name: use month & day from text or received date
            let dateStr = extractCalendarDateString(rawIso: rawIso, excerpt: lowerExcerpt, receivedDate: receivedDate, timeZone: targetTz)
            let parts = dateStr.split(separator: "-").compactMap { Int($0) }
            if parts.count == 3 {
                comp.year = parts[0]
                comp.month = parts[1]
                comp.day = parts[2]
            } else {
                comp.year = cal.component(.year, from: receivedDate)
                comp.month = cal.component(.month, from: receivedDate)
                comp.day = cal.component(.day, from: receivedDate)
            }
        }
        
        guard let finalDate = cal.date(from: comp) else {
            return nil
        }
        
        return (date: finalDate, wording: wording)
    }
    
    private static func parseHourMinute(from lower: String) -> (hour: Int, minute: Int)? {
        // 1. "11:59 pm" or "5:00 pm" or "10:15 am"
        let pattern1 = "\\b(\\d{1,2}):(\\d{2})\\s*(am|pm)\\b"
        if let regex = try? NSRegularExpression(pattern: pattern1),
           let match = regex.firstMatch(in: lower, range: NSRange(location: 0, length: lower.utf16.count)),
           let hRange = Range(match.range(at: 1), in: lower),
           let mRange = Range(match.range(at: 2), in: lower),
           let ampmRange = Range(match.range(at: 3), in: lower),
           let h = Int(lower[hRange]),
           let m = Int(lower[mRange]) {
            let ampm = lower[ampmRange]
            var hour = h
            if ampm == "pm" && hour < 12 { hour += 12 }
            if ampm == "am" && hour == 12 { hour = 0 }
            return (hour, m)
        }
        
        // 2. "6pm" or "5 pm" or "9am"
        let pattern2 = "\\b(\\d{1,2})\\s*(am|pm)\\b"
        if let regex = try? NSRegularExpression(pattern: pattern2),
           let match = regex.firstMatch(in: lower, range: NSRange(location: 0, length: lower.utf16.count)),
           let hRange = Range(match.range(at: 1), in: lower),
           let ampmRange = Range(match.range(at: 2), in: lower),
           let h = Int(lower[hRange]) {
            let ampm = lower[ampmRange]
            var hour = h
            if ampm == "pm" && hour < 12 { hour += 12 }
            if ampm == "am" && hour == 12 { hour = 0 }
            return (hour, 0)
        }
        
        // 3. 24-hour "18:00"
        let pattern3 = "\\b(\\d{1,2}):(\\d{2})\\b"
        if let regex = try? NSRegularExpression(pattern: pattern3),
           let match = regex.firstMatch(in: lower, range: NSRange(location: 0, length: lower.utf16.count)),
           let hRange = Range(match.range(at: 1), in: lower),
           let mRange = Range(match.range(at: 2), in: lower),
           let h = Int(lower[hRange]),
           let m = Int(lower[mRange]),
           h >= 0 && h <= 23 && m >= 0 && m <= 59 {
            return (h, m)
        }
        
        return nil
    }
    
    private static func parseISO8601(_ str: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: str) { return d }
        let standard = ISO8601DateFormatter()
        return standard.date(from: str)
    }
}
