import SwiftUI

struct ClipRootView: View {
    @Environment(UploadModel.self) private var model
    @State private var isPicking = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .waitingForInvocation(let linkHadNoEvent):
                    ScanGuideView(linkHadNoEvent: linkHadNoEvent)
                case .ready:
                    UploadView(isPicking: $isPicking)
                }
            }
            .navigationTitle("보태줘")
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
                    Text(model.eventName ?? "")
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
                    SentPhotosView(items: model.items)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("\(model.doneCount)/\(model.items.count) 보냄")
                } footer: {
                    if model.isUploading {
                        Text("다 보낼 때까지 이 화면을 켜 두세요.")
                    } else if model.doneCount == model.items.count {
                        if model.sentRemotelyCount > 0 {
                            Text("모두 보냈어요. 고마워요! 가까이 있지 않아서 iCloud로 전달했고, 호스트가 앱을 열면 사진 앱에 들어가요.")
                        } else {
                            Text("모두 보냈어요. 고마워요!")
                        }
                    }
                }
            }
        }
    }
}

/// Shown until the clip has a host to send to. Explains where the QR comes from rather than
/// reporting an error, because a guest who opened the clip some other way only needs to scan.
private struct ScanGuideView: View {
    let linkHadNoEvent: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("호스트의 QR을 찍어 주세요")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("사진을 받을 사람의 iPhone에 뜬 QR을 카메라로 찍으면, 여기서 바로 사진을 보낼 수 있어요.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 16) {
                    step(1, "받는 사람이 보태줘 앱에서 이벤트를 열면 QR이 나와요.")
                    step(2, "이 iPhone의 카메라 앱으로 그 QR을 찍어요.")
                    step(3, "사진을 고르면 원본 그대로 받는 사람의 사진 앱에 들어가요.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if linkHadNoEvent {
                    Label("이 링크에는 이벤트 정보가 없어요. 받는 사람 화면에 지금 떠 있는 QR을 찍어 주세요.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number, format: .number)
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
