import CryptoKit
import Foundation

/// Sending over the internet instead of the local network.
///
/// App Clips can't link CloudKit, but they can call CloudKit Web Services over HTTPS signed
/// with a server-to-server key, so one `MoaItem` record per item lands in the public database
/// and the host picks it up later — no server of ours, no shared Wi-Fi, no host app open.
///
/// The key ships inside the App Clip, so the public database is treated as untrusted: every
/// file and all metadata are sealed with AES-GCM under the key printed in the QR. Only someone
/// who scanned that QR can read them, and the host deletes each record once it is in Photos.
enum RemoteTransfer {
    static var isConfigured: Bool { CloudKitConfig.isConfigured }

    static let recordType = "MoaItem"
    /// Sealing happens in memory, and an App Clip has little of it. Bigger files stay
    /// local-only rather than crashing the guest's App Clip.
    static let maxRemoteResourceSize = 60 << 20

    #if DEBUG
    static let environment = "development"
    #else
    static let environment = "production"
    #endif

    /// Metadata of one item, sealed into the record's `meta` field.
    struct Meta: Codable, Sendable {
        var uploader: String?
        var capturedAt: Date?
        var location: CaptureLocation?
        var resources: [ResourceDescriptor]
    }

    struct RemoteItem: Sendable {
        let recordName: String
        let meta: Meta
        /// Download URLs in the same order as `meta.resources`.
        let assetURLs: [URL]
    }
}

enum RemoteTransferError: LocalizedError {
    case notConfigured
    case http(status: Int, body: String)
    case malformedResponse(String)
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "원거리 전송이 설정되지 않았어요."
        case let .http(status, body):
            return "iCloud가 요청을 거절했어요 (\(status)). \(body.prefix(200))"
        case .malformedResponse(let detail):
            return "iCloud 응답을 이해하지 못했어요. \(detail)"
        case .decryptionFailed:
            return "받은 사진을 풀지 못했어요. QR이 다른 이벤트의 것일 수 있어요."
        }
    }
}

// MARK: - Encryption

enum ItemCrypto {
    /// The QR key is the only secret both sides share, so it is the encryption key too.
    static func key(fromInvitationKey invitationKey: String) -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data(invitationKey.utf8)))
    }

    static func seal(_ data: Data, with key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else {
            throw RemoteTransferError.decryptionFailed
        }
        return combined
    }

    static func open(_ data: Data, with key: SymmetricKey) throws -> Data {
        do {
            return try AES.GCM.open(try AES.GCM.SealedBox(combined: data), using: key)
        } catch {
            throw RemoteTransferError.decryptionFailed
        }
    }
}

// MARK: - CloudKit Web Services

/// Minimal signed client for the public database. Both targets use it: the App Clip to upload,
/// the host to list, download and delete.
struct CloudKitWebService: Sendable {
    private let session = URLSession(configuration: .default)

    private var base: String {
        "/database/1/\(CloudKitConfig.containerID)/\(RemoteTransfer.environment)/public"
    }

    // MARK: Requests

    func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        guard CloudKitConfig.isConfigured else { throw RemoteTransferError.notConfigured }
        let subpath = base + path
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "https://api.apple-cloudkit.com\(subpath)")!)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let date = ISO8601DateFormatter.cloudKit.string(from: Date())
        request.setValue(CloudKitConfig.keyID, forHTTPHeaderField: "X-Apple-CloudKit-Request-KeyID")
        request.setValue(date, forHTTPHeaderField: "X-Apple-CloudKit-Request-ISO8601Date")
        request.setValue(try sign(date: date, body: bodyData, subpath: subpath),
                         forHTTPHeaderField: "X-Apple-CloudKit-Request-SignatureV1")

        let (data, response) = try await session.data(for: request)
        try check(response, data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RemoteTransferError.malformedResponse("not an object")
        }
        return json
    }

    /// Uploads one file to the URL handed out by `/assets/upload` and returns the receipt
    /// that goes into the record field.
    func uploadAsset(_ fileURL: URL, fieldName: String) async throws -> [String: Any] {
        let prepared = try await post("/assets/upload", body: [
            "tokens": [["recordType": RemoteTransfer.recordType, "fieldName": fieldName]]
        ])
        guard let tokens = prepared["tokens"] as? [[String: Any]],
              let urlString = tokens.first?["url"] as? String,
              let url = URL(string: urlString) else {
            throw RemoteTransferError.malformedResponse("no upload url")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: request, fromFile: fileURL)
        try check(response, data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let single = json["singleFile"] as? [String: Any] else {
            throw RemoteTransferError.malformedResponse("no singleFile receipt")
        }
        return single
    }

    func download(_ url: URL, to destination: URL) async throws {
        let (temporary, response) = try await session.download(from: url)
        try check(response, nil)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    // MARK: Plumbing

    private func check(_ response: URLResponse, _ data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw RemoteTransferError.http(
                status: http.statusCode,
                body: data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            )
        }
    }

    /// Signs "[date]:[base64(sha256(body))]:[subpath]" with the server-to-server key.
    private func sign(date: String, body: Data, subpath: String) throws -> String {
        guard let keyData = Data(base64Encoded: CloudKitConfig.privateKeyBase64) else {
            throw RemoteTransferError.notConfigured
        }
        let message = "\(date):\(Data(SHA256.hash(data: body)).base64EncodedString()):\(subpath)"
        let privateKey = try P256.Signing.PrivateKey(derRepresentation: keyData)
        return try privateKey.signature(for: Data(message.utf8)).derRepresentation.base64EncodedString()
    }
}

extension ISO8601DateFormatter {
    static let cloudKit: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
