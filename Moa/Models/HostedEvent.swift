import Foundation

/// A shared album on this device: one this iPhone made, or one it joined through a link or QR.
///
/// Whoever has the link is a member. Photos travel through the album's encrypted feed in iCloud
/// (`RemoteTransfer`), and each member's app copies them into its own Photos album. Guests
/// nearby can also send straight to the iPhone that made it while its album screen is open.
struct HostedEvent: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var createdAt: Date
    /// Local identifier of the Photos album created for this event, if any.
    var albumIdentifier: String?
    var receivedCount: Int
    var lastReceivedAt: Date?
    /// Photos asset id → who sent it. Optional so events saved before this existed still load.
    var uploaders: [String: String]?
    /// The key in this event's QR. It stays the same for the whole event, so a guest who scanned
    /// earlier, or opens a shared link later, can still send — and photos they left in iCloud,
    /// sealed with this key, can always be opened. Optional for events saved before it existed.
    var inviteKey: String?
    /// The port the QR last pointed at. Reused when possible so an earlier QR still reaches
    /// this iPhone directly on the same Wi-Fi.
    var invitePort: UInt16?
    /// Joined through someone else's link, rather than made here. Optional for older events.
    var joined: Bool?
    /// For a joined album: the address of the iPhone that made it, as the link gave it.
    var inviteHost: String?
    /// Feed records this device is done with, so nothing is brought in twice.
    var syncedRecords: [String]?
    /// Names of everyone who has joined or added to the album, from its feed.
    var members: [String]?

    var isJoined: Bool { joined ?? false }

    /// The link of a joined album. The one this iPhone made comes from its receiver, which
    /// knows the current address.
    var joinedInvitation: DirectInvitation? {
        guard isJoined, let inviteKey, let inviteHost, let invitePort else { return nil }
        return DirectInvitation(host: inviteHost, port: invitePort, key: inviteKey, name: name, eventID: id)
    }

}
