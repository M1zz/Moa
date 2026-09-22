import CoreLocation
import Foundation
import Photos

enum PhotoLibraryError: LocalizedError {
    case accessDenied
    case albumCreationFailed
    case noResources

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "사진 접근 권한이 필요해요. 설정 > 모아 > 사진에서 '전체 접근'을 허용해 주세요."
        case .albumCreationFailed:
            return "사진 앱에 앨범을 만들지 못했어요."
        case .noResources:
            return "가져올 파일이 없어요."
        }
    }
}

/// Everything that touches PhotoKit lives here. The App Clip never links this file.
enum PhotoLibraryService {
    /// Read-write access is required to create the event album.
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static func createAlbum(named title: String) async throws -> String {
        let box = PlaceholderBox()
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            box.placeholder = request.placeholderForCreatedAssetCollection
        }
        guard let identifier = box.placeholder?.localIdentifier else {
            throw PhotoLibraryError.albumCreationFailed
        }
        return identifier
    }

    /// Imports the original files as a single asset, so it looks like one taken on this iPhone:
    /// original format, Live Photo pairing, and its real position in the library timeline
    /// instead of "today". Date and place are also set explicitly because Photos doesn't
    /// always pick them up from video files on import.
    static func importAsset(
        photo: URL?,
        pairedVideo: URL?,
        video: URL?,
        capturedAt: Date?,
        location: CaptureLocation?,
        albumIdentifier: String?
    ) async throws {
        guard photo != nil || video != nil else { throw PhotoLibraryError.noResources }

        let album = albumIdentifier.flatMap {
            PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [$0], options: nil).firstObject
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()

            if let photo {
                request.addResource(with: .photo, fileURL: photo, options: options)
                if let pairedVideo {
                    request.addResource(with: .pairedVideo, fileURL: pairedVideo, options: options)
                }
            } else if let video {
                request.addResource(with: .video, fileURL: video, options: options)
            }

            if let capturedAt {
                request.creationDate = capturedAt
            }
            if let location {
                request.location = CLLocation(latitude: location.latitude, longitude: location.longitude)
            }

            if let album,
               let placeholder = request.placeholderForCreatedAsset,
               let albumRequest = PHAssetCollectionChangeRequest(for: album) {
                albumRequest.addAssets([placeholder] as NSArray)
            }
        }
    }
}

#if DEBUG
extension PhotoLibraryService {
    /// One line about the newest asset of an album, for checking imports from the console.
    static func debugDescribeLatest(albumIdentifier: String?) async -> String {
        guard let albumIdentifier,
              let album = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumIdentifier], options: nil).firstObject else {
            return "album missing"
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(in: album, options: options)
        guard let latest = assets.firstObject else { return "album empty" }
        let resources = PHAssetResource.assetResources(for: latest)
            .map { "\($0.type.rawValue):\($0.originalFilename)" }
            .joined(separator: ",")
        return "count=\(assets.count) created=\(latest.creationDate?.description ?? "nil") "
            + "location=\(latest.location.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" } ?? "nil") "
            + "resources=[\(resources)]"
    }
}
#endif

/// Lets the change block hand a placeholder back out without mutating a captured var.
private final class PlaceholderBox: @unchecked Sendable {
    var placeholder: PHObjectPlaceholder?
}
