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
}
