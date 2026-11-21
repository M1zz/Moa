import AVFoundation
import SwiftUI
import VisionKit

/// 앱이 있는 게스트가 사진을 보내는 곳. 호스트의 QR 을 앱에서 찍으면 App Clip 과 같은 화면이 나오고,
/// 근처의 호스트를 직접 찾아 보낸다 — 공유기 · 인터넷이 없어도 된다 (→ NearbyTransfer).
struct SendPhotosView: View {
    @State private var model = UploadModel(searchesNearby: true)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .ready:
                    UploadView()
                case .waitingForInvocation(let wrongCode):
                    ScanInvitationView(wrongCode: wrongCode) { url in model.handle(url: url) }
                }
            }
            .environment(model)
            .navigationTitle("사진 보내기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Label("닫기", systemImage: "xmark") }
                }
            }
        }
        // 보내는 중에 닫히지 않게
        .interactiveDismissDisabled(model.isUploading)
        .onDisappear { model.stop() }
    }
}

/// 카메라로 호스트의 QR 을 읽는다. 기기 안에서 읽으니 네트워크가 필요 없다.
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

                Text(wrongCode ? "보태줘 QR이 아니에요. 받는 사람의 이벤트 화면에 뜬 QR을 찍어 주세요."
                               : "받는 사람의 이벤트 화면에 뜬 QR을 찍어 주세요.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("가까이 있으면 인터넷 없이도 바로 보내요. 두 기기 모두 Wi-Fi만 켜 두세요.")
                    .foregroundStyle(.secondary)
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
