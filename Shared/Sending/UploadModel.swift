import Foundation
import Observation
import PhotosUI
import UIKit

@MainActor
@Observable
final class UploadModel {
    enum Phase: Equatable {
        /// No usable invitation yet. `linkHadNoEvent` is true when the clip was opened through a
        /// link without one, e.g. the default App Clip link or the App Store demo URL.
        case waitingForInvocation(linkHadNoEvent: Bool)
        case ready
    }

    struct UploadItem: Identifiable, Equatable {
        enum Status: Equatable {
            case waiting
            case preparing
            case uploading
            /// Local network didn't work; going through iCloud instead.
            case uploadingRemotely
            case done(remote: Bool)
            case failed(String)
        }

        let id = UUID()
        var status: Status = .waiting
        var preview: UIImage?
        var isVideo = false
        var capturedAt: Date?
    }

    private(set) var phase: Phase = .waitingForInvocation(linkHadNoEvent: false)
    private(set) var eventName: String?
    private(set) var items: [UploadItem] = []
    var uploaderName: String

    /// How one photo travels.
    enum Route {
        /// A guest (the App Clip): straight to the iPhone that made the album when it is
        /// nearby, which then shares it with everyone; otherwise into the album's feed.
        case guest
        /// A member's own app adding to their album: into the feed first, so every member gets
        /// it; the album's iPhone nearby only when there is no internet (not when this is it).
        case member(isOwner: Bool)
    }

    private var invitation: DirectInvitation?
    let route: Route
    /// The app picks from the library so a photo it adds can join its own album without a copy.
    var picksFromLibrary: Bool { if case .member = route { true } else { false } }
    /// Called after each photo reaches the album, with its library id (member route only)
    /// and the feed record it went into, if any.
    var onSent: ((_ assetIdentifier: String?, _ record: String?) -> Void)?
    /// nil until checked. Whether this guest can reach the host's iCloud mailbox.
    private(set) var canSendRemotely: Bool?
    /// The app looks for the host nearby (no network needed); the App Clip can't use Bonjour.
    private let nearby: NearbyHostFinder?

    init(route: Route = .guest) {
        self.route = route
        uploaderName = MemberName.current
        // The App Clip can't use Bonjour; the app finds the album's iPhone nearby with no network.
        if case .member(isOwner: false) = route {
            nearby = NearbyHostFinder()
        } else {
            nearby = nil
        }
    }

    func stop() {
        nearby?.stop()
    }

    var isUploading: Bool {
        items.contains { item in
            switch item.status {
            case .waiting, .preparing, .uploading, .uploadingRemotely: return true
            case .done, .failed: return false
            }
        }
    }

    var doneCount: Int {
        items.filter { if case .done = $0.status { return true } else { return false } }.count
    }

    // MARK: Invocation

    /// Expects a direct invitation from the host's QR (see `DirectInvitation`). Any other link
    /// (the default App Clip link, the App Store demo URL, an old or cropped QR) shows how to
    /// get one instead of an error, since that is all the guest can do about it.
    func handle(url: URL) {
        guard let invitation = DirectInvitation(url: url) else {
            if self.invitation == nil { phase = .waitingForInvocation(linkHadNoEvent: true) }
            return
        }
        self.invitation = invitation
        eventName = invitation.name ?? String(localized: "호스트에게 바로 보내기")
        phase = .ready
        nearby?.start(eventID: invitation.eventID)
        // Answer "can this go through iCloud?" before it is needed, so the first failed
        // local attempt doesn't stall behind a second network round trip.
        Task { canSendRemotely = await RemoteSender.isReachable() }
    }

    #if DEBUG
    /// `MOA_DEMO_DIR=<folder of images>`: opens a sample invitation and shows those images as
    /// already sent, so App Store screenshots show the clip mid-event.
    func loadDemo(from directory: URL) {
        let sample = ScreenshotSamples.current
        var components = URLComponents(url: AppConfig.directInvitationBaseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "host", value: "192.168.0.2"), URLQueryItem(name: "port", value: "50000"),
            URLQueryItem(name: "key", value: "demo"), URLQueryItem(name: "eid", value: "demo"),
            URLQueryItem(name: "name", value: sample.events[0]),
        ]
        guard let url = components.url, let invitation = DirectInvitation(url: url) else { return }
        self.invitation = invitation
        eventName = invitation.name
        phase = .ready
        uploaderName = sample.people[0]
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        items = files.enumerated().compactMap { index, file in
            guard let image = UIImage(contentsOfFile: file.path) else { return nil }
            var item = UploadItem()
            item.preview = image.preparingThumbnail(of: CGSize(width: 600, height: 600 * image.size.height / image.size.width))
            item.status = index == files.count - 1 ? .uploading : .done(remote: false)
            return item
        }
    }
    #endif

    // MARK: Upload

    func upload(_ results: [PHPickerResult]) {
        guard let invitation, !results.isEmpty else { return }

        MemberName.set(uploaderName)
        let trimmedName = MemberName.current

        let newItems = results.map { _ in UploadItem() }
        items.append(contentsOf: newItems)

        let jobs = zip(results, newItems).map { Job(provider: $0.itemProvider, assetIdentifier: $0.assetIdentifier, localID: $1.id) }
        Task {
            await run(jobs, to: invitation, uploader: trimmedName.isEmpty ? nil : trimmedName)
        }
    }

    private struct Job {
        let provider: NSItemProvider
        let assetIdentifier: String?
        let localID: UUID
    }

    private func run(_ jobs: [Job], to invitation: DirectInvitation, uploader: String?) async {
        // Uploads die if the screen locks, so keep it awake while anything is in flight.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = isUploading }

        for job in jobs {
            let localID = job.localID
            setStatus(.preparing, for: localID)
            do {
                let media = try await MediaExporter.export(job.provider)
                defer { media.cleanUp() }
                let preview = await MediaExporter.preview(for: media)
                update(localID) {
                    $0.preview = preview
                    $0.isVideo = media.resources.contains { $0.kind == .video }
                    $0.capturedAt = media.capturedAt
                }
                setStatus(.uploading, for: localID)
                let record = try await send(media, uploader: uploader, to: invitation, localID: localID)
                onSent?(job.assetIdentifier, record)
            } catch {
                setStatus(.failed(error.localizedDescription), for: localID)
            }
        }
    }

    /// Returns the feed record when it went into the feed.
    private func send(_ media: PreparedMedia, uploader: String?, to invitation: DirectInvitation,
                      localID: UUID) async throws -> String? {
        let me = [DeviceID.current]
        switch route {
        case .guest:
            do {
                try await DirectSender.send(media, uploader: uploader, from: DeviceID.current, to: invitation)
                setStatus(.done(remote: false), for: localID)
                return nil
            } catch let directError {
                // Not on the same network, or the album's iPhone closed the screen: use the feed.
                guard RemoteTransfer.isConfigured, canSendRemotely != false else { throw directError }
                setStatus(.uploadingRemotely, for: localID)
                let record = try await RemoteSender.send(media, uploader: uploader, holders: me, to: invitation)
                setStatus(.done(remote: true), for: localID)
                return record
            }
        case .member(let isOwner):
            do {
                guard RemoteTransfer.isConfigured else { throw RemoteTransferError.notConfigured }
                let record = try await RemoteSender.send(media, uploader: uploader, holders: me, to: invitation)
                setStatus(.done(remote: true), for: localID)
                return record
            } catch let remoteError {
                // No internet: hand it to the album's iPhone nearby, which shares it later.
                guard !isOwner else { throw remoteError }
                let nearbyHost = await nearby?.waitForEndpoint()
                try await DirectSender.send(media, uploader: uploader, from: DeviceID.current,
                                            to: invitation, nearby: nearbyHost)
                setStatus(.done(remote: false), for: localID)
                return nil
            }
        }
    }

    private func setStatus(_ status: UploadItem.Status, for id: UUID) {
        update(id) { $0.status = status }
    }

    private func update(_ id: UUID, _ body: (inout UploadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        body(&items[index])
    }
}
