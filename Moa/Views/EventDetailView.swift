import SwiftUI

/// While this screen is open, guests on the same Wi-Fi send straight to this iPhone.
struct EventDetailView: View {
    @Environment(EventStore.self) private var store
    let eventID: String

    @State private var receiver = DirectReceiver()
    @State private var gallery = AlbumGallery()

    var body: some View {
        if let event = store.event(id: eventID) {
            content(for: event)
                .task(id: event.id) {
                    receiver.onImport = { [store] in store.recordImport(eventID: eventID) }
                    gallery.start(albumIdentifier: event.albumIdentifier)
                    await receiver.start(name: event.name, albumIdentifier: event.albumIdentifier)
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

    private func content(for event: HostedEvent) -> some View {
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

                Divider()

                ReceivedPhotosView(assets: gallery.assets)
            }
            .padding()
        }
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func listening(event: HostedEvent, invitation: DirectInvitation, interface: String) -> some View {
        let qrImage = QRCodeRenderer.image(for: invitation.url.absoluteString)

        QRCodeView(image: qrImage)
            .frame(maxWidth: 280)

        VStack(spacing: 4) {
            Text("같은 \(interface)에서 QR을 찍으면 이 iPhone으로 바로 와요")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("\(invitation.host):\(String(invitation.port))")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("사진 앱에 넣은 항목", value: "\(event.receivedCount)개")
                if receiver.failedCount > 0 {
                    LabeledContent("이번에 실패", value: "\(receiver.failedCount)개")
                }
                if let lastMessage = receiver.lastMessage {
                    Text(lastMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }

        ShareLink(item: invitation.url) {
            Label("테스트용 링크 공유", systemImage: "link")
        }
        .buttonStyle(.bordered)

        Text("이 화면이 켜져 있는 동안만 받아요. 화면은 자동으로 꺼지지 않아요.\n화면을 다시 열면 QR이 바뀌어요.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
