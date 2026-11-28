import BackgroundTasks
import UIKit
import UserNotifications

/// 앱을 닫아 둔 동안 멀리서 보낸 사진을 받는 길.
///
/// CloudKit 공개 DB 의 구독(푸시)은 Production 에서 만들 수 없다(LeeoFeedbackService 주석의 실측).
/// 그래서 앱이 뒤로 갈 때 백그라운드 새로고침을 예약해 두고, iOS 가 앱을 깨우면 최근 이벤트의
/// iCloud 함을 비워 사진 앱에 넣은 뒤 로컬 알림으로 알린다. 언제 깨울지는 iOS 가 정하니 실시간은
/// 아니다 — 앱을 열 때(`MoaApp`)와 이벤트 화면(30초마다)이 같은 일을 해서 메운다.
enum RemoteRefresh {
    /// `Config/Moa-Info.plist` 의 BGTaskSchedulerPermittedIdentifiers 에도 있어야 한다.
    static let taskIdentifier = "com.leeo.moa.remote-inbox"
    /// 알림을 누르면 열 이벤트.
    static let eventIDKey = "moaEventID"

    /// 앨범이 하나라도 있으면 깨워 달라고 한다.
    @MainActor
    static func schedule(for store: EventStore) {
        guard RemoteInbox.isConfigured, !store.events.isEmpty else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            NSLog("[moa] background refresh not scheduled: \(error)")
            #endif
        }
    }

    /// iOS 가 깨웠을 때. 가져온 것을 이벤트마다 한 번 알리고 다음을 예약한다.
    @MainActor
    static func run(store: EventStore) async {
        for (event, count) in await store.pullAllRemote() {
            await notify(event: event, count: count)
        }
        schedule(for: store)
    }

    /// 이벤트를 처음 열 때 한 번 묻는다. 거절해도 사진은 그대로 받는다 — 알림만 없다.
    static func askForNotifications() async {
        guard RemoteInbox.isConfigured else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private static func notify(event: HostedEvent, count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = event.name
        content.body = String(localized: "멤버들이 보탠 사진 \(count)개를 사진 앱에 넣었어요",
                              comment: "Notification after photos other album members added were imported in the background")
        content.sound = .default
        content.threadIdentifier = event.id
        content.userInfo = [eventIDKey: event.id]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// 알림을 누르면 그 이벤트로 연다.
final class MoaAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let id = response.notification.request.content.userInfo[RemoteRefresh.eventIDKey] as? String else { return }
        await MainActor.run { EventRouter.shared.openEventID = id }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
