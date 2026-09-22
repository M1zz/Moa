import CryptoKit
import Foundation

/// The host side of remote sending: lists what guests left in the iCloud mailbox for this
/// event, decrypts it, hands it to Photos, and deletes the record.
enum RemoteInbox {
    private static let service = CloudKitWebService()

    static var isConfigured: Bool { RemoteTransfer.isConfigured }

    struct FetchResult {
        /// Photos asset id and who sent it, for each item imported in this pass.
        var imported: [(assetID: String?, uploader: String?)] = []
        var failed = 0

        var lastUploader: String? { imported.last?.uploader }
    }

    static func fetch(
        eventID: String,
        invitationKey: String,
        albumIdentifier: String?
    ) async throws -> FetchResult {
        guard RemoteTransfer.isConfigured else { throw RemoteTransferError.notConfigured }
        let key = ItemCrypto.key(fromInvitationKey: invitationKey)
        var result = FetchResult()

        for item in try await list(eventID: eventID, key: key) {
            do {
                let assetID = try await importItem(item, key: key, albumIdentifier: albumIdentifier)
                result.imported.append((assetID: assetID, uploader: item.meta.uploader))
                // Only delete once it is safely in Photos.
                try? await delete(recordName: item.recordName)
            } catch {
                result.failed += 1
                #if DEBUG
                NSLog("[moa] remote import failed: \(error)")
                #endif
            }
        }
        return result
    }

    // MARK: Pieces

    private static func list(eventID: String, key: SymmetricKey) async throws -> [RemoteTransfer.RemoteItem] {
        let response = try await service.post("/records/query", body: [
            "query": [
                "recordType": RemoteTransfer.recordType,
                "filterBy": [[
                    "fieldName": "eventID",
                    "comparator": "EQUALS",
                    "fieldValue": ["value": eventID]
                ]]
            ],
            "resultsLimit": 50
        ])

        guard let records = response["records"] as? [[String: Any]] else { return [] }
        return records.compactMap { record in
            guard let recordName = record["recordName"] as? String,
                  let fields = record["fields"] as? [String: Any],
                  let metaField = fields["meta"] as? [String: Any],
                  let metaBase64 = metaField["value"] as? String,
                  let sealedMeta = Data(base64Encoded: metaBase64),
                  let metaData = try? ItemCrypto.open(sealedMeta, with: key),
                  let meta = try? JSONCoding.decoder.decode(RemoteTransfer.Meta.self, from: metaData)
            else { return nil }

            let urls: [URL] = meta.resources.indices.compactMap { index in
                guard let field = fields["a\(index)"] as? [String: Any],
                      let value = field["value"] as? [String: Any],
                      let string = value["downloadURL"] as? String else { return nil }
                // CloudKit escapes the URL for JS consumers.
                return URL(string: string.replacingOccurrences(of: "${f}", with: ""))
            }
            guard urls.count == meta.resources.count else { return nil }
            return RemoteTransfer.RemoteItem(recordName: recordName, meta: meta, assetURLs: urls)
        }
    }

    private static func importItem(
        _ item: RemoteTransfer.RemoteItem,
        key: SymmetricKey,
        albumIdentifier: String?
    ) async throws -> String? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var files: [ResourceKind: URL] = [:]
        for (index, resource) in item.meta.resources.enumerated() {
            let sealedURL = directory.appendingPathComponent("sealed-\(index)")
            try await service.download(item.assetURLs[index], to: sealedURL)

            // Keep only the extension so Photos recognizes the format.
            let ext = (resource.filename as NSString).pathExtension.filter { $0.isLetter || $0.isNumber }
            var url = directory.appendingPathComponent(UUID().uuidString)
            if !ext.isEmpty { url.appendPathExtension(ext) }
            try ItemCrypto.open(try Data(contentsOf: sealedURL), with: key).write(to: url)
            files[resource.kind] = url
        }

        return try await PhotoLibraryService.importAsset(
            photo: files[.photo],
            pairedVideo: files[.pairedVideo],
            video: files[.video],
            capturedAt: item.meta.capturedAt,
            location: item.meta.location,
            albumIdentifier: albumIdentifier
        )
    }

    private static func delete(recordName: String) async throws {
        _ = try await service.post("/records/modify", body: [
            "operations": [[
                "operationType": "forceDelete",
                "record": ["recordName": recordName]
            ]]
        ])
    }
}
