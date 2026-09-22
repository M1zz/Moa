import Foundation

enum ResourceKind: String, Codable, Sendable, CaseIterable {
    /// Still image (HEIC/JPEG/PNG…), or the still half of a Live Photo.
    case photo
    /// The movie half of a Live Photo.
    case pairedVideo
    /// A regular video.
    case video
}

struct ResourceDescriptor: Codable, Hashable, Sendable {
    let kind: ResourceKind
    let filename: String
    let contentType: String
    let size: Int
}

struct CaptureLocation: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Accepts ISO 8601 dates with or without fractional seconds.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: string) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }()
}
