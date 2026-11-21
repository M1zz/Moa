import Foundation

/// An event on this device. Guests send straight to this iPhone while the event screen is open,
/// so nothing about it lives on a server.
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

    /// Still worth checking iCloud for: guests keep sending for a while after an event.
    var isRecent: Bool {
        max(createdAt, lastReceivedAt ?? createdAt) > .now.addingTimeInterval(-3 * 86_400)
    }
}
