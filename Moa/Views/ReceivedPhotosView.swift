import Photos
import SwiftUI

/// Grid of everything the event has received, read from its Photos album.
struct ReceivedPhotosView: View {
    let assets: [PHAsset]

    @State private var opened: OpenedAsset?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 3)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("받은 사진 \(assets.count)개")
                .font(.headline)

            if assets.isEmpty {
                Text("아직 받은 사진이 없어요. QR을 보여주면 여기에 쌓여요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                        Button {
                            opened = OpenedAsset(index: index)
                        } label: {
                            AssetThumbnail(asset: asset)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(label(for: asset))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(item: $opened) { opened in
            AssetPagerView(assets: assets, startIndex: opened.index)
        }
    }

    private func label(for asset: PHAsset) -> String {
        let when = asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "촬영 시각 모름"
        return asset.mediaType == .video ? "동영상, \(when)" : "사진, \(when)"
    }
}

private struct OpenedAsset: Identifiable {
    let index: Int
    var id: Int { index }
}

struct AssetThumbnail: View {
    let asset: PHAsset

    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaSubtypes.contains(.photoLive) {
                    badge("livephoto")
                } else if asset.mediaType == .video {
                    badge("video.fill")
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task(id: asset.localIdentifier) {
                image = await AssetImageLoader.image(
                    for: asset,
                    targetSize: CGSize(width: 300, height: 300),
                    contentMode: .aspectFill
                )
            }
    }

    private func badge(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.caption)
            .foregroundStyle(.white)
            .shadow(radius: 2)
            .padding(5)
    }
}

/// Full-screen viewer with swipe between photos.
struct AssetPagerView: View {
    let assets: [PHAsset]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var isDeleting = false

    init(assets: [PHAsset], startIndex: Int) {
        self.assets = assets
        self.startIndex = startIndex
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { offset, asset in
                    AssetFullImage(asset: asset)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        Task { await delete() }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(isDeleting)
                    .accessibilityLabel("사진 삭제")
                }
            }
        }
    }

    private var title: String {
        guard assets.indices.contains(index) else { return "" }
        return assets[index].creationDate?.formatted(date: .abbreviated, time: .shortened) ?? ""
    }

    private func delete() async {
        guard assets.indices.contains(index) else { return }
        isDeleting = true
        defer { isDeleting = false }
        // Photos asks the user to confirm; the grid updates through the library observer.
        let deleted = await PhotoLibraryService.delete(assets: [assets[index]])
        if deleted { dismiss() }
    }
}

struct AssetFullImage: View {
    let asset: PHAsset

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .task(id: asset.localIdentifier) {
                let scale = UIScreen.main.scale
                image = await AssetImageLoader.image(
                    for: asset,
                    targetSize: CGSize(width: proxy.size.width * scale, height: proxy.size.height * scale),
                    contentMode: .aspectFit
                )
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
