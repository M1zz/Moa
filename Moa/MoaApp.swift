import SwiftUI
import LeeoKit

@main
struct MoaApp: App {
    @State private var store = EventStore()

    init() {
        // LeeoKit 계약을 켜는 한 줄 (→ MoaSpec.swift). 실행 횟수 기록 · 익명 사용 통계 ·
        // 크래시 진단 · DEBUG 프리플라이트. 통계·진단은 FeedbackHub(CloudKit)로 올라간다 —
        // 그 iCloud 컨테이너 권한은 Config/Moa.entitlements 에 있다 (없으면 CKContainer 에서 죽는다).
        LeeoKit.bootstrap(MoaSpec.self)
    }

    var body: some Scene {
        WindowGroup {
            EventListView()
                .environment(store)
        }
    }
}
