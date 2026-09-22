import SwiftUI

/// What this guest has sent, with how each one went. App Clips can't read the photo library,
/// so these are previews kept from the originals while they were being sent.
struct SentPhotosView: View {
    let items: [UploadModel.UploadItem]

    @State private var opened: OpenedItem?

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 3)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    opened = OpenedItem(index: index)
                } label: {
                    SentThumbnail(item: item)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.statusLabel(item.status))
            }
        }
        .fullScreenCover(item: $opened) { opened in
            SentPagerView(items: items, startIndex: opened.index)
        }
    }

    static func statusLabel(_ status: UploadModel.UploadItem.Status) -> String {
        switch status {
        case .waiting: return "대기 중"
        case .preparing: return "원본 준비 중"
        case .uploading: return "보내는 중"
        case .uploadingRemotely: return "가까이 없어서 iCloud로 보내는 중"
        case .done(let remote): return remote ? "완료 (iCloud로 전달)" : "완료"
        case .failed(let message): return "실패: \(message)"
        }
    }
}

struct OpenedItem: Identifiable {
    let index: Int
    var id: Int { index }
}

private struct SentThumbnail: View {
    let item: UploadModel.UploadItem

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let preview = item.preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay {
                // Anything not finished stays dimmed, so "what got through" reads at a glance.
                if !isDone {
                    Color.black.opacity(0.35)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                StatusBadge(status: item.status)
                    .padding(4)
            }
            .overlay(alignment: .bottomLeading) {
                if item.isVideo {
                    Image(systemName: "video.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }

    private var isDone: Bool {
        if case .done = item.status { return true }
        return false
    }
}

private struct StatusBadge: View {
    let status: UploadModel.UploadItem.Status

    var body: some View {
        switch status {
        case .waiting:
            badge("clock", .white)
        case .preparing, .uploading, .uploadingRemotely:
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        case .done(let remote):
            badge(remote ? "checkmark.icloud.fill" : "checkmark.circle.fill", .green)
        case .failed:
            badge("exclamationmark.circle.fill", .red)
        }
    }

    private func badge(_ systemName: String, _ color: Color) -> some View {
        Image(systemName: systemName)
            .font(.body)
            .foregroundStyle(color)
            .shadow(radius: 2)
    }
}

/// Full-screen look at one sent photo, with what happened to it.
private struct SentPagerView: View {
    let items: [UploadModel.UploadItem]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(items: [UploadModel.UploadItem], startIndex: Int) {
        self.items = items
        self.startIndex = startIndex
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                    VStack(spacing: 16) {
                        if let preview = item.preview {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 60))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Text(SentPhotosView.statusLabel(item.status))
                            .font(.body)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private var title: String {
        guard items.indices.contains(index) else { return "" }
        return items[index].capturedAt?.formatted(date: .abbreviated, time: .shortened) ?? "보낸 사진"
    }
}
