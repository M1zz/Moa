import SwiftUI
import LeeoKit

/// While this screen is open, guests on the same Wi-Fi send straight to this iPhone.
struct EventDetailView: View {
    @Environment(EventStore.self) private var store
    let eventID: String

    @State private var receiver = DirectReceiver()
    @State private var gallery = AlbumGallery()
    @State private var remoteMessage: String?
    @State private var isCheckingRemote = false
    /// 아이폰 듀오를 펴면 받은 사진은 옆 판(`FoldEventPhotos`)에 서므로 여기서는 그리지 않는다.
    @Environment(\.foldLayout) private var fold
    @Environment(\.isWidePadPanes) private var widePad
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if let event = store.event(id: eventID) {
            content(for: event)
                .task(id: event.id) {
                    receiver.onImport = { [store] assetID, uploader in
                        store.recordImport(eventID: eventID, assetID: assetID, uploader: uploader)
                    }
                    gallery.start(albumIdentifier: event.albumIdentifier)
                    await startReceiving(event)
                    // 앱을 닫은 뒤 멀리서 온 사진을 가져와 알려 줄 수 있게 (→ RemoteRefresh)
                    await RemoteRefresh.askForNotifications()
                    await pollRemote(event: event)
                }
                .onChange(of: receiver.state) { _, state in
                    if case let .listening(invitation, _) = state {
                        store.rememberPort(invitation.port, for: eventID)
                    }
                }
                // 뒤로 갔다 오면 iOS 가 듣기를 끊어 둘 수 있다. 같은 키 · 포트로 다시 열어 QR 이 그대로다.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, case .failed = receiver.state else { return }
                    receiver.stop()
                    Task { await startReceiving(event) }
                }
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
                .onDisappear {
                    receiver.stop()
                    gallery.stop()
                    UIApplication.shared.isIdleTimerDisabled = false
                }
        } else {
            ContentUnavailableView("이벤트를 찾을 수 없어요", systemImage: "questionmark.circle")
        }
    }

    private func startReceiving(_ event: HostedEvent) async {
        guard let key = store.inviteKey(for: event.id) else { return }
        await receiver.start(
            name: event.name,
            eventID: event.id,
            albumIdentifier: event.albumIdentifier,
            key: key,
            preferredPort: event.invitePort
        )
    }

    private func content(for event: HostedEvent) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 24) {
                switch receiver.state {
                case .idle, .starting:
                    ProgressView("받을 준비를 하는 중…")
                        .padding(.top, 80)
                case .failed(let message):
                    ContentUnavailableView(
                        "받을 준비를 못 했어요",
                        systemImage: "wifi.exclamationmark",
                        description: Text(message)
                    )
                case let .listening(invitation, interface):
                    listening(event: event, invitation: invitation, interface: interface)
                }

                if !fold.isUnfolded {
                    Divider()

                    ReceivedPhotosView(assets: gallery.assets, uploaders: event.uploaders ?? [:])
                        .id("photos")
                }
            }
            .padding()
        }
        #if DEBUG
        // `-moa-scroll-to-photos`: shows the received grid, for the App Store screenshot.
        .onChange(of: gallery.assets.count) {
            guard ProcessInfo.processInfo.arguments.contains("-moa-scroll-to-photos") else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                proxy.scrollTo("photos", anchor: .top)
            }
        }
        #endif
        }
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func listening(event: HostedEvent, invitation: DirectInvitation, interface: String) -> some View {
        let qrImage = QRCodeRenderer.image(for: invitation.url.absoluteString)

        QRCodeView(image: qrImage)
            // 넓은 아이패드는 행사장 안내판 — 멀리서도 찍히게 크게
            .frame(maxWidth: widePad ? 440 : 280)

        VStack(spacing: 4) {
            Text(UIDevice.current.userInterfaceIdiom == .pad
                 ? "같은 \(interface)에서 QR을 찍으면 이 iPad로 바로 와요"
                 : "같은 \(interface)에서 QR을 찍으면 이 iPhone으로 바로 와요")
                .font(.headline)
                .multilineTextAlignment(.center)
        }

        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("사진 앱에 넣은 항목", value: String(localized: "\(event.receivedCount)개"))
                if receiver.failedCount > 0 {
                    LabeledContent("이번에 실패", value: String(localized: "\(receiver.failedCount)개"))
                }
                if let lastMessage = receiver.lastMessage {
                    Text(lastMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if RemoteInbox.isConfigured {
                    Divider()
                    LabeledContent("멀리서 보낸 사진") {
                        if isCheckingRemote {
                            ProgressView()
                        } else {
                            Text(remoteMessage ?? String(localized: "확인했어요"))
                        }
                    }
                }
            }
        }

        ShareLink(item: invitation.url) {
            Label("초대 링크 보내기", systemImage: "link")
        }
        .buttonStyle(.bordered)

        Text("이 화면이 켜져 있으면 같은 Wi-Fi에서 바로 받아요. 화면은 자동으로 꺼지지 않아요.\n이 QR은 이벤트 내내 그대로예요. 앱을 닫아 두면 멀리서 보낸 사진으로 받아 알려 드려요.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    /// Guests who weren't on the same Wi-Fi leave their photos in iCloud. Check on open and
    /// every 30 seconds after that, so they land in the same album as the local ones.
    private func pollRemote(event: HostedEvent) async {
        guard RemoteInbox.isConfigured else { return }
        while !Task.isCancelled {
            isCheckingRemote = true
            do {
                // nil: another pass (app launch, background refresh) is already on it.
                if let result = try await store.pullRemote(eventID: event.id) {
                    if !result.imported.isEmpty {
                        let count = result.imported.count
                        remoteMessage = result.lastUploader.map { String(localized: "\($0) 님 외 \(count)개 가져왔어요") }
                            ?? String(localized: "\(count)개 가져왔어요")
                        gallery.reload()
                    } else if result.failed > 0 {
                        remoteMessage = String(localized: "\(result.failed)개 실패")
                    } else if remoteMessage == nil {
                        remoteMessage = String(localized: "없어요")
                    }
                }
            } catch {
                remoteMessage = String(localized: "확인 실패")
                #if DEBUG
                NSLog("[moa] remote poll failed: \(error)")
                #endif
            }
            isCheckingRemote = false
            try? await Task.sleep(for: .seconds(30))
        }
    }
}
