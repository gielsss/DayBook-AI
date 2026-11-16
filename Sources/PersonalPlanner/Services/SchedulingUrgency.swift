import Foundation

/// How urgent it is to start a task, judged from its deadline, the work it still needs, and how busy the
/// rest of your schedule is.
///
/// Slack = free working time between now and the task's deadline (working hours minus classes/events,
/// lunch, kept sessions and the daily cap) − the work every task due by then still needs (this one included).
/// Little slack means it has to start now even if the deadline looks far away (a long assignment in a busy
/// week); lots of slack means it can wait for its turn.
public struct TaskUrgency: Equatable {
    public enum Level: Int, Comparable {
        case overbooked = 0  // can't all fit before the deadline
        case startNow = 1
        case startSoon = 2
        case onTrack = 3

        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public let level: Level
    /// Minutes of free working time to spare before the deadline (negative = short by that much).
    public let slackMinutes: Int
    /// Work this task still needs, in minutes.
    public let remainingMinutes: Int

    /// Short label for lists: "Start now", "Start soon", "On track", "Won't fit".
    public var label: String {
        switch level {
        case .overbooked: return "Won't fit"
        case .startNow: return "Start now"
        case .startSoon: return "Start soon"
        case .onTrack: return "On track"
        }
    }

    /// One-line explanation, e.g. "3 h of free time to spare before it's due".
    public var explanation: String {
        func text(_ m: Int) -> String {
            let h = m / 60, r = m % 60
            if h == 0 { return "\(r) min" }
            return r == 0 ? "\(h) h" : "\(h) h \(r) min"
        }
        if slackMinutes < 0 {
            return "About \(text(-slackMinutes)) short: your free time before the deadline doesn't cover this and the work due before it."
        }
        return "\(text(slackMinutes)) of free time to spare before it's due, after everything due earlier."
    }

    static func classify(slack: Int, remaining: Int, dailyCap: Int) -> Level {
        if slack < 0 { return .overbooked }
        if slack < max(120, remaining / 2) { return .startNow }
        if slack < max(dailyCap, 240) * 2 { return .startSoon }
        return .onTrack
    }
}

/// Free working time, day by day, used to measure slack.
struct FreeTimeMap {
    struct Day {
        let start: Date
        let gaps: [(start: Date, end: Date)]
        let capMinutes: Int
    }
    let days: [Day]
    /// Share of free time that becomes work once breaks between sessions are taken
    /// (45-minute sessions with 15-minute breaks → 0.75).
    var workShare: Double = 1

    /// Free minutes between `from` and `to`, respecting each day's cap. `usedToday` minutes are already
    /// taken from the day containing `from` (sessions just placed).
    func minutes(from: Date, to: Date, usedOnFromDay: Int = 0, calendar: Calendar) -> Int {
        guard to > from else { return 0 }
        var total = 0
        for day in days {
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day.start), dayEnd > from, day.start < to else { continue }
            var free = 0
            for gap in day.gaps {
                let s = max(gap.start, from), e = min(gap.end, to)
                if e > s { free += Int(e.timeIntervalSince(s) / 60) }
            }
            var cap = day.capMinutes
            if calendar.isDate(day.start, inSameDayAs: from) { cap -= usedOnFromDay }
            total += max(0, min(Int(Double(free) * workShare), cap))
        }
        return total
    }
}

extension RuleBasedSchedulingEngine {
    /// Slack of one task at time `at`: free time until its cutoff minus the work of every queued task due
    /// by then (including itself). Your priority shifts it: High counts as 3 h less slack, Low as 3 h more.
    static func slack(of item: TaskSchedulingItem, in queue: [TaskSchedulingItem], at: Date, usedOnDay: Int,
                      freeTime: FreeTimeMap, calendar: Calendar) -> Int {
        let capacity = freeTime.minutes(from: at, to: item.hardCutoff, usedOnFromDay: usedOnDay, calendar: calendar)
        let demand = queue.filter { $0.hardCutoff <= item.hardCutoff }.reduce(0) { $0 + $1.remainingMinutes }
            + (queue.contains { $0.task.id == item.task.id } ? 0 : item.remainingMinutes)
        var slack = capacity - demand
        switch item.task.userPriority {
        case .high: slack -= 180
        case .low: slack += 180
        default: break
        }
        return slack
    }
}
