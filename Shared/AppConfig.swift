import Foundation

/// Central configuration shared by the host app and the App Clip.
enum AppConfig {
    /// Domain that serves the relay Worker. Must match the `appclips:` associated domain
    /// in Config/MoaClip.entitlements and the App Clip experience URL in App Store Connect.
    static let host = "moa.example.com"

    static var baseURL: URL { URL(string: "https://\(host)")! }

    /// URL encoded into the QR code. Invokes the App Clip on iPhone.
    static func invitationURL(eventID: String) -> URL {
        baseURL.appendingPathComponent("e").appendingPathComponent(eventID)
    }

    static let clipBundleID = "com.leeo.moa.Clip"

    /// Apple's default App Clip link (iOS 17+). Works without a domain of our own once the
    /// App Clip is set up in App Store Connect; before that, register it as a Local Experience.
    static var directInvitationBaseURL: URL {
        URL(string: "https://appclip.apple.com/id?p=\(clipBundleID)")!
    }
}
