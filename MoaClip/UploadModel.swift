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
            case done
            case failed(String)
        }

        let id = UUID()
        var status: Status = .waiting
    }

    private(set) var phase: Phase = .waitingForInvocation
    private(set) var eventName: String?
    private(set) var items: [UploadItem] = []
    var uploaderName: String

    private var invitation: DirectInvitation?
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

    /// Expects a direct invitation from the host's QR (see `DirectInvitation`).
    func handle(url: URL) {
        guard let invitation = DirectInvitation(url: url) else {
            phase = .failed("올바른 초대 링크가 아니에요.")
            return
        }
        self.invitation = invitation
        eventName = invitation.name ?? "호스트에게 바로 보내기"
        phase = .ready
    }

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
                setStatus(.uploading, for: localID)
                try await DirectSender.send(media, uploader: uploader, to: invitation)
                setStatus(.done, for: localID)
            } catch {
                setStatus(.failed(error.localizedDescription), for: localID)
            }
        }
    }

    private func setStatus(_ status: UploadItem.Status, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = status
    }
}
