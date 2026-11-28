import CryptoKit
import Foundation

/// Reads an album's shared feed in iCloud (see `RemoteTransfer`): every item this device
/// hasn't seen yet is decrypted and put in its own Photos album. Nothing is deleted — the
/// other members still need it.
enum RemoteInbox {
    private static let service = CloudKitWebService()

    static var isConfigured: Bool { RemoteTransfer.isConfigured }

    struct FetchResult {
        /// Photos asset id and who sent it, for each item imported in this pass.
        var imported: [(assetID: String?, uploader: String?)] = []
        var failed = 0
        /// Records that are done with for this device: imported, or nothing to import.
        var seen: [String] = []
        /// Everyone who has joined or added to the album, oldest first.
        var members: [String] = []

        var lastUploader: String? { imported.last?.uploader }
    }

    static func fetch(
        eventID: String,
        invitationKey: String,
        albumIdentifier: String?,
        skipping seen: Set<String>
    ) async throws -> FetchResult {
        guard RemoteTransfer.isConfigured else { throw RemoteTransferError.notConfigured }
        let key = ItemCrypto.key(fromInvitationKey: invitationKey)
        let me = DeviceID.current
        var result = FetchResult()

        for item in try await list(eventID: eventID, key: key) {
            if let name = item.meta.uploader, !name.isEmpty, !result.members.contains(name) {
                result.members.append(name)
            }
            guard !seen.contains(item.recordName) else { continue }
            // A join record, or something this device sent or shared itself.
            if item.meta.resources.isEmpty || item.meta.holders?.contains(me) == true {
                result.seen.append(item.recordName)
                continue
            }
            // Background time ran out: stop between items, the rest come next time.
            if Task.isCancelled { continue }
            do {
                let assetID = try await importItem(item, key: key, albumIdentifier: albumIdentifier)
                result.imported.append((assetID: assetID, uploader: item.meta.uploader))
                result.seen.append(item.recordName)
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

    /// The whole feed, page by page. Records sealed with another key (or damaged) are skipped.
    private static func list(eventID: String, key: SymmetricKey) async throws -> [RemoteTransfer.RemoteItem] {
        var items: [RemoteTransfer.RemoteItem] = []
        var marker: String?
        repeat {
            var body: [String: Any] = [
                "query": [
                    "recordType": RemoteTransfer.recordType,
                    "filterBy": [[
                        "fieldName": "eventID",
                        "comparator": "EQUALS",
                        "fieldValue": ["value": eventID]
                    ]]
                ],
                "resultsLimit": 200
            ]
            if let marker { body["continuationMarker"] = marker }
            let response = try await service.post("/records/query", body: body)
            let records = response["records"] as? [[String: Any]] ?? []
            items += records.compactMap { item(from: $0, key: key) }
            marker = response["continuationMarker"] as? String
        } while marker != nil
        return items
    }

    private static func item(from record: [String: Any], key: SymmetricKey) -> RemoteTransfer.RemoteItem? {
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
}
