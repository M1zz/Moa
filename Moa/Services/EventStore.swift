import Foundation
import Observation

@MainActor
@Observable
final class EventStore {
    private(set) var events: [HostedEvent] = []

    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("events.json")
        load()
    }

    func event(id: String) -> HostedEvent? {
        events.first { $0.id == id }
    }

    // MARK: Lifecycle

    func createEvent(name: String) async throws -> HostedEvent {
        guard await PhotoLibraryService.requestAccess() else { throw PhotoLibraryError.accessDenied }

        // An album is nice to have; importing still works without one (e.g. limited access).
        let albumID = try? await PhotoLibraryService.createAlbum(named: name)

        let event = HostedEvent(
            id: UUID().uuidString,
            name: name,
            createdAt: .now,
            albumIdentifier: albumID,
            receivedCount: 0,
            lastReceivedAt: nil
        )
        events.insert(event, at: 0)
        save()
        return event
    }

    /// Removes the event from this device only. Photos already imported stay in the library.
    func delete(at offsets: IndexSet) {
        events = events.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        save()
    }

    func recordImport(eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        events[index].receivedCount += 1
        events[index].lastReceivedAt = .now
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONCoding.decoder.decode([HostedEvent].self, from: data) else { return }
        events = decoded
    }

    private func save() {
        guard let data = try? JSONCoding.encoder.encode(events) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
