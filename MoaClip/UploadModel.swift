import Foundation
import Observation
import PhotosUI
import UIKit

@MainActor
@Observable
final class UploadModel {
    enum Phase: Equatable {
        case waitingForInvocation
        case ready
        case failed(String)
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

    private(set) var phase: Phase = .waitingForInvocation
    private(set) var eventName: String?
    private(set) var items: [UploadItem] = []
    var uploaderName: String

    private var invitation: DirectInvitation?
    /// nil until checked. Whether this guest can reach the host's iCloud mailbox.
    private(set) var canSendRemotely: Bool?
    private static let uploaderNameKey = "uploaderName"

    init() {
        uploaderName = UserDefaults.standard.string(forKey: Self.uploaderNameKey) ?? ""
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

    var sentRemotelyCount: Int {
        items.filter { $0.status == .done(remote: true) }.count
    }

    // MARK: Invocation

    /// Expects a direct invitation from the host's QR (see `DirectInvitation`).
    func handle(url: URL) {
        guard let invitation = DirectInvitation(url: url) else {
            phase = .failed("올바른 초대 링크가 아니에요.")
            return
        }
        self.invitation = invitation
        eventName = invitation.name ?? "호스트에게 바로 보내기"
        phase = .ready
        // Answer "can this go through iCloud?" before it is needed, so the first failed
        // local attempt doesn't stall behind a second network round trip.
        Task { canSendRemotely = await RemoteSender.isReachable() }
    }

    #if DEBUG
    /// `MOA_DEMO_DIR=<folder of images>`: opens a sample invitation and shows those images as
    /// already sent, so App Store screenshots show the clip mid-event.
    func loadDemo(from directory: URL) {
        var components = URLComponents(url: AppConfig.directInvitationBaseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "host", value: "192.168.0.2"), URLQueryItem(name: "port", value: "50000"),
            URLQueryItem(name: "key", value: "demo"), URLQueryItem(name: "eid", value: "demo"),
            URLQueryItem(name: "name", value: "가을 캠핑"),
        ]
        guard let url = components.url, let invitation = DirectInvitation(url: url) else { return }
        self.invitation = invitation
        eventName = invitation.name
        phase = .ready
        uploaderName = "지민"
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

        let trimmedName = uploaderName.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmedName, forKey: Self.uploaderNameKey)

        let providers = results.map(\.itemProvider)
        let newItems = providers.map { _ in UploadItem() }
        items.append(contentsOf: newItems)

        let jobs = Array(zip(providers, newItems.map(\.id)))
        Task {
            await run(jobs, to: invitation, uploader: trimmedName.isEmpty ? nil : trimmedName)
        }
    }

    private func run(_ jobs: [(NSItemProvider, UUID)], to invitation: DirectInvitation, uploader: String?) async {
        // Uploads die if the screen locks, so keep it awake while anything is in flight.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = isUploading }

        for (provider, localID) in jobs {
            setStatus(.preparing, for: localID)
            do {
                let media = try await MediaExporter.export(provider)
                defer { media.cleanUp() }
                let preview = await MediaExporter.preview(for: media)
                update(localID) {
                    $0.preview = preview
                    $0.isVideo = media.resources.contains { $0.kind == .video }
                    $0.capturedAt = media.capturedAt
                }
                setStatus(.uploading, for: localID)
                do {
                    try await DirectSender.send(media, uploader: uploader, to: invitation)
                    setStatus(.done(remote: false), for: localID)
                } catch let directError {
                    // Not on the same network, or the host closed the screen: try iCloud.
                    guard RemoteTransfer.isConfigured, canSendRemotely != false else { throw directError }
                    setStatus(.uploadingRemotely, for: localID)
                    try await RemoteSender.send(media, uploader: uploader, to: invitation)
                    setStatus(.done(remote: true), for: localID)
                }
            } catch {
                setStatus(.failed(error.localizedDescription), for: localID)
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
