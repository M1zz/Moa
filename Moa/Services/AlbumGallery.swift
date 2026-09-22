import Observation
import Photos
import UIKit

/// The event album, read back out of Photos. Watching the library keeps the grid in step with
/// new arrivals and with anything deleted from the Photos app itself.
@MainActor
@Observable
final class AlbumGallery {
    private(set) var assets: [PHAsset] = []

    private var albumIdentifier: String?
    private var observer: LibraryObserver?

    func start(albumIdentifier: String?) {
        self.albumIdentifier = albumIdentifier
        reload()
        guard observer == nil else { return }
        let observer = LibraryObserver { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        PHPhotoLibrary.shared().register(observer)
        self.observer = observer
    }

    func stop() {
        if let observer {
            PHPhotoLibrary.shared().unregisterChangeObserver(observer)
        }
        observer = nil
    }

    func reload() {
        guard let albumIdentifier,
              let album = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumIdentifier], options: nil).firstObject else {
            assets = []
            return
        }
        let options = PHFetchOptions()
        // Newest first: the photo just received is the one the host wants to see.
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(in: album, options: options)
        assets = (0..<result.count).map { result.object(at: $0) }
    }
}

private final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }
}

enum AssetImageLoader {
    /// One image per call; `highQualityFormat` means the callback fires once.
    static func image(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
