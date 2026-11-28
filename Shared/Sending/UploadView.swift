import PhotosUI
import SwiftUI

/// Name, picker and what was sent. The App Clip and the app's "send photos" sheet both show it
/// once they have the host's invitation.
struct UploadView: View {
    @Environment(UploadModel.self) private var model
    @State private var isPicking = false

    var body: some View {
        @Bindable var model = model

        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.eventName ?? "")
                        .font(.title2.bold())
                    Text("고른 사진과 동영상이 원본 그대로, 찍은 시각 그대로 앨범 멤버 모두의 사진 앱에 들어가요.")
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
                        Text("모두 보냈어요. 고마워요! 멤버들이 앱을 열면 각자의 사진 앱에 들어가요.")
                    }
                }
            }
        }
        .sheet(isPresented: $isPicking) {
            MediaPicker(library: model.picksFromLibrary ? .shared() : nil) { results in
                model.upload(results)
            }
            .ignoresSafeArea()
        }
    }
}
