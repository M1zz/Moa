import SwiftUI

struct EventListView: View {
    @Environment(EventStore.self) private var store
    @State private var isCreating = false
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.events.isEmpty {
                    ContentUnavailableView {
                        Label("아직 이벤트가 없어요", systemImage: "qrcode")
                    } description: {
                        Text("이벤트를 만들고 QR을 보여주면, 같은 Wi-Fi에 있는 사람이 앱 설치 없이 이 iPhone으로 사진을 보낼 수 있어요. 받은 사진은 촬영 시각 그대로 사진 앱에 들어가요.")
                    } actions: {
                        Button("이벤트 만들기") { isCreating = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(store.events) { event in
                            NavigationLink(value: event.id) {
                                EventRow(event: event)
                            }
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("모아")
            .navigationDestination(for: String.self) { id in
                EventDetailView(eventID: id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("이벤트 만들기")
                }
            }
            .sheet(isPresented: $isCreating) {
                CreateEventView()
            }
            #if DEBUG
            // `-moa-auto-event` opens a receiving event straight away, so the flow can be
            // exercised from the console without tapping through the UI.
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-moa-auto-event"), path.isEmpty else { return }
                NSLog("[moa] auto-event starting")
                var event = store.events.first
                if event == nil {
                    do {
                        event = try await store.createEvent(name: "디버그 이벤트")
                    } catch {
                        NSLog("[moa] auto-event create failed: \(error)")
                    }
                }
                if let event { path = [event.id] }
            }
            #endif
        }
    }
}

private struct EventRow: View {
    let event: HostedEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.name)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let count = "받은 사진 \(event.receivedCount)개"
        guard let last = event.lastReceivedAt else { return count }
        return "\(count) · 마지막 \(last.formatted(date: .abbreviated, time: .shortened))"
    }
}
