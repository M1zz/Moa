//
//  EventIntents.swift
//  Moa
//
//  "보태줘 사진 모으기 시작" — 모임이 시작되면 말로 새 사진 모으기를 연다. 이름을 정하면 QR 이 나온다.
//

import AppIntents
import Foundation

@MainActor @Observable
final class EventRouter {
    static let shared = EventRouter()
    /// 늘어날 때마다 목록 화면이 새 모으기를 연다.
    var createRequest = 0
}

struct NewEventIntent: AppIntent {
    static let title = LocalizedStringResource("사진 모으기 시작", comment: "Siri: start collecting photos for a new event")
    static let description = IntentDescription(
        LocalizedStringResource("새 사진 모으기를 열어 QR 을 만듭니다.", comment: "Siri: new event description")
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        EventRouter.shared.createRequest &+= 1
        return .result()
    }
}

struct MoaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewEventIntent(),
            phrases: ["Start collecting photos with \(.applicationName)", "New photo drop in \(.applicationName)"],
            shortTitle: "Collect Photos",
            systemImageName: "qrcode"
        )
    }
}
