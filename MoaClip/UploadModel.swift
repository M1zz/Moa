import Foundation
import Observation
import PhotosUI
import UIKit

@MainActor
@Observable
final class UploadModel {
    enum Phase: Equatable {
        case waitingForInvocation
        case loading
        case ready
        case failed(String)
    }

    struct UploadItem: Identifiable, Equatable {
        enum Status: Equatable {
            case waiting
            case preparing
            case uploading
            case done
            case failed(String)
        }

        let id = UUID()
        var status: Status = .waiting
    }

    private(set) var phase: Phase = .waitingForInvocation
    private(set) var event: EventInfo?
    private(set) var items: [UploadItem] = []
    var uploaderName: String

    private let api = MoaAPI()
    private var eventID: String?
    /// Set when the QR points at the host's iPhone on the local network instead of the relay.
    private var direct: DirectInvitation?
    private static let uploaderNameKey = "uploaderName"

    init() {
        uploaderName = UserDefaults.standard.string(forKey: Self.uploaderNameKey) ?? ""
    }

    var isUploading: Bool {
        items.contains { item in
            switch item.status {
            case .waiting, .preparing, .uploading: return true
            case .done, .failed: return false
            }
        }
    }

    var doneCount: Int { items.filter { $0.status == .done }.count }

    // MARK: Invocation

    /// Expects `https://<host>/e/<eventID>`, or a direct invitation (see `DirectInvitation`).
    func handle(url: URL) {
        if let invitation = DirectInvitation(url: url) {
            direct = invitation
            eventID = nil
            event = EventInfo(id: "direct", name: invitation.name ?? "호스트에게 바로 보내기", expiresAt: .distantFuture)
            phase = .ready
            return
        }
        direct = nil

        let components = url.pathComponents
        guard let index = components.firstIndex(of: "e"), components.indices.contains(index + 1) else {
            phase = .failed("올바른 초대 링크가 아니에요.")
            return
        }
        let id = components[index + 1]
        if id == eventID, event != nil { return }

        eventID = id
        event = nil
        phase = .loading
        Task { await loadEvent(id: id) }
    }

    private func loadEvent(id: String) async {
        do {
            let info = try await api.fetchEvent(id: id)
            guard id == eventID else { return }
            event = info
            phase = info.expiresAt < .now ? .failed("사진 받기가 종료된 이벤트예요.") : .ready
        } catch {
            guard id == eventID else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Upload

    func upload(_ results: [PHPickerResult]) {
        guard let destination, !results.isEmpty else { return }

        let trimmedName = uploaderName.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmedName, forKey: Self.uploaderNameKey)

        let providers = results.map(\.itemProvider)
        let newItems = providers.map { _ in UploadItem() }
        items.append(contentsOf: newItems)

        let jobs = Array(zip(providers, newItems.map(\.id)))
        Task {
            await run(jobs, to: destination, uploader: trimmedName.isEmpty ? nil : trimmedName)
        }
    }

    private enum Destination {
        case relay(eventID: String)
        case direct(DirectInvitation)
    }

    private var destination: Destination? {
        if let direct { return .direct(direct) }
        return eventID.map { .relay(eventID: $0) }
    }

    private func run(_ jobs: [(NSItemProvider, UUID)], to destination: Destination, uploader: String?) async {
        // Uploads die if the screen locks, so keep it awake while anything is in flight.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = isUploading }

        for (provider, localID) in jobs {
            setStatus(.preparing, for: localID)
            do {
                let media = try await MediaExporter.export(provider)
                defer { media.cleanUp() }
                setStatus(.uploading, for: localID)
                switch destination {
                case .relay(let eventID):
                    try await send(media, eventID: eventID, uploader: uploader)
                case .direct(let invitation):
                    try await DirectSender.send(media, uploader: uploader, to: invitation)
                }
                setStatus(.done, for: localID)
            } catch {
                setStatus(.failed(error.localizedDescription), for: localID)
            }
        }
    }

    private func send(_ media: PreparedMedia, eventID: String, uploader: String?) async throws {
        let itemID = UUID().uuidString
        var descriptors: [ResourceDescriptor] = []

        for resource in media.resources {
            try await api.uploadResource(
                eventID: eventID,
                itemID: itemID,
                kind: resource.kind,
                fileURL: resource.url,
                contentType: resource.contentType
            )
            descriptors.append(ResourceDescriptor(
                kind: resource.kind,
                filename: resource.url.lastPathComponent,
                contentType: resource.contentType,
                size: resource.size
            ))
        }

        let manifest = ItemManifest(
            itemID: itemID,
            uploader: uploader,
            capturedAt: media.capturedAt,
            resources: descriptors
        )
        try await api.completeItem(eventID: eventID, manifest: manifest)
    }

    private func setStatus(_ status: UploadItem.Status, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = status
    }
}
