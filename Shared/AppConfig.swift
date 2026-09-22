import Foundation

/// Central configuration shared by the host app and the App Clip.
enum AppConfig {
    static let clipBundleID = "com.leeo.moa.Clip"

    /// App Clip invocation URL on the shared GitHub Pages domain (same setup as FindMe).
    /// `m1zz.github.io/.well-known/apple-app-site-association` lists this App Clip, and
    /// `/moa/c` serves a landing page for browsers. Unlike Apple's default `appclip.apple.com`
    /// link, a domain we own can be registered as a Local Experience before release.
    static var directInvitationBaseURL: URL {
        URL(string: "https://m1zz.github.io/moa/c")!
    }
}
