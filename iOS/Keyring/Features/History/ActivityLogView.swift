import SwiftUI

/// Pro-only "Advanced key history": every event across every key, newest first.
struct ActivityLogView: View {
    @Environment(KeyringStore.self) private var store

    private var events: [(key: KeyEntity, event: KeyHistoryEntity)] {
        store.keyrings
            .flatMap { $0.sortedKeys }
            .flatMap { key in key.sortedHistory.map { (key, $0) } }
            .sorted { $0.event.timestamp > $1.event.timestamp }
    }

    var body: some View {
        ZStack {
            KRTheme.backdrop.ignoresSafeArea()
            if events.isEmpty {
                EmptyStateView(systemImage: "clock.arrow.circlepath", title: "No activity yet", message: "Every edit, loan, and location check-in will show up here.")
            } else {
                List(events, id: \.event.id) { item in
                    KeyHistoryRowView(event: item.event, showKeyName: item.key.name)
                        .listRowBackground(KRTheme.surface)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Activity")
    }
}
