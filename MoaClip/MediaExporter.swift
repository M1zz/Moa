import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// Original files ready to upload, stored in a private working directory.
struct PreparedMedia {
    struct Resource {
        let kind: ResourceKind
        let url: URL
        let contentType: String
        let size: Int
    }

    let resources: [Resource]
    let capturedAt: Date?
    let location: CaptureLocation?
    let workingDirectory: URL

    func cleanUp() {
        try? FileManager.default.removeItem(at: workingDirectory)
    }
}

enum MediaExportError: LocalizedError {
    case unsupported
    case missingFile

    var errorDescription: String? {
        switch self {
        case .unsupported: return "지원하지 않는 형식이에요."
        case .missingFile: return "파일을 불러오지 못했어요."
        }
    }
}

/// Pulls the *original* representation out of a PHPicker item provider.
/// No PhotoKit here: App Clips can't use it, but PHPicker needs no permission.
enum MediaExporter {
    /// Directory bundle containing the still image and the paired movie of a Live Photo.
    private static let livePhotoBundleType = "com.apple.live-photo-bundle"

    static func export(_ provider: NSItemProvider) async throws -> PreparedMedia {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        do {
            // 1. Live Photo: keep both halves so the host gets a real Live Photo back.
            if provider.hasItemConformingToTypeIdentifier(livePhotoBundleType),
               let media = try? await exportLivePhoto(provider, into: workDir) {
                return media
            }

            // 2. Still image in its original format (usually HEIC, with full EXIF + GPS).
            if let imageType = preferredImageType(for: provider) {
                let url = try await loadFile(from: provider, type: imageType, into: workDir)
                return PreparedMedia(
                    resources: [try resource(.photo, at: url)],
                    capturedAt: imageCaptureDate(url),
                    location: imageLocation(url),
                    workingDirectory: workDir
                )
            }

            // 3. Video.
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                let url = try await loadFile(from: provider, type: UTType.movie.identifier, into: workDir)
                let capturedAt = await videoCreationDate(url)
                let location = await videoLocation(url)
                return PreparedMedia(
                    resources: [try resource(.video, at: url)],
                    capturedAt: capturedAt,
                    location: location,
                    workingDirectory: workDir
                )
            }

            throw MediaExportError.unsupported
        } catch {
            try? FileManager.default.removeItem(at: workDir)
            throw error
        }
    }

    // MARK: Live Photo

    private static func exportLivePhoto(_ provider: NSItemProvider, into directory: URL) async throws -> PreparedMedia {
        let bundleURL = try await loadFile(from: provider, type: livePhotoBundleType, into: directory)
        let contents = try FileManager.default.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil)
        guard let photo = contents.first(where: { conforms($0, to: .image) }),
              let video = contents.first(where: { conforms($0, to: .movie) }) else {
            throw MediaExportError.missingFile
        }
        return PreparedMedia(
            resources: [try resource(.photo, at: photo), try resource(.pairedVideo, at: video)],
            capturedAt: imageCaptureDate(photo),
            location: imageLocation(photo),
            workingDirectory: directory
        )
    }

    // MARK: Loading

    /// The first registered image type is the asset's current (original) representation
    /// because the picker is configured with `preferredAssetRepresentationMode = .current`.
    private static func preferredImageType(for provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first { identifier in
            guard identifier != livePhotoBundleType, let type = UTType(identifier) else { return false }
            return type.conforms(to: .image)
        }
    }

    /// The system deletes the provided file when the callback returns, so copy it out immediately.
    private static func loadFile(from provider: NSItemProvider, type: String, into directory: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: MediaExportError.missingFile)
                    return
                }
                do {
                    let destination = directory.appendingPathComponent(url.lastPathComponent)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func resource(_ kind: ResourceKind, at url: URL) throws -> PreparedMedia.Resource {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return PreparedMedia.Resource(kind: kind, url: url, contentType: contentType, size: size)
    }

    private static func conforms(_ url: URL, to type: UTType) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: type) ?? false
    }

    // MARK: Metadata (sent alongside the files so the host can pin date and place on the asset)

    private static func imageProperties(_ url: URL) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    static func imageCaptureDate(_ url: URL) -> Date? {
        guard let properties = imageProperties(url),
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
            if let date = formatter.date(from: raw + offset) { return date }
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: raw)
    }

    static func imageLocation(_ url: URL) -> CaptureLocation? {
        guard let gps = imageProperties(url)?[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              let longitude = gps[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        let south = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S"
        let west = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W"
        return CaptureLocation(latitude: south ? -latitude : latitude, longitude: west ? -longitude : longitude)
    }

    /// iPhone videos store the place as an ISO 6709 string such as `+37.5665+126.9780+038.000/`.
    static func videoLocation(_ url: URL) async -> CaptureLocation? {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.metadata),
              let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .quickTimeMetadataLocationISO6709).first
                ?? AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierLocation).first,
              let value = try? await item.load(.stringValue) else { return nil }
        let numbers = value.matches(of: /[+-]\d+(?:\.\d+)?/).compactMap { Double($0.output) }
        guard numbers.count >= 2 else { return nil }
        return CaptureLocation(latitude: numbers[0], longitude: numbers[1])
    }

    #if canImport(UIKit)
    /// Small preview kept in memory so the guest can see what they sent. The originals are
    /// deleted right after upload, and an App Clip has little memory, so this stays small.
    static func preview(for media: PreparedMedia, maxPixel: CGFloat = 800) async -> UIImage? {
        if let photo = media.resources.first(where: { $0.kind == .photo })?.url {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ]
            guard let source = CGImageSourceCreateWithURL(photo as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            return UIImage(cgImage: image)
        }

        guard let video = media.resources.first(where: { $0.kind == .video })?.url else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        guard let frame = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: frame)
    }
    #endif

    static func videoCreationDate(_ url: URL) async -> Date? {
        let asset = AVURLAsset(url: url)
        guard let item = try? await asset.load(.creationDate) else { return nil }
        return try? await item.load(.dateValue)
    }
}
