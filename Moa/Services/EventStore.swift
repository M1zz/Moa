import Foundation
import Observation
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
            uploaders: [:]
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

    func recordImport(eventID: String, assetID: String?, uploader: String?) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        events[index].receivedCount += 1
        events[index].lastReceivedAt = .now
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
        let albumID = try? await PhotoLibraryService.createAlbum(named: "가을 캠핑")
        let fetched = PHAsset.fetchAssets(with: .image, options: nil)
        let assets = (0..<fetched.count).map { fetched.object(at: $0) }
        if let albumID,
           let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject {
            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest(for: album)?.addAssets(assets as NSArray)
            }
        }
        let names = ["지민", "서준", "하은", "도윤", "민서", "유나"]
        var uploaders: [String: String] = [:]
        for (index, asset) in assets.enumerated() {
            uploaders[asset.localIdentifier] = names[index % names.count]
        }
        let now = Date.now
        let main = HostedEvent(
            id: UUID().uuidString, name: "가을 캠핑", createdAt: now, albumIdentifier: albumID,
            receivedCount: assets.count, lastReceivedAt: now.addingTimeInterval(-120), uploaders: uploaders
        )
        func past(_ name: String, days: Double, count: Int) -> HostedEvent {
            let date = now.addingTimeInterval(-days * 86_400)
            return HostedEvent(id: UUID().uuidString, name: name, createdAt: date, albumIdentifier: nil,
                               receivedCount: count, lastReceivedAt: date.addingTimeInterval(7_200), uploaders: nil)
        }
        events = [
            main,
            past("지민이 돌잔치", days: 9, count: 128),
            past("9월 멘토링 세션", days: 16, count: 47),
            past("대학 동기 모임", days: 31, count: 86),
            past("제주 가족 여행", days: 58, count: 312),
        ]
        save()
        return main
    }
    #endif

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
