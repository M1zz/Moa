import Foundation

/// Central configuration shared by the host app and the App Clip.
enum AppConfig {
    static let clipBundleID = "com.leeo.moa.Clip"

    /// Apple's default App Clip link (iOS 17+). Works without a domain or server of our own once
    /// the App Clip is set up in App Store Connect; before that, register it as a Local Experience.
    static var directInvitationBaseURL: URL {
        URL(string: "https://appclip.apple.com/id?p=\(clipBundleID)")!
    }
}
