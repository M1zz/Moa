import SwiftUI
import LeeoKit

struct EventListView: View {
    @Environment(EventStore.self) private var store
    @State private var isCreating = false
    @State private var path: [String] = []
    @State private var isShowingOnboarding = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        // 아이폰 듀오를 펴면 왼쪽(세로면 아래)은 이벤트 목록 · QR, 오른쪽(위)은 그 이벤트에 받은 사진이다.
        // 접혀 있거나 보통 아이폰이면 목록만 그린다. 지금 화면 그대로다.
        FoldSplitView {
            list
        } result: {
            FoldEventPhotos(eventID: path.last ?? store.events.first?.id)
                .environment(\.foldLayout, .single)
        }
    }

    private var list: some View {
        NavigationStack(path: $path) {
            Group {
                if store.events.isEmpty {
                    ContentUnavailableView {
                        Label("아직 이벤트가 없어요", systemImage: "qrcode")
                    } description: {
                        Text("이벤트를 만들고 QR을 보여주면, 같은 Wi-Fi에 있는 사람이 앱 설치 없이 이 iPhone으로 사진을 보낼 수 있어요. 받은 사진은 촬영 시각 그대로 사진 앱에 들어가요.")
                    } actions: {
                        Button("이벤트 만들기") { isCreating = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        // 이벤트를 마치고 목록으로 돌아온 자리. 모은 사진이 숫자로 보일 때만, 드물게 응원을 부탁한다.
                        LeeoTipAskSlot<MoaSpec>(tipJar: MoaSpec.tipJar,
                                                reached: MoaTipMoments.reached(photos: store.events.reduce(0) { $0 + $1.receivedCount }))
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        ForEach(store.events) { event in
                            NavigationLink(value: event.id) {
                                EventRow(event: event)
                            }
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("보태줘")
            .navigationDestination(for: String.self) { id in
                EventDetailView(eventID: id)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        isShowingOnboarding = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("앱 소개")
                    // 친구에게 소개하기 — App Store ID 가 생기면 나타난다.
                    LeeoShareAppLink<MoaSpec>()
                    // 개발자 응원하기 — 설정 화면이 없어 여기서 시트로 연다. 판매 중인 팁이 있어야 나타난다.
                    TipJarButton(tipJar: MoaSpec.tipJar)
                    // 백업 및 복원 — 설정 화면이 없어 여기서 연다.
                    NavigationLink { LeeoVaultView(appName: MoaSpec.displayName) } label: {
                        Label(LeeoVaultText.entry, systemImage: "externaldrive.badge.timemachine")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("이벤트 만들기")
                }
            }
            .sheet(isPresented: $isCreating) {
                CreateEventView()
            }
            .fullScreenCover(isPresented: $isShowingOnboarding) {
                OnboardingView()
                    .foldConfined()
            }
            .onAppear {
                guard !hasSeenOnboarding else { return }
                hasSeenOnboarding = true
                isShowingOnboarding = true
            }
            #if DEBUG
            // `-moa-auto-event` opens a receiving event straight away, so the flow can be
            // exercised from the console without tapping through the UI.
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("-moa-screenshots"), store.events.isEmpty {
                    let event = await store.seedForScreenshots()
                    if arguments.contains("-moa-open-first"), let event { path = [event.id] }
                    return
                }
                if arguments.contains("-moa-open-first"), let event = store.events.first, path.isEmpty {
                    path = [event.id]
                    return
                }
                guard ProcessInfo.processInfo.arguments.contains("-moa-auto-event"), path.isEmpty else { return }
                NSLog("[moa] auto-event starting")
                var event = store.events.first
                if event == nil {
                    do {
                        event = try await store.createEvent(name: "디버그 이벤트")
                    } catch {
                        NSLog("[moa] auto-event create failed: \(error)")
                    }
                }
                if let event { path = [event.id] }
            }
            #endif
        }
    }
}

/// 받은 사진이 이만큼 모였을 때 응원을 부탁한다. 큰 것부터.
enum MoaTipMoments {
    static let photos = [1000, 300, 100]

    static func reached(photos total: Int) -> [LeeoTipMoment] {
        photos.filter { total >= $0 }.map { threshold in
            LeeoTipMoment(id: "photos.\(threshold)",
                          message: String(localized: "지금까지 사진 \(total)장을 모았어요",
                                          comment: "Tip ask card: total photos received across all events"))
        }
    }
}

private struct TipJarButton: View {
    @ObservedObject var tipJar: LeeoTipJar
    @State private var isShowing = false

    var body: some View {
        if tipJar.isAvailable {
            Button {
                isShowing = true
            } label: {
                Image(systemName: "heart")
            }
            .accessibilityLabel(LeeoTipText.entry)
            .sheet(isPresented: $isShowing) {
                NavigationStack {
                    LeeoTipJarView<MoaSpec>(tipJar: tipJar)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { isShowing = false } label: { Label("닫기", systemImage: "xmark") }
                            }
                        }
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: HostedEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.name)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let count = String(localized: "받은 사진 \(event.receivedCount)개")
        guard let last = event.lastReceivedAt else { return count }
        return String(localized: "\(count) · 마지막 \(last.formatted(date: .abbreviated, time: .shortened))")
    }
}
