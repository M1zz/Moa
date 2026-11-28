import Foundation
import Observation
import LeeoKit
#if DEBUG
import Photos
#endif

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
            lastReceivedAt: nil,
            uploaders: [:],
            inviteKey: Self.makeInviteKey()
        )
        events.insert(event, at: 0)
        save()
        announce(event)
        return event
    }

    /// Opens someone's link or QR: the album is added here and its photos start coming in.
    /// Nobody has to add anyone — having the link is being a member.
    func join(_ invitation: DirectInvitation) async throws -> HostedEvent {
        if let existing = event(id: invitation.eventID) { return existing }
        guard await PhotoLibraryService.requestAccess() else { throw PhotoLibraryError.accessDenied }
        let name = invitation.name ?? String(localized: "공유 앨범")
        let albumID = try? await PhotoLibraryService.createAlbum(named: name)

        let event = HostedEvent(
            id: invitation.eventID,
            name: name,
            createdAt: .now,
            albumIdentifier: albumID,
            receivedCount: 0,
            lastReceivedAt: nil,
            uploaders: [:],
            inviteKey: invitation.key,
            invitePort: invitation.port,
            joined: true,
            inviteHost: invitation.host
        )
        events.insert(event, at: 0)
        save()
        announce(event)
        Task { _ = try? await pullRemote(eventID: event.id) }
        return event
    }

    /// Leaves a name in the feed so the other members see who is in. Without a name there is
    /// nothing to show, and the member appears once they add a photo.
    private func announce(_ event: HostedEvent) {
        let name = MemberName.current
        guard !name.isEmpty, RemoteInbox.isConfigured, let key = event.inviteKey else { return }
        let invitation = DirectInvitation(host: event.inviteHost ?? "-", port: event.invitePort ?? 0,
                                          key: key, name: event.name, eventID: event.id)
        Task {
            if let record = try? await RemoteSender.announceJoin(name: name, to: invitation) {
                markSynced(record, eventID: event.id)
            }
            var members = self.event(id: event.id)?.members ?? []
            if !members.contains(name) { members.append(name) }
            update(event.id) { $0.members = members }
        }
    }

    /// Photos this device added to the album itself: they are already in the library, so they
    /// only join the album here, and the feed copy is skipped.
    func recordOwnAdd(eventID: String, assetIdentifier: String?, record: String?) async {
        if let record { markSynced(record, eventID: eventID) }
        guard let event = event(id: eventID) else { return }
        if let assetIdentifier {
            await PhotoLibraryService.addExisting(assetIdentifier: assetIdentifier, to: event.albumIdentifier)
        }
        recordImport(eventID: eventID, assetID: assetIdentifier, uploader: MemberName.current)
    }

    func markSynced(_ record: String, eventID: String) {
        update(eventID) { event in
            var synced = event.syncedRecords ?? []
            if !synced.contains(record) { synced.append(record) }
            event.syncedRecords = synced
        }
    }

    private func update(_ eventID: String, _ body: (inout HostedEvent) -> Void) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        body(&events[index])
        save()
    }

    /// Leaves the album on this device only. Photos already brought in stay in the library,
    /// and the other members keep theirs.
    func delete(at offsets: IndexSet) {
        events = events.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        save()
    }

    // MARK: Invitation

    /// This event's QR key, made once and kept (see `HostedEvent.inviteKey`).
    func inviteKey(for eventID: String) -> String? {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return nil }
        if let key = events[index].inviteKey { return key }
        let key = Self.makeInviteKey()
        events[index].inviteKey = key
        save()
        return key
    }

    func rememberPort(_ port: UInt16, for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }),
              events[index].invitePort != port else { return }
        events[index].invitePort = port
        save()
    }

    private static func makeInviteKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: Remote (iCloud) inbox

    private var pulling: Set<String> = []

    /// Brings in what the other members added to this album. The album screen, app launch and
    /// background refresh all come through here, one pass per album at a time, so the same
    /// record is never imported twice. nil when there is nothing to do or a pass is running.
    func pullRemote(eventID: String) async throws -> RemoteInbox.FetchResult? {
        guard RemoteInbox.isConfigured, !pulling.contains(eventID),
              let event = event(id: eventID), let key = event.inviteKey else { return nil }
        pulling.insert(eventID)
        defer { pulling.remove(eventID) }
        let result = try await RemoteInbox.fetch(
            eventID: eventID, invitationKey: key, albumIdentifier: event.albumIdentifier,
            skipping: Set(event.syncedRecords ?? [])
        )
        for item in result.imported {
            recordImport(eventID: eventID, assetID: item.assetID, uploader: item.uploader)
        }
        update(eventID) { event in
            event.syncedRecords = (event.syncedRecords ?? []) + result.seen.filter { !(event.syncedRecords ?? []).contains($0) }
            if !result.members.isEmpty {
                let mine = event.members ?? []
                event.members = result.members + mine.filter { !result.members.contains($0) }
            }
        }
        return result
    }

    /// Checks every album and returns how many items each brought in.
    func pullAllRemote() async -> [(event: HostedEvent, count: Int)] {
        var pulled: [(HostedEvent, Int)] = []
        for event in events where event.inviteKey != nil {
            if let result = try? await pullRemote(eventID: event.id), !result.imported.isEmpty {
                pulled.append((event, result.imported.count))
            }
        }
        return pulled
    }

    func recordImport(eventID: String, assetID: String?, uploader: String?) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        events[index].receivedCount += 1
        events[index].lastReceivedAt = .now
        // 행사마다 첫 장만 센다 — QR 이 실제로 사진을 데려온 순간. 장마다 세면 행사 하나가 수백 건이 된다.
        if events[index].receivedCount == 1 {
            LeeoAnalyticsCenter.track(.custom(name: "photos_received", parameters: [:]))
        }
        if let assetID, let uploader, !uploader.isEmpty {
            var uploaders = events[index].uploaders ?? [:]
            uploaders[assetID] = uploader
            events[index].uploaders = uploaders
        }
        save()
    }


    #if DEBUG
    /// `-moa-screenshots`: fills the list with sample events and puts the library's photos into
    /// the first event's album, so App Store screenshots show a lived-in app.
    func seedForScreenshots() async -> HostedEvent? {
        guard await PhotoLibraryService.requestAccess() else { return nil }
        // Sample names follow the app's language so each locale's screenshots read naturally.
        let sample = ScreenshotSamples.current
        let mainName = sample.events[0]
        let albumID = try? await PhotoLibraryService.createAlbum(named: mainName)
        let fetched = PHAsset.fetchAssets(with: .image, options: nil)
        let assets = (0..<fetched.count).map { fetched.object(at: $0) }
        if let albumID,
           let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject {
            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest(for: album)?.addAssets(assets as NSArray)
            }
        }
        let names = sample.people
        var uploaders: [String: String] = [:]
        for (index, asset) in assets.enumerated() {
            uploaders[asset.localIdentifier] = names[index % names.count]
        }
        let now = Date.now
        let main = HostedEvent(
            id: UUID().uuidString, name: mainName, createdAt: now, albumIdentifier: albumID,
            receivedCount: assets.count, lastReceivedAt: now.addingTimeInterval(-120), uploaders: uploaders
        )
        func past(_ name: String, days: Double, count: Int) -> HostedEvent {
            let date = now.addingTimeInterval(-days * 86_400)
            return HostedEvent(id: UUID().uuidString, name: name, createdAt: date, albumIdentifier: nil,
                               receivedCount: count, lastReceivedAt: date.addingTimeInterval(7_200), uploaders: nil)
        }
        events = [
            main,
            past(sample.events[1], days: 9, count: 128),
            past(sample.events[2], days: 16, count: 47),
            past(sample.events[3], days: 31, count: 86),
            past(sample.events[4], days: 58, count: 312),
        ]
        save()
        return main
    }
    #endif

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONCoding.decoder.decode([HostedEvent].self, from: data) else {
            // 못 읽은 원본을 옆에 남긴다 — 빈 목록으로 시작해 다음 저장이 덮어써도 되찾을 수 있게
            try? FileManager.default.copyItem(at: fileURL, to: fileURL.appendingPathExtension("unreadable"))
            return
        }
        events = decoded
    }

    private func save() {
        guard let data = try? JSONCoding.encoder.encode(events) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
