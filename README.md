# 모아 (Moa)

QR 하나로 게스트의 사진을 모아, **원본 그대로 · 찍은 시각 그대로** 호스트의 사진 앱에 넣어주는 앱.
서버가 없어요. 게스트 iPhone이 같은 Wi-Fi에 있는 호스트 iPhone으로 바로 보내요.

```
게스트 App Clip ── 같은 Wi-Fi, TCP ──▶ 호스트 모아 앱 (화면 켜 둠) ──▶ 사진 앱 → iCloud 사진
```

## 비용

Apple Developer Program 멤버십 말고는 드는 비용이 없어요.

| 구성 요소 | 쓰는 것 | 비용 |
|---|---|---|
| 게스트 앱 | App Clip (설치 없이 실행) | 무료 |
| QR 링크 | GitHub Pages `m1zz.github.io/moa/c` (FindMe와 같은 도메인) | 무료 |
| 전송 | 같은 Wi-Fi(또는 개인용 핫스팟) 안의 TCP 직접 연결 | 무료, 서버 없음 |
| 저장 | 호스트의 사진 보관함 → iCloud 사진 | 호스트의 기존 iCloud 용량 |

## 폴더 구성

| 경로 | 내용 |
|---|---|
| `Moa/` | 호스트 앱. 이벤트 생성, QR 표시, 직접 받기, PhotoKit 가져오기 |
| `MoaClip/` | App Clip. PHPicker로 원본(HEIC, Live Photo 포함)을 골라 호스트로 보내요 |
| `Shared/` | 두 타깃이 함께 쓰는 전송 규약, 모델, 설정 |
| `Config/` | App Clip 엔타이틀먼트와 Info.plist |

Xcode 16 이상의 폴더 동기화 그룹을 쓰기 때문에, 폴더에 파일을 추가하면 자동으로 타깃에 포함돼요.

## 동작 방식

- QR은 `https://m1zz.github.io/moa/c?host=…&port=…&key=…&name=…` 이에요. 사진은 이 도메인을 거치지 않아요. iOS가 어떤 App Clip을 열지 아는 데만 써요.
- 도메인 연결은 FindMe와 같은 방식이에요. [m1zz.github.io](https://github.com/M1zz/m1zz.github.io) 레포의 `.well-known/apple-app-site-association`에 있는 `appclips.apps`에 `QGAQ3AY3R3.com.leeo.moa.Clip`이 들어 있고, `/moa/c/index.html`은 브라우저로 열었을 때 보이는 안내 페이지예요.
- 처음에는 Apple 기본 링크(`appclip.apple.com`)를 썼어요. 그런데 출시 전에는 카메라로 찍으면 "This App Clip is not currently available in your country"가 떠서 자체 도메인으로 바꿨어요.
- App Clip에서는 Bonjour를 쓸 수 없어서, QR에 호스트의 IP·포트·일회용 키를 담아요. 화면을 다시 열면 키가 바뀌어요.
- 전송 형식과 규칙은 `Shared/DirectTransfer.swift` 맨 위에 있어요.

## 기기 두 대로 테스트하기

1. 두 iPhone을 같은 Wi-Fi에 연결해요. 기기끼리 통신을 막는 Wi-Fi(클라이언트 격리)면 호스트의 개인용 핫스팟을 써요.
2. 호스트 iPhone에서 `Moa` 스킴을 실행하고 이벤트를 만든 뒤 그 이벤트를 열어요. 사진 권한과 로컬 네트워크 권한을 허용하면 QR이 나와요.
3. **테스트용 링크 공유**로 URL을 Mac에 보내요.
4. 게스트 iPhone에서 `MoaClip` 스킴 → Edit Scheme → Run → Environment Variables에 `_XCAppClipURL` = 그 URL을 넣고 실행해요. 로컬 네트워크 권한을 허용한 뒤 사진을 보내요.
   - 카메라로 QR을 찍는 흐름: 게스트 iPhone에 `MoaClip`을 한 번 설치한 뒤, 설정 → 개발자 → App Clips Testing → Local Experiences → Register에서 URL 접두사 `https://m1zz.github.io/moa/c`, Bundle ID `com.leeo.moa.Clip`을 등록하고 QR을 찍어요.
   - TestFlight에 올리면 App Clip 호출 URL을 등록해 두고 테스터가 TestFlight 앱에서 App Clip을 실행해 볼 수 있어요.
5. 확인할 것: 호스트 화면의 숫자가 올라가는지, 사진 앱의 이벤트 앨범에 **촬영 날짜 자리**로 들어갔는지, Live Photo가 살아 있는지.

## 출시 전 체크리스트

- App Store Connect에서 App Clip **고급 경험**을 추가해요. URL은 `https://m1zz.github.io/moa/c`예요. 도메인 검증은 위 AASA 파일로 통과해요.
- 가격 및 사용 가능 여부에서 **대한민국**이 들어 있는지 확인해요. 빠져 있으면 출시한 뒤에도 "your country"에서 사용할 수 없다는 메시지가 떠요.
- 앱 심사 메모에 "두 기기가 같은 Wi-Fi에 있어야 동작함"과 테스트 방법을 적어 두세요.

## 설계 메모

- **왜 서버가 없나:** App Clip은 CloudKit에 쓸 수 없어요(공개 DB 읽기만 가능). 외부 서버 대신 호스트 iPhone이 직접 받는 쪽을 택했어요.
- **원본 보존:** PHPicker를 `preferredAssetRepresentationMode = .current`로 써서 HEIC와 EXIF(촬영 시각, 위치)를 그대로 보내요. 호스트는 파일 그대로 `PHAssetCreationRequest`에 넣기 때문에 Photos가 메타데이터를 직접 읽어 타임라인 제자리에 배치해요.
- **Live Photo:** `com.apple.live-photo-bundle` 표현을 받아 사진과 `.pairedVideo`를 함께 보내요. 이 표현을 못 받으면 정지 사진으로 대체해요.
- **저장 확인:** 호스트는 사진 앱에 넣은 뒤에야 성공 응답을 보내요. 게스트의 "완료"는 호스트 보관함에 들어갔다는 뜻이에요.

## 알려진 한계

- 호스트와 게스트가 **같은 네트워크**에 있어야 해요. 멀리 있는 사람은 보낼 수 없어요.
- 호스트 앱의 이벤트 화면이 **열려 있을 때만** 받아요. 화면은 자동으로 꺼지지 않게 해 뒀어요.
- 게스트도 다 보낼 때까지 화면을 켜 둬야 해요.
- 업로더 이름은 호스트 화면 알림에만 쓰이고, 사진 앱에는 기록할 공개 API가 없어요.
