//
//  EventIntents.swift
//  Moa
//
//  "보태줘 사진 모으기 시작" — 모임이 시작되면 말로 새 사진 모으기를 연다. 이름을 정하면 QR 이 나온다.
//
//  만든 이벤트는 Spotlight 에 싣는다(iOS 18+). Siri · Spotlight 에서 누르면 그 이벤트가 열린다.
//

import AppIntents
import CoreSpotlight
import Foundation

@MainActor @Observable
final class EventRouter {
    static let shared = EventRouter()
    /// 늘어날 때마다 목록 화면이 새 모으기를 연다.
    var createRequest = 0
    /// 열어 달라는 이벤트. 목록 화면이 그 이벤트로 넘어가고 비운다.
    var openEventID: String?
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

// MARK: - 이벤트

struct EventEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("사진 모으기 이벤트", comment: "Siri/Spotlight: one photo-collecting event the user created")
    )
    static let defaultQuery = EventQuery()

    let id: String
    let name: String
    let createdAt: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(createdAt.formatted(date: .long, time: .omitted))")
    }

    init(_ event: HostedEvent) {
        id = event.id
        name = event.name
        createdAt = event.createdAt
    }
}

@available(iOS 18.0, *)
extension EventEntity: IndexedEntity {}

struct EventQuery: EntityStringQuery {
    @Dependency private var store: EventStore

    func entities(for identifiers: [String]) async throws -> [EventEntity] {
        let wanted = Set(identifiers)
        return await store.events.filter { wanted.contains($0.id) }.map(EventEntity.init)
    }

    func entities(matching string: String) async throws -> [EventEntity] {
        await store.events
            .filter { $0.name.range(of: string, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .map(EventEntity.init)
    }

    func suggestedEntities() async throws -> [EventEntity] {
        await store.events.map(EventEntity.init)
    }
}

/// 이벤트를 연다. Spotlight · Siri 결과를 누르면 여기로 온다.
struct OpenEventIntent: OpenIntent {
    static let title = LocalizedStringResource("이벤트 열기", comment: "Siri/Spotlight: open a photo-collecting event")
    static let description = IntentDescription(
        LocalizedStringResource("이벤트의 QR 과 받은 사진을 엽니다.", comment: "Siri: open event description")
    )

    @Parameter(title: LocalizedStringResource("사진 모으기 이벤트", comment: "Siri/Spotlight: one photo-collecting event the user created"),
               description: LocalizedStringResource("열어 볼 이벤트", comment: "Siri: event parameter description"))
    var target: EventEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        EventRouter.shared.openEventID = target.id
        return .result()
    }
}

extension EventStore {
    /// Spotlight 에 싣는 이벤트를 지금 것에 맞춘다. 앱을 열 때와 뒤로 보낼 때 부른다.
    func reindex() async {
        guard #available(iOS 18.0, *) else { return }
        let index = CSSearchableIndex.default()
        try? await index.deleteAppEntities(ofType: EventEntity.self)
        try? await index.indexAppEntities(events.map(EventEntity.init))
    }
}

// MARK: - Siri 문구

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
