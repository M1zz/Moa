import Foundation
import Network

/// Streams one prepared item to the host's iPhone. See `DirectTransfer` for the wire format.
enum DirectSender {
    private static let queue = DispatchQueue(label: "moa.direct.sender")

    static func send(_ media: PreparedMedia, uploader: String?, to invitation: DirectInvitation) async throws {
        guard let port = NWEndpoint.Port(rawValue: invitation.port) else { throw DirectTransferError.invalidHeader }
        let connection = NWConnection(host: NWEndpoint.Host(invitation.host), port: port, using: .tcp)
        defer { connection.cancel() }

        try await connection.startAndWaitUntilReady(on: queue, timeout: .seconds(15))
        let watchdog = StallWatchdog(connection: connection)
        defer { watchdog.stop() }

        let header = DirectHeader(
            key: invitation.key,
            uploader: uploader,
            resources: media.resources.map {
                ResourceDescriptor(kind: $0.kind, filename: $0.url.lastPathComponent, contentType: $0.contentType, size: $0.size)
            }
        )
        let json = try JSONCoding.encoder.encode(header)
        try await connection.sendData(UInt32(json.count).bigEndianData + json)

        let go = try await connection.receive(exactly: 1)
        guard go.first == DirectTransfer.replyOK else { throw DirectTransferError.rejected }
        watchdog.touch()

        for resource in media.resources {
            let handle = try FileHandle(forReadingFrom: resource.url)
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: DirectTransfer.chunkSize), !chunk.isEmpty {
                try await connection.sendData(chunk)
                watchdog.touch()
            }
        }

        // The host replies only after the item is in Photos.
        let reply = try await connection.receive(exactly: 1)
        guard reply.first == DirectTransfer.replyOK else { throw DirectTransferError.importFailed }
    }
}
