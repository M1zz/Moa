import SwiftUI
import LeeoKit

/// One shared album: who is in it, how to bring more people in, and every member's photos.
///
/// Anyone who scans the QR or opens the link is a member, so there is nobody to add by hand.
/// On the iPhone that made the album, this screen also receives straight from guests nearby.
struct EventDetailView: View {
    @Environment(EventStore.self) private var store
    let eventID: String

    @State private var receiver = DirectReceiver()
    @State private var gallery = AlbumGallery()
    @State private var remoteMessage: String?
    @State private var isCheckingRemote = false
    @State private var isAdding = false
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
                    receiver.onShared = { [store] record in
                        store.markSynced(record, eventID: eventID)
                    }
                    gallery.start(albumIdentifier: event.albumIdentifier)
                    if !event.isJoined { await startReceiving(event) }
                    // 앱을 닫은 뒤 멤버들이 보탠 사진을 가져와 알려 줄 수 있게 (→ RemoteRefresh)
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
                .onAppear { UIApplication.shared.isIdleTimerDisabled = !event.isJoined }
                .onDisappear {
                    receiver.stop()
                    gallery.stop()
                    UIApplication.shared.isIdleTimerDisabled = false
                }
                .sheet(isPresented: $isAdding) {
                    AddPhotosSheet(event: event, invitation: invitation(for: event))
                }
        } else {
            ContentUnavailableView("앨범을 찾을 수 없어요", systemImage: "questionmark.circle")
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

    /// The album's link. On the iPhone that made it, the receiver's current address; until it
    /// is listening, one without a reachable address still works through the feed.
    private func invitation(for event: HostedEvent) -> DirectInvitation {
        if let joined = event.joinedInvitation { return joined }
        if case let .listening(invitation, _) = receiver.state { return invitation }
        return DirectInvitation(host: "-", port: event.invitePort ?? 0,
                                key: store.inviteKey(for: event.id) ?? "", name: event.name, eventID: event.id)
    }

    private func content(for event: HostedEvent) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 24) {
                invite(event: event)

                Button {
                    isAdding = true
                } label: {
                    Label("사진 보태기", systemImage: "plus.square.on.square")
                        .font(.headline)
                        .frame(maxWidth: 360)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                MembersView(names: members(of: event))

                status(event: event)

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

    /// Everyone the feed has named, plus whoever sent straight to this iPhone.
    private func members(of event: HostedEvent) -> [String] {
        var names = event.members ?? []
        for name in Set((event.uploaders ?? [:]).values).sorted() where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    // MARK: Invite

    @ViewBuilder
    private func invite(event: HostedEvent) -> some View {
        if event.isJoined {
            qrCard(invitation(for: event))
        } else {
            switch receiver.state {
            case .idle, .starting:
                ProgressView("받을 준비를 하는 중…")
                    .padding(.vertical, 60)
            case .failed(let message):
                ContentUnavailableView(
                    "받을 준비를 못 했어요",
                    systemImage: "wifi.exclamationmark",
                    description: Text(message)
                )
            case let .listening(invitation, interface):
                qrCard(invitation)
                if let interface {
                    Text(UIDevice.current.userInterfaceIdiom == .pad
                         ? "같은 \(interface)에서 QR을 찍으면 이 iPad로 바로 와요"
                         : "같은 \(interface)에서 QR을 찍으면 이 iPhone으로 바로 와요")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func qrCard(_ invitation: DirectInvitation) -> some View {
        VStack(spacing: 12) {
            QRCodeView(image: QRCodeRenderer.image(for: invitation.url.absoluteString))
                // 넓은 아이패드는 행사장 안내판 — 멀리서도 찍히게 크게
                .frame(maxWidth: widePad ? 440 : 240)
            Text("이 QR을 찍거나 링크를 연 사람은 바로 멤버가 돼요")
                .font(.headline)
            Text("한 명씩 추가할 필요가 없어요. 멤버 누구나 다른 사람을 초대할 수 있어요.")
                .foregroundStyle(.secondary)
            ShareLink(item: invitation.url,
                      subject: Text(invitation.name ?? ""),
                      message: Text("보태줘 공유 앨범에 초대해요. 링크를 열면 바로 함께 사진을 모을 수 있어요.")) {
                Label("초대 링크 보내기", systemImage: "link")
            }
            .buttonStyle(.bordered)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: Status

    private func status(event: HostedEvent) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("사진 앱에 넣은 항목", value: String(localized: "\(event.receivedCount)개"))
                if receiver.failedCount > 0 {
                    LabeledContent("이번에 실패", value: String(localized: "\(receiver.failedCount)개"))
                }
                if let lastMessage = receiver.lastMessage {
                    Text(lastMessage)
                        .foregroundStyle(.secondary)
                }
                if RemoteInbox.isConfigured {
                    Divider()
                    LabeledContent("멤버들이 보탠 사진") {
                        if isCheckingRemote {
                            ProgressView()
                        } else {
                            Text(remoteMessage ?? String(localized: "확인했어요"))
                        }
                    }
                }
            }
        }
    }

    /// The other members' photos come through the feed. Check on open and every 30 seconds
    /// after that, so they land in the same album as everything else.
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

/// Who is in the album, by the names they chose.
private struct MembersView: View {
    let names: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("멤버 \(names.count)명", systemImage: "person.2")
                .font(.headline)
            Text(names.isEmpty
                 ? String(localized: "아직 이름을 알린 멤버가 없어요. 링크를 보내 초대해 보세요.")
                 : names.joined(separator: ", "))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Adding my own photos: they go into the album's feed for every member, and into my album
/// here without a second copy.
private struct AddPhotosSheet: View {
    let event: HostedEvent
    let invitation: DirectInvitation

    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var model: UploadModel

    init(event: HostedEvent, invitation: DirectInvitation) {
        self.event = event
        self.invitation = invitation
        _model = State(initialValue: UploadModel(route: .member(isOwner: !event.isJoined)))
    }

    var body: some View {
        NavigationStack {
            UploadView()
                .environment(model)
                .navigationTitle("사진 보태기")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Label("닫기", systemImage: "xmark") }
                    }
                }
        }
        // 보내는 중에 닫히지 않게
        .interactiveDismissDisabled(model.isUploading)
        .task {
            model.onSent = { [store, eventID = event.id] assetIdentifier, record in
                Task { await store.recordOwnAdd(eventID: eventID, assetIdentifier: assetIdentifier, record: record) }
            }
            model.handle(url: invitation.url)
        }
        .onDisappear { model.stop() }
    }
}
