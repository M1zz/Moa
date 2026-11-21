import Foundation
import Network
import Observation

/// 인터넷도 공유기도 없을 때의 길. 앱끼리는 iPhone 끼리 직접 잇는 Wi-Fi(AirDrop 과 같은 길)로
/// 서로를 찾고 보낸다. 두 기기 모두 Wi-Fi 만 켜 있으면 되고, 어느 네트워크에 붙어 있지 않아도 된다.
///
/// 호스트는 이벤트 ID 를 이름으로 Bonjour 에 알리고(`DirectReceiver`), 앱의 보내는 쪽은 그 이름을
/// 찾는다(`NearbyHostFinder`). 전송 규약과 키 확인은 `DirectTransfer` 그대로라, 키는 여전히 QR 에만
/// 있다 — 근처에 있다는 것만으로는 보낼 수 없다. App Clip 은 Bonjour 를 쓸 수 없어 이 길을 쓰지 않는다.
enum NearbyTransfer {
    /// `Config/Moa-Info.plist` 의 NSBonjourServices 에도 있어야 한다.
    static let serviceType = "_moa._tcp"

    static var parameters: NWParameters {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        // Lets the same port be taken again right after the screen closes.
        parameters.allowLocalEndpointReuse = true
        return parameters
    }
}

/// Keeps looking for the host that advertises this event while the send screen is open.
@MainActor
@Observable
final class NearbyHostFinder {
    private(set) var endpoint: NWEndpoint?
    private var browser: NWBrowser?
    private var startedAt = ContinuousClock.now

    func start(eventID: String) {
        stop()
        startedAt = .now
        let browser = NWBrowser(
            for: .bonjour(type: NearbyTransfer.serviceType, domain: nil),
            using: NearbyTransfer.parameters
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let match = results.first { result in
                if case let .service(name, _, _, _) = result.endpoint { return name == eventID }
                return false
            }?.endpoint
            Task { @MainActor in self?.endpoint = match }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        endpoint = nil
    }

    /// The host's endpoint, giving the search a few seconds from when it started. After that it
    /// answers at once, so a host that isn't nearby costs the first item a moment, not every item.
    func waitForEndpoint() async -> NWEndpoint? {
        let deadline = startedAt + .seconds(3)
        while endpoint == nil, browser != nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return endpoint
    }
}
