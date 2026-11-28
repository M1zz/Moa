import SwiftUI

struct CreateEventView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var memberName = MemberName.current
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("예: 우리 가족, 제주 여행", text: $name)
                        .submitLabel(.done)
                } header: {
                    Text("앨범 이름")
                } footer: {
                    Text("사진 앱에 같은 이름의 앨범이 만들어져요. 멤버가 참여하면 그 사람의 사진 앱에도 생겨요.")
                }

                Section {
                    TextField("이름", text: $memberName)
                        .textContentType(.name)
                } header: {
                    Text("멤버들에게 보일 이름")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("새 공유 앨범")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSubmitting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Label("취소", systemImage: "xmark") }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button {
                            Task { await submit() }
                        } label: {
                            Label("만들기", systemImage: "checkmark")
                        }
                        .disabled(trimmedName.isEmpty)
                    }
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        MemberName.set(memberName)
        do {
            _ = try await store.createEvent(name: trimmedName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
