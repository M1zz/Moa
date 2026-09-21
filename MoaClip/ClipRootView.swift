import SwiftUI

struct ClipRootView: View {
    @Environment(UploadModel.self) private var model
    @State private var isPicking = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .waitingForInvocation:
                    ContentUnavailableView(
                        "QR 코드를 스캔해 주세요",
                        systemImage: "qrcode.viewfinder",
                        description: Text("행사장에 있는 QR 코드를 카메라로 스캔하면 사진을 보낼 수 있어요.")
                    )
                case .loading:
                    ProgressView("이벤트 정보를 불러오는 중…")
                case .failed(let message):
                    ContentUnavailableView(
                        "열 수 없어요",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                case .ready:
                    UploadView(isPicking: $isPicking)
                }
            }
            .navigationTitle("모아")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $isPicking) {
            MediaPicker { results in
                model.upload(results)
            }
            .ignoresSafeArea()
        }
    }
}

private struct UploadView: View {
    @Environment(UploadModel.self) private var model
    @Binding var isPicking: Bool

    var body: some View {
        @Bindable var model = model

        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.event?.name ?? "")
                        .font(.title2.bold())
                    Text("고른 사진과 동영상이 원본 그대로, 찍은 시각 그대로 호스트의 사진 앱에 들어가요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                TextField("이름 (선택)", text: $model.uploaderName)
                    .textContentType(.name)
            } header: {
                Text("보내는 사람")
            }

            Section {
                Button {
                    isPicking = true
                } label: {
                    Label("사진·동영상 고르기", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if !model.items.isEmpty {
                Section {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        UploadRow(index: index + 1, status: item.status)
                    }
                } header: {
                    Text("\(model.doneCount)/\(model.items.count) 보냄")
                } footer: {
                    if model.isUploading {
                        Text("다 보낼 때까지 이 화면을 켜 두세요.")
                    } else if model.doneCount == model.items.count {
                        Text("모두 보냈어요. 고마워요!")
                    }
                }
            }
        }
    }
}

private struct UploadRow: View {
    let index: Int
    let status: UploadModel.UploadItem.Status

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("항목 \(index)")
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .waiting:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .preparing, .uploading:
            ProgressView()
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var label: String {
        switch status {
        case .waiting: return "대기 중"
        case .preparing: return "원본 준비 중"
        case .uploading: return "보내는 중"
        case .done: return "완료"
        case .failed(let message): return "실패: \(message)"
        }
    }
}
