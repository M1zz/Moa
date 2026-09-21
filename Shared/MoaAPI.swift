import Foundation

enum MoaAPIError: LocalizedError {
    case invalidResponse
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "서버 응답을 이해하지 못했어요."
        case let .http(status, message):
            return "\(message) (\(status))"
        }
    }
}

/// Thin client for the relay Worker (see worker/src/index.js).
struct MoaAPI: Sendable {
    let baseURL: URL

    init(baseURL: URL = AppConfig.baseURL) {
        self.baseURL = baseURL
    }

    private var session: URLSession { .shared }

    // MARK: Events

    func createEvent(name: String, days: Int) async throws -> CreateEventResponse {
        var request = makeRequest("/api/events", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONCoding.encoder.encode(CreateEventRequest(name: name, days: days))
        return try await send(request)
    }

    func fetchEvent(id: String) async throws -> EventInfo {
        try await send(makeRequest("/api/events/\(id)"))
    }

    // MARK: Guest (App Clip)

    func uploadResource(eventID: String, itemID: String, kind: ResourceKind, fileURL: URL, contentType: String) async throws {
        var request = makeRequest("/api/events/\(eventID)/items/\(itemID)/\(kind.rawValue)", method: "PUT")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: request, fromFile: fileURL)
        try validate(response, data)
    }

    func completeItem(eventID: String, manifest: ItemManifest) async throws {
        var request = makeRequest("/api/events/\(eventID)/items/\(manifest.itemID)/complete", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONCoding.encoder.encode(manifest)
        let (data, response) = try await session.data(for: request)
        try validate(response, data)
    }

    // MARK: Host

    func listItems(eventID: String, hostToken: String) async throws -> [ItemManifest] {
        let response: ItemListResponse = try await send(makeRequest("/api/events/\(eventID)/items", token: hostToken))
        return response.items
    }

    /// Downloads one resource to a temporary file that keeps the original extension,
    /// so Photos can recognize the format. The caller owns (and deletes) the file.
    func downloadResource(eventID: String, itemID: String, resource: ResourceDescriptor, hostToken: String) async throws -> URL {
        let request = makeRequest("/api/events/\(eventID)/items/\(itemID)/\(resource.kind.rawValue)", token: hostToken)
        let (tempURL, response) = try await session.download(for: request)
        let ext = (resource.filename as NSString).pathExtension
        var destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        if !ext.isEmpty { destination.appendPathExtension(ext) }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        do {
            try validate(response, nil)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }

    func deleteItem(eventID: String, itemID: String, hostToken: String) async throws {
        let request = makeRequest("/api/events/\(eventID)/items/\(itemID)", method: "DELETE", token: hostToken)
        let (data, response) = try await session.data(for: request)
        try validate(response, data)
    }

    // MARK: Plumbing

    private func makeRequest(_ path: String, method: String = "GET", token: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)!.absoluteURL)
        request.httpMethod = method
        request.timeoutInterval = 120
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        try validate(response, data)
        return try JSONCoding.decoder.decode(T.self, from: data)
    }

    private func validate(_ response: URLResponse, _ data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { throw MoaAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = data.flatMap { try? JSONDecoder().decode(ServerError.self, from: $0).error }
            let message = serverMessage ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw MoaAPIError.http(status: http.statusCode, message: message)
        }
    }

    private struct ServerError: Decodable {
        let error: String
    }
}
