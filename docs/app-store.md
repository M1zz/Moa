# 앱 심사 메모

스토어 문구(이름·부제·설명·키워드·URL)는 레포 최상단 `APPSTORE.md` 가 원본이고 DeployBar 가 올린다.
이 파일에는 App Store Connect ▸ 앱 심사 정보 ▸ 메모 칸에 붙여 넣을 글만 둔다.
심사관은 영어로 읽으므로 영어 메모를 넣는다. 한국어는 내용 확인용이다.

## English (붙여넣기)

```
Botaejwo collects photos from guests through an App Clip. Testing needs two devices: one runs the app (the host) and the other scans its QR code (the guest).

Host device
1. Open Botaejwo and create an event. Allow Photos access and Local Network access.
2. Open the event. A QR code appears. Keep this screen open while testing.

Guest device
3. Scan the host's QR code with the Camera app. The App Clip opens with the event name.
4. Tap Choose Photos and Videos and pick a few. Each one is added to the host's Photos app, in an album named after the event, at the date it was taken.

The devices do not need to be on the same network. When they cannot reach each other directly, the App Clip encrypts each file and passes it through the developer's CloudKit public database. The host imports it within about 30 seconds while the event screen is open and then deletes the record. The decryption key exists only in the QR code.

The App Clip needs a QR code made by the host app, because the code carries the host's address and a one-time key. If the App Clip is opened without one, for example from the default App Clip link or the App Store demo URL, it explains how to scan the host's QR code.

A short screen recording of the full flow on two devices is attached.
```

## 한국어 (확인용)

```
보태줘는 App Clip으로 게스트의 사진을 모읍니다. 테스트하려면 기기 두 대가 필요합니다. 한 대는 앱을 실행하고(호스트), 다른 한 대는 그 QR을 찍습니다(게스트).

호스트 기기
1. 보태줘를 열고 이벤트를 만듭니다. 사진 접근과 로컬 네트워크 접근을 허용합니다.
2. 이벤트를 열면 QR이 나옵니다. 테스트하는 동안 이 화면을 열어 둡니다.

게스트 기기
3. 카메라 앱으로 호스트의 QR을 찍으면 이벤트 이름과 함께 App Clip이 열립니다.
4. 사진·동영상 고르기를 눌러 몇 장 고릅니다. 호스트의 사진 앱에 이벤트 이름의 앨범으로, 찍은 날짜 자리에 들어갑니다.

두 기기가 같은 네트워크에 있지 않아도 됩니다. 서로 직접 연결되지 않으면 App Clip이 파일을 암호화해 개발자의 CloudKit 공개 데이터베이스를 거쳐 보냅니다. 호스트는 이벤트 화면을 열어 둔 동안 30초 안팎으로 가져오고, 가져온 뒤 기록을 지웁니다. 암호를 푸는 키는 QR 안에만 있습니다.

App Clip은 호스트 앱이 만든 QR이 있어야 합니다. QR에 호스트의 주소와 일회용 키가 들어 있기 때문입니다. 기본 App Clip 링크나 App Store 데모 URL처럼 QR 없이 열리면 호스트의 QR을 찍는 방법을 안내합니다.

두 기기로 전체 흐름을 찍은 짧은 화면 녹화를 첨부했습니다.
```
