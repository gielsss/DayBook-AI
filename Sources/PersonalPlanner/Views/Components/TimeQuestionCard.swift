import SwiftUI

/// Today: "How long did it take?" for tasks you finished. Answers teach later estimates for the same
/// course and kind of work; Skip records nothing.
public struct TimeQuestionCard: View {
    @ObservedObject var appState: AppState
    @State private var answers: [UUID: Int] = [:]
    @State private var showAll = false
    private let collapsedCount = 3

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        let questions = appState.openTimeQuestions
        if !questions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    DayBookIconTile(systemImage: "stopwatch", color: .dbAccent, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(questions.count == 1 ? "How long did it take?" : "How long did these take?")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.dbInk)
                        Text("Your answers make the next estimates for the same course and kind of work more accurate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array((showAll ? questions : Array(questions.prefix(collapsedCount))).enumerated()), id: \.element.id) { index, q in
                        if index > 0 { Divider() }
                        row(q)
                    }
                }

                if questions.count > collapsedCount {
                    Button(showAll ? "Show Fewer" : "Show \(questions.count - collapsedCount) More") {
                        withAnimation(.easeInOut(duration: 0.2)) { showAll.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dbAccent)
                }
            }
            .dayBookCard(padding: 16)
        }
    }

    private func row(_ q: TimeQuestion) -> some View {
        let minutes = Binding<Int>(
            get: { answers[q.taskId] ?? Self.rounded(q.suggestedMinutes) },
            set: { answers[q.taskId] = $0 }
        )
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(q.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.dbInk)
                    .lineLimit(1)
                Text("Planned \(AppState.durationText(q.plannedMinutes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Stepper(value: minutes, in: 5...1200, step: minutes.wrappedValue < 60 ? 5 : 15) {
                Text(AppState.durationText(minutes.wrappedValue))
                    .monospacedDigit()
                    .frame(minWidth: 64, alignment: .trailing)
            }
            .fixedSize()
            Button("Save") {
                withAnimation(.easeInOut(duration: 0.2)) { appState.answerTimeQuestion(taskId: q.taskId, minutes: minutes.wrappedValue) }
            }
            Button("Skip") {
                withAnimation(.easeInOut(duration: 0.2)) { appState.skipTimeQuestion(taskId: q.taskId) }
            }
            .help("Don't use this task for future estimates")
        }
        .controlSize(.small)
        .padding(.vertical, 7)
    }

    static func rounded(_ minutes: Int) -> Int {
        minutes < 60 ? max(5, (minutes + 2) / 5 * 5) : (minutes + 7) / 15 * 15
    }
}
