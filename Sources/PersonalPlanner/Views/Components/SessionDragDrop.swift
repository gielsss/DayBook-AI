import SwiftUI

/// Drag a planned session on Today or Week and drop it on another item (it goes right after that item)
/// or on a day (it goes into that day's first free time).
enum SessionDrag {
    static let prefix = "daybook-session:"

    static func payload(_ id: UUID) -> String { prefix + id.uuidString }

    static func sessionId(from items: [String]) -> UUID? {
        items.lazy.compactMap { item -> UUID? in
            guard item.hasPrefix(prefix) else { return nil }
            return UUID(uuidString: String(item.dropFirst(prefix.count)))
        }.first
    }
}

private struct SessionDropTarget: ViewModifier {
    @ObservedObject var appState: AppState
    let day: Date
    let after: Date?
    let ownSessionId: UUID?
    let cornerRadius: CGFloat
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .dropDestination(for: String.self) { items, _ in
                guard let id = SessionDrag.sessionId(from: items), id != ownSessionId else { return false }
                return appState.dropSession(id: id, onDay: day, after: after)
            } isTargeted: { isTargeted = $0 }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.dbAccent, style: StrokeStyle(lineWidth: 2, dash: after == nil ? [6, 4] : []))
                    .opacity(isTargeted ? 1 : 0)
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    /// Lets this session row be dragged (not for done, locked or paid-work sessions).
    @ViewBuilder
    func sessionDraggable(_ session: WorkSession?, appState: AppState) -> some View {
        if let s = session, appState.canDragSession(s) {
            self.draggable(SessionDrag.payload(s.id)) {
                Label(s.title.replacingOccurrences(of: "Work Session: ", with: ""), systemImage: "deskclock.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.dbSurface, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Color.dbInk)
            }
            .help("Drag to move: drop on an item to go right after it, or on a day for its first free time")
        } else {
            self
        }
    }

    /// Accepts dropped sessions. `after`: drop lands right after this time (an item's end); nil = first free time.
    func sessionDropTarget(appState: AppState, day: Date, after: Date? = nil, ownSessionId: UUID? = nil,
                           cornerRadius: CGFloat = 8) -> some View {
        modifier(SessionDropTarget(appState: appState, day: day, after: after, ownSessionId: ownSessionId,
                                   cornerRadius: cornerRadius))
    }
}
