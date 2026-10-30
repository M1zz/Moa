import SwiftUI

/// 아이폰 듀오를 폈을 때 옆 판: 지금 보는 이벤트(목록에 있으면 맨 위 이벤트)에 받은 사진.
///
/// 왼쪽(세로면 아래)에서 QR을 보여 주는 동안 받은 사진이 이쪽에 바로 쌓인다.
/// 이벤트 화면의 격자(`ReceivedPhotosView`)를 그대로 쓰고, 사진 보관함은 따로 지켜본다.
struct FoldEventPhotos: View {
    @Environment(EventStore.self) private var store
    let eventID: String?

    @State private var gallery = AlbumGallery()

    private var event: HostedEvent? { eventID.flatMap(store.event(id:)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                ReceivedPhotosView(assets: gallery.assets, uploaders: event?.uploaders ?? [:])
                    .padding()
            }
            .navigationTitle(event?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: event?.albumIdentifier) { gallery.start(albumIdentifier: event?.albumIdentifier) }
        .onDisappear { gallery.stop() }
    }
}
