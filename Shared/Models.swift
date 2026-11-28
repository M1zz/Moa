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

/// This install, so a device never downloads back what it already has (`RemoteTransfer.Meta.holders`).
enum DeviceID {
    static var current: String {
        let key = "moaDeviceID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}

/// The name this person shows to the other members. One for the whole app, the App Clip keeps its own.
enum MemberName {
    static let key = "uploaderName"

    static var current: String {
        (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func set(_ name: String) {
        UserDefaults.standard.set(name.trimmingCharacters(in: .whitespacesAndNewlines), forKey: key)
    }
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
