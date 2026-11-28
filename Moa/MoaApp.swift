import AppIntents
import SwiftUI
import LeeoKit

@main
struct MoaApp: App {
    /// 금고(bootstrap 안)가 예약된 복원을 먼저 적용한 뒤에 읽도록 init 에서 만든다.
    @State private var store: EventStore
    /// 알림을 누르면 그 이벤트를 연다 (→ RemoteRefresh.swift)
    @UIApplicationDelegateAdaptor(MoaAppDelegate.self) private var appDelegate

    init() {
        // LeeoKit 계약을 켜는 한 줄 (→ MoaSpec.swift). 실행 횟수 기록 · 익명 사용 통계 ·
        // 크래시 진단 · DEBUG 프리플라이트. 통계·진단은 FeedbackHub(CloudKit)로 올라간다 —
        // 그 iCloud 컨테이너 권한은 Config/Moa.entitlements 에 있다 (없으면 CKContainer 에서 죽는다).
        LeeoKit.bootstrap(MoaSpec.self)
        let store = EventStore()
        _store = State(initialValue: store)
        // Siri · Spotlight 가 같은 이벤트 목록을 읽게 한다 (→ EventIntents.swift)
        AppDependencyManager.shared.add(dependency: store)
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WidePadPanes { EventListView() }
                // 개발자가 보낸 의견에 답장하면, 앱이 앞으로 올 때 답장을 시트로 보여 준다 (LeeoKit).
                .leeoFeedbackReplyNotice(MoaSpec.self)
                // 모든 사용자가 한 번은 감사를 받는다 (LeeoKit 3.46)
                .leeoCelebrations(appName: MoaSpec.displayName)
                .environment(store)
                // 팁 상품을 불러오고 끝나지 않은 팁을 마저 센다.
                .task { await MoaSpec.tipJar.startStandalone() }
                .task { await store.reindex() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        Task { await store.reindex() }
                        RemoteRefresh.schedule(for: store)
                    case .active:
                        // 닫아 둔 동안 멤버들이 보탠 사진을 바로 들인다 (알림은 없이 — 보고 있으니까)
                        Task { _ = await store.pullAllRemote() }
                    default:
                        break
                    }
                }
                // 시트 · 알림창이 아이폰 듀오의 접힌 선을 비킨다. 접혀 있으면 아무것도 바뀌지 않는다.
                .foldAware()
        }
        // 앱을 닫아 둔 동안 멀리서 보낸 사진을 가져와 알린다 (→ RemoteRefresh.swift)
        .backgroundTask(.appRefresh(RemoteRefresh.taskIdentifier)) {
            await RemoteRefresh.run(store: store)
        }
        // 의견 답장도 같은 방식으로 알린다 — 식별자는 Config/Moa-Info.plist 에 있다.
        .leeoFeedbackReplyRefresh(MoaSpec.self)
    }
}

// MARK: - 넓은 아이패드

/// 넓은 아이패드도 가로로 편 아이폰 듀오와 같은 짝으로 세운다: 왼쪽 이벤트 · 큰 QR(안내판), 오른쪽 받은 사진.
/// 아이패드는 접히지 않아 Fold 가 한 쪽(single)으로 재므로, regular 폭이면 여기서 펼친 자세로 바꿔 흘린다.
/// Slide Over · 좁은 분할(compact)은 아이폰처럼 한 쪽.
private struct WidePadPanes<Content: View>: View {
    @Environment(\.foldLayout) private var fold
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.foldLayout, layout)
            .environment(\.isWidePadPanes, layout.isUnfolded && !fold.isUnfolded)
    }

    private var layout: FoldLayout {
        guard UIDevice.current.userInterfaceIdiom == .pad, sizeClass == .regular,
              fold.windowSize != .zero else { return fold }
        return FoldLayout(posture: .innerLandscape, windowSize: fold.windowSize)
    }
}

extension EnvironmentValues {
    /// 넓은 아이패드라서 두 쪽으로 세웠는가(진짜 접는 폰이 아니라).
    @Entry var isWidePadPanes = false
}

extension View {
    /// 전체 화면 덮개에 건다. 펼친 아이폰 듀오에서는 고르는 쪽 판에만 서고(접힌 선을 넘지 않게),
    /// 넓은 아이패드는 접힌 선이 없으니 화면을 다 쓴다.
    func coverConfined() -> some View { modifier(CoverConfined()) }
}

private struct CoverConfined: ViewModifier {
    @Environment(\.isWidePadPanes) private var widePad

    func body(content: Content) -> some View {
        if widePad {
            content.environment(\.foldLayout, .single)
        } else {
            content.foldConfined()
        }
    }
}
