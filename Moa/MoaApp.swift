import SwiftUI

@main
struct MoaApp: App {
    @State private var store = EventStore()

    var body: some Scene {
        WindowGroup {
            EventListView()
                .environment(store)
        }
    }
}
