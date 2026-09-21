import Foundation
import Network
import Observation

/// Listens on the local network and imports whatever the App Clip sends straight into Photos.
/// No relay, no iCloud API: the photos reach iCloud through the host's own iCloud Photos.
@MainActor
@Observable
final class DirectReceiver {
    enum State: Equatable {
        case idle
        case starting
        case listening(DirectInvitation, interface: String)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var receivedCount = 0
    private(set) var failedCount = 0
    private(set) var lastMessage: String?
    /// Called on the main actor after each item lands in Photos.
    var onImport: (() -> Void)?

    private var listener: NWListener?
    private var albumIdentifier: String?
    private let queue = DispatchQueue(label: "moa.direct.receiver")

    func start(name: String?, albumIdentifier: String?) async {
        guard listener == nil else { return }
        state = .starting

        guard await PhotoLibraryService.requestAccess() else {
            state = .failed(PhotoLibraryError.accessDenied.localizedDescription)
            return
        }
        self.albumIdentifier = albumIdentifier

        guard let address = LocalAddress.current() else {
            state = .failed("Wi-Fi 또는 개인용 핫스팟에 연결되어 있지 않아요.")
            return
        }

        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        let key = Self.makeKey()

        listener.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                switch newState {
                case .ready:
                    guard let port = listener.port?.rawValue else { return }
                    let invitation = DirectInvitation(host: address.ip, port: port, key: key, name: name)
                    self.state = .listening(invitation, interface: address.interface)
                case .failed(let error):
                    self.state = .failed(error.localizedDescription)
                    self.stop()
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection, key: key) }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        if case .listening = state { state = .idle }
    }

    // MARK: Receiving

    private func accept(_ connection: NWConnection, key: String) {
        let queue = queue
        let albumIdentifier = albumIdentifier
        Task {
            defer { connection.cancel() }
            var reply = DirectTransfer.replyFailed
            do {
                try await connection.startAndWaitUntilReady(on: queue, timeout: .seconds(10))
                let watchdog = StallWatchdog(connection: connection)
                defer { watchdog.stop() }
                let item = try await Self.receiveItem(from: connection, key: key, watchdog: watchdog)
                defer { item.cleanUp() }
                try await PhotoLibraryService.importAsset(
                    photo: item.files[.photo],
                    pairedVideo: item.files[.pairedVideo],
                    video: item.files[.video],
                    albumIdentifier: albumIdentifier
                )
                reply = DirectTransfer.replyOK
                receivedCount += 1
                onImport?()
                lastMessage = item.uploader.map { "\($0) 님이 보낸 사진을 넣었어요." } ?? "사진을 하나 넣었어요."
            } catch DirectTransferError.rejected {
                // Wrong key: someone else on the network. Don't count it as a failed photo.
            } catch {
                failedCount += 1
                lastMessage = error.localizedDescription
            }
            // Answers the header on rejection, or reports the import result.
            try? await connection.sendData(Data([reply]))
        }
    }

    private struct ReceivedItem {
        let uploader: String?
        let files: [ResourceKind: URL]
        let directory: URL

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Runs off the main actor so file writes don't stall the UI.
    private nonisolated static func receiveItem(
        from connection: NWConnection,
        key: String,
        watchdog: StallWatchdog
    ) async throws -> ReceivedItem {
        let length = try await connection.receive(exactly: 4)
        guard let headerLength = UInt32(bigEndianData: length).map(Int.init),
              headerLength > 0, headerLength <= DirectTransfer.maxHeaderLength else {
            throw DirectTransferError.invalidHeader
        }
        let header = try JSONCoding.decoder.decode(DirectHeader.self, from: try await connection.receive(exactly: headerLength))
        guard header.key == key else { throw DirectTransferError.rejected }
        guard !header.resources.isEmpty,
              header.resources.allSatisfy({ $0.size > 0 && $0.size <= DirectTransfer.maxResourceSize }) else {
            throw DirectTransferError.invalidHeader
        }
        try await connection.sendData(Data([DirectTransfer.replyOK]))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("direct-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            var files: [ResourceKind: URL] = [:]
            for resource in header.resources {
                // Keep only the extension so Photos recognizes the format; never trust the sender's path.
                let ext = (resource.filename as NSString).pathExtension.filter { $0.isLetter || $0.isNumber }
                var url = directory.appendingPathComponent(UUID().uuidString)
                if !ext.isEmpty { url.appendPathExtension(ext) }

                FileManager.default.createFile(atPath: url.path, contents: nil)
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }

                var remaining = resource.size
                while remaining > 0 {
                    let chunk = try await connection.receiveChunk(maximumLength: min(remaining, DirectTransfer.chunkSize))
                    try handle.write(contentsOf: chunk)
                    remaining -= chunk.count
                    watchdog.touch()
                }
                files[resource.kind] = url
            }
            return ReceivedItem(uploader: header.uploader, files: files, directory: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    // MARK: Helpers

    private static func makeKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// The host's IPv4 address that guests on the same network can reach.
enum LocalAddress {
    struct Address {
        let ip: String
        /// "Wi-Fi" or "개인용 핫스팟"
        let interface: String
    }

    static func current() -> Address? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var found: [String: String] = [:]
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (entry.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            let name = String(cString: entry.ifa_name)
            guard name == "en0" || name.hasPrefix("bridge") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            found[name] = String(cString: host)
        }

        if let ip = found["en0"] { return Address(ip: ip, interface: "Wi-Fi") }
        if let ip = found.first(where: { $0.key.hasPrefix("bridge") })?.value {
            return Address(ip: ip, interface: "개인용 핫스팟")
        }
        return nil
    }
}
