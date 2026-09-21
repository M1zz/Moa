import SwiftUI

@main
struct MoaClipApp: App {
    @State private var model = UploadModel()

    var body: some Scene {
        WindowGroup {
            ClipRootView()
                .environment(model)
                // QR / App Clip Code / Safari banner invocations arrive as a browsing activity.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    model.handle(url: url)
                }
                // Fallback for local testing with custom URLs.
                .onOpenURL { url in
                    model.handle(url: url)
                }
        }
    }
}
