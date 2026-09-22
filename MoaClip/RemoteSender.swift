import CryptoKit
import Foundation

/// Uploads one item to the host's iCloud mailbox when the local network route didn't work.
/// Everything is encrypted with the key from the QR before it leaves the phone.
enum RemoteSender {
    private static let service = CloudKitWebService()

    /// Can this guest reach the mailbox at all? Checked once so a guest who is offline,
    /// or an app built without a key, fails fast with a clear message instead of a long wait.
    static func isReachable() async -> Bool {
        guard RemoteTransfer.isConfigured else { return false }
        do {
            _ = try await service.post("/records/query", body: [
                "query": ["recordType": RemoteTransfer.recordType],
                "resultsLimit": 1
            ])
            return true
        } catch {
            return false
        }
    }

    static func send(_ media: PreparedMedia, uploader: String?, to invitation: DirectInvitation) async throws {
        guard RemoteTransfer.isConfigured else { throw RemoteTransferError.notConfigured }
        if let tooBig = media.resources.first(where: { $0.size > RemoteTransfer.maxRemoteResourceSize }) {
            throw RemoteSenderError.tooLarge(megabytes: tooBig.size / (1 << 20))
        }

        let key = ItemCrypto.key(fromInvitationKey: invitation.key)
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        var assetFields: [String: Any] = [:]
        for (index, resource) in media.resources.enumerated() {
            let sealed = try ItemCrypto.seal(try Data(contentsOf: resource.url), with: key)
            let sealedURL = workDirectory.appendingPathComponent("a\(index)")
            try sealed.write(to: sealedURL)
            let fieldName = "a\(index)"
            assetFields[fieldName] = ["value": try await service.uploadAsset(sealedURL, fieldName: fieldName)]
        }

        let meta = RemoteTransfer.Meta(
            uploader: uploader,
            capturedAt: media.capturedAt,
            location: media.location,
            resources: media.resources.map {
                ResourceDescriptor(kind: $0.kind, filename: $0.url.lastPathComponent,
                                   contentType: $0.contentType, size: $0.size)
            }
        )
        let sealedMeta = try ItemCrypto.seal(try JSONCoding.encoder.encode(meta), with: key)

        var fields: [String: Any] = [
            // Plain text so the host can find its own items; it reveals nothing but a random id.
            "eventID": ["value": invitation.eventID],
            "meta": ["value": sealedMeta.base64EncodedString()]
        ]
        fields.merge(assetFields) { current, _ in current }

        _ = try await service.post("/records/modify", body: [
            "operations": [[
                "operationType": "create",
                "record": ["recordType": RemoteTransfer.recordType, "fields": fields]
            ]]
        ])
    }
}

enum RemoteSenderError: LocalizedError {
    case tooLarge(megabytes: Int)

    var errorDescription: String? {
        switch self {
        case .tooLarge(let megabytes):
            return "\(megabytes)MB라서 멀리 있는 호스트에게는 보낼 수 없어요. 같은 Wi-Fi에서 보내 주세요."
        }
    }
}
