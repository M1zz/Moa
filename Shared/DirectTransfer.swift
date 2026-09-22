import Foundation
import Network

/// Sends media straight from the App Clip to the host's iPhone over the local network,
/// with no relay in between. One TCP connection carries one item:
///
///     guest → [UInt32 big-endian header length][header JSON]
///     host  → 1 byte: 1 = go ahead, 0 = rejected (wrong key, bad header)
///     guest → [resource 1 bytes][resource 2 bytes]…
///     host  → 1 byte: 1 = imported into Photos, 0 = failed
///
/// Answering after the header keeps a rejected guest from pushing megabytes nobody reads.
/// App Clips can't use Bonjour, so the QR carries the host's address instead of a service name.
enum DirectTransfer {
    static let maxHeaderLength = 64 * 1024
    /// Guards against a stray connection claiming gigabytes of the host's disk.
    static let maxResourceSize = 4 << 30
    static let chunkSize = 1 << 20
    static let replyOK: UInt8 = 1
    static let replyFailed: UInt8 = 0
    /// A connection that moves no bytes for this long is cut, so neither side waits forever
    /// when the other walks away (host closes the screen, guest locks the phone).
    static let stallLimit: Duration = .seconds(30)
}

struct DirectHeader: Codable, Sendable {
    let key: String
    let uploader: String?
    /// Read from the files by the App Clip. The host sets them on the asset explicitly so it lands
    /// at its real place in the timeline even when Photos can't read the file's own metadata.
    let capturedAt: Date?
    let location: CaptureLocation?
    let resources: [ResourceDescriptor]
}

enum DirectTransferError: LocalizedError {
    case timedOut(underlying: Error?)
    case connectionClosed
    case rejected
    case importFailed
    case invalidHeader

    var errorDescription: String? {
        switch self {
        case .timedOut(let underlying):
            let reason = underlying.map { " (\($0.localizedDescription))" } ?? ""
            return "호스트 iPhone에 연결하지 못했어요. 같은 Wi-Fi인지, 로컬 네트워크 권한을 허용했는지 확인해 주세요.\(reason)"
        case .connectionClosed:
            return "보내는 도중 연결이 끊겼어요."
        case .rejected:
            return "호스트가 받지 않았어요. QR을 다시 찍어 주세요."
        case .importFailed:
            return "호스트 iPhone이 사진을 저장하지 못했어요."
        case .invalidHeader:
            return "잘못된 요청이에요."
        }
    }
}

/// What the host's QR encodes: the App Clip invocation URL (`AppConfig.directInvitationBaseURL`)
/// with the host's address and a one-time key as query items. Nothing goes through the domain;
/// it only tells iOS which App Clip to open.
struct DirectInvitation: Hashable, Sendable {
    let host: String
    let port: UInt16
    let key: String
    let name: String?
    /// Identifies the event in the remote (iCloud) mailbox, and stays the same across screens.
    let eventID: String

    var url: URL {
        var components = URLComponents(url: AppConfig.directInvitationBaseURL, resolvingAgainstBaseURL: false)!
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "host", value: host))
        items.append(URLQueryItem(name: "port", value: String(port)))
        items.append(URLQueryItem(name: "key", value: key))
        items.append(URLQueryItem(name: "eid", value: eventID))
        if let name { items.append(URLQueryItem(name: "name", value: name)) }
        components.queryItems = items
        return components.url!
    }

    init(host: String, port: UInt16, key: String, name: String?, eventID: String) {
        self.host = host
        self.port = port
        self.key = key
        self.name = name
        self.eventID = eventID
    }

    init?(url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let host = value("host"), !host.isEmpty,
              let port = value("port").flatMap(UInt16.init),
              let key = value("key"), !key.isEmpty,
              let eventID = value("eid"), !eventID.isEmpty else { return nil }
        self.init(host: host, port: port, key: key, name: value("name"), eventID: eventID)
    }
}

// MARK: - async/await over NWConnection

extension NWConnection {
    /// Starts the connection and waits for `.ready`. A connection that can't reach the peer
    /// sits in `.waiting` (e.g. while the Local Network prompt is up), so give up after `timeout`.
    func startAndWaitUntilReady(on queue: DispatchQueue, timeout: Duration) async throws {
        let once = ResumeOnce()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            once.set(continuation)
            stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.resume(with: .success(()))
                case .failed(let error):
                    once.resume(with: .failure(error))
                case .waiting(.posix(.ECONNREFUSED)):
                    // Reachable but nobody is listening: the host closed the screen. No point waiting.
                    once.resume(with: .failure(DirectTransferError.timedOut(underlying: NWError.posix(.ECONNREFUSED))))
                case .waiting(let error):
                    once.lastError = error
                case .cancelled:
                    once.resume(with: .failure(DirectTransferError.connectionClosed))
                default:
                    break
                }
            }
            start(queue: queue)
            Task {
                try? await Task.sleep(for: timeout)
                once.resume(with: .failure(DirectTransferError.timedOut(underlying: once.lastError)))
            }
        }
    }

    func sendData(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Receives up to `maximumLength` bytes, at least one.
    func receiveChunk(maximumLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: DirectTransferError.connectionClosed)
                }
            }
        }
    }

    func receive(exactly length: Int) async throws -> Data {
        var buffer = Data()
        while buffer.count < length {
            buffer.append(try await receiveChunk(maximumLength: length - buffer.count))
        }
        return buffer
    }
}

/// Cancels the connection when no progress is reported for `limit`. Cancelling makes every
/// pending send/receive fail, which unwinds whichever side was stuck.
final class StallWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var lastProgress = ContinuousClock.now
    private var task: Task<Void, Never>?

    init(connection: NWConnection, limit: Duration = DirectTransfer.stallLimit) {
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                if ContinuousClock.now - self.lock.withLock({ self.lastProgress }) > limit {
                    connection.cancel()
                    return
                }
            }
        }
    }

    func touch() {
        lock.withLock { lastProgress = .now }
    }

    func stop() {
        task?.cancel()
    }
}

extension UInt32 {
    var bigEndianData: Data { withUnsafeBytes(of: bigEndian) { Data($0) } }

    init?(bigEndianData data: Data) {
        guard data.count == 4 else { return nil }
        self = data.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}

/// Resumes a continuation exactly once, whichever of the state handler or the timeout gets there first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var _lastError: Error?

    var lastError: Error? {
        get { lock.withLock { _lastError } }
        set { lock.withLock { _lastError = newValue } }
    }

    func set(_ continuation: CheckedContinuation<Void, Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func resume(with result: Result<Void, Error>) {
        let pending: CheckedContinuation<Void, Error>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }
}
