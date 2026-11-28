import AVFoundation
import SwiftUI
import VisionKit

/// 다른 사람의 공유 앨범에 들어가는 곳. 그 사람 화면의 QR 을 찍거나 받은 링크를 붙여 넣으면 끝이다 —
/// 애플 공유 앨범처럼 누가 나를 한 명씩 추가해 줄 필요가 없다. 링크를 가진 사람이 멤버다.
struct JoinAlbumView: View {
    /// 들어간 앨범을 연다.
    var onJoined: (String) -> Void

    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var invitation: DirectInvitation?
    @State private var wrongCode = false
    @State private var name = MemberName.current
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let invitation {
                    confirm(invitation)
                } else {
                    VStack(spacing: 16) {
                        ScanInvitationView(wrongCode: wrongCode) { read($0) }
                        PasteButton(payloadType: URL.self) { urls in
                            if let url = urls.first { Task { @MainActor in read(url) } }
                        }
                        .labelStyle(.titleAndIcon)
                    }
                    .padding(.bottom)
                }
            }
            .navigationTitle("앨범 참여")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Label("닫기", systemImage: "xmark") }
                }
            }
        }
        .interactiveDismissDisabled(isJoining)
    }

    private func read(_ url: URL) {
        guard let found = DirectInvitation(url: url) else {
            wrongCode = true
            return
        }
        // 이미 있는 앨범이면 바로 그 앨범으로
        if store.event(id: found.eventID) != nil {
            dismiss()
            onJoined(found.eventID)
            return
        }
        invitation = found
    }

    private func confirm(_ invitation: DirectInvitation) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(invitation.name ?? String(localized: "공유 앨범"))
                        .font(.title2.bold())
                    Text("참여하면 멤버들이 올린 사진이 원본 그대로 내 사진 앱에도 들어와요. 내가 올린 사진도 모두에게 가요.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section {
                TextField("이름", text: $name)
                    .textContentType(.name)
            } header: {
                Text("멤버들에게 보일 이름")
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            Section {
                Button {
                    Task { await join(invitation) }
                } label: {
                    if isJoining {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("참여하기", systemImage: "person.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isJoining)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    private func join(_ invitation: DirectInvitation) async {
        isJoining = true
        errorMessage = nil
        defer { isJoining = false }
        MemberName.set(name)
        do {
            let event = try await store.join(invitation)
            dismiss()
            onJoined(event.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 카메라로 앨범의 QR 을 읽는다. 기기 안에서 읽으니 네트워크가 필요 없다.
private struct ScanInvitationView: View {
    let wrongCode: Bool
    let onScan: (URL) -> Void
    @State private var cameraAllowed: Bool?

    var body: some View {
        VStack(spacing: 16) {
            if !DataScannerViewController.isSupported {
                ContentUnavailableView("이 기기에서는 QR을 찍을 수 없어요", systemImage: "qrcode.viewfinder")
            } else if cameraAllowed == false {
                ContentUnavailableView {
                    Label("카메라를 쓸 수 없어요", systemImage: "camera")
                } description: {
                    Text("설정에서 보태줘의 카메라 접근을 허용해 주세요.")
                } actions: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("설정 열기", destination: url)
                    }
                }
            } else if cameraAllowed == true {
                QRScanner { text in
                    if let url = URL(string: text) { onScan(url) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityLabel("QR 스캐너")

                Text(wrongCode ? "보태줘 앨범의 QR이나 링크가 아니에요. 앨범 화면에 뜬 QR을 찍어 주세요."
                               : "멤버의 앨범 화면에 뜬 QR을 찍거나, 받은 링크를 붙여 넣으세요.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .task {
            cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void

        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .barcode(barcode) in addedItems {
                if let text = barcode.payloadStringValue { onFound(text) }
            }
        }
    }
}
