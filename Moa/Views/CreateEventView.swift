import SwiftUI

struct CreateEventView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("예: 9월 멘토링 세션", text: $name)
                        .submitLabel(.done)
                } header: {
                    Text("이벤트 이름")
                } footer: {
                    Text("사진 앱에 같은 이름의 앨범이 만들어져요.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("새 이벤트")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSubmitting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("만들기") {
                            Task { await submit() }
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
        do {
            _ = try await store.createEvent(name: trimmedName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
