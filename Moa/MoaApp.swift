import SwiftUI
import LeeoKit

@main
struct MoaApp: App {
    /// 금고(bootstrap 안)가 예약된 복원을 먼저 적용한 뒤에 읽도록 init 에서 만든다.
    @State private var store: EventStore

    init() {
        // LeeoKit 계약을 켜는 한 줄 (→ MoaSpec.swift). 실행 횟수 기록 · 익명 사용 통계 ·
        // 크래시 진단 · DEBUG 프리플라이트. 통계·진단은 FeedbackHub(CloudKit)로 올라간다 —
        // 그 iCloud 컨테이너 권한은 Config/Moa.entitlements 에 있다 (없으면 CKContainer 에서 죽는다).
        LeeoKit.bootstrap(MoaSpec.self)
        _store = State(initialValue: EventStore())
    }

    var body: some Scene {
        WindowGroup {
            EventListView()
                .environment(store)
                // 팁 상품을 불러오고 끝나지 않은 팁을 마저 센다.
                .task { await MoaSpec.tipJar.startStandalone() }
                // 시트 · 알림창이 아이폰 듀오의 접힌 선을 비킨다. 접혀 있으면 아무것도 바뀌지 않는다.
                .foldAware()
        }
    }
}
