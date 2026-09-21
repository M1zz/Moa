# 모아 (Moa)

QR 하나로 게스트의 사진을 모아, **원본 그대로 · 찍은 시각 그대로** 호스트의 사진 앱에 넣어주는 앱.

```
게스트 iPhone                    Cloudflare (릴레이)                 호스트 iPhone
┌──────────────┐  PUT 원본 파일  ┌───────────────────┐  목록/다운로드  ┌───────────────────┐
│ App Clip     │ ──────────────▶ │ Worker + R2       │ ◀────────────── │ 모아 앱            │
│ (설치 없음)   │ POST manifest   │ 잠깐 보관하는 우편함 │  가져온 뒤 삭제   │ PhotoKit → 사진 앱  │
└──────────────┘                 └───────────────────┘                 └───────────────────┘
```

사진은 릴레이에 잠깐 머물다가 호스트 앱이 사진 앱에 넣는 즉시 삭제돼요. 최종 저장소는 호스트의 사진 보관함(→ iCloud 사진)이에요.

## 폴더 구성

| 경로 | 내용 |
|---|---|
| `Moa/` | 호스트 앱. 이벤트 생성, QR 표시, 20초 폴링, PhotoKit 가져오기 |
| `MoaClip/` | App Clip. PHPicker로 원본(HEIC, Live Photo 포함)을 골라 업로드 |
| `Shared/` | 두 타깃이 함께 쓰는 API 클라이언트, 모델, 설정 |
| `Config/` | App Clip 엔타이틀먼트와 Info.plist |
| `worker/` | Cloudflare Worker 릴레이 (R2 사용) |

Xcode 16 이상의 폴더 동기화 그룹을 쓰기 때문에, 폴더에 파일을 추가하면 자동으로 타깃에 포함돼요.

## 설정 순서

### 1. 릴레이 배포 (약 10분)

```bash
cd worker
npm install
npx wrangler login
npx wrangler r2 bucket create moa-relay
```

`wrangler.toml`에서 `TEAM_ID`를 본인 Apple Team ID로 바꾸고, `routes` 줄의 주석을 풀어 본인 도메인을 넣은 뒤 배포해요.

```bash
npx wrangler deploy
```

Cloudflare 대시보드 → R2 → `moa-relay` → Settings → Object lifecycle rules에서 **30일 지난 객체 삭제** 규칙을 추가하세요. 호스트가 가져가지 않은 사진이 계속 남지 않게 하는 안전장치예요.

배포 확인:

```bash
curl https://<도메인>/.well-known/apple-app-site-association
```

### 2. Xcode 설정

1. `Moa.xcodeproj`를 열어요.
2. `Moa`, `MoaClip` 두 타깃 모두 Signing & Capabilities에서 Team을 선택해요.
3. 번들 ID를 바꾸려면 세 곳을 같이 바꿔요: 각 타깃의 Bundle Identifier, `Config/MoaClip.entitlements`의 `parent-application-identifiers`, `worker/wrangler.toml`의 `CLIP_BUNDLE_ID`. App Clip ID는 반드시 `<앱 ID>.Clip` 형태여야 해요.
4. `Shared/AppConfig.swift`의 `host`와 `Config/MoaClip.entitlements`의 `appclips:` 도메인을 배포한 도메인으로 바꿔요.

### 3. 기기에서 테스트

**호스트 쪽:** `Moa` 스킴 실행 → 이벤트 만들기 → 사진 전체 접근 허용 → QR이 나와요.

**게스트 쪽 (App Clip 호출 흉내내기):**
- 가장 빠른 방법: `MoaClip` 스킴 → Edit Scheme → Run → Arguments → Environment Variables에 `_XCAppClipURL` = `https://<도메인>/e/<이벤트ID>`를 넣고 실행해요. 시뮬레이터에서도 돼요.
- 실제 QR 스캔 흐름: App Clip을 기기에 한 번 실행한 뒤, 설정 → 개발자 → App Clips Testing → Local Experiences에 URL 접두사 `https://<도메인>/e/`와 App Clip 번들 ID를 등록하고 카메라로 QR을 찍어요.

Live Photo 하나, 일반 사진 하나, 동영상 하나를 보내고 호스트 사진 앱에서 **촬영 날짜 위치에 들어왔는지, Live Photo가 살아 있는지** 확인하는 게 핵심 검증이에요.

### 4. 출시 전 체크리스트

- App Store Connect에서 App Clip 경험 설정: 기본 경험 + 고급 경험(URL 접두사 `https://<도메인>/e/`)
- `wrangler.toml`의 `APP_STORE_ID`를 채우면 QR을 Safari로 열었을 때 App Clip 카드가 떠요.
- 이벤트 생성 API가 누구에게나 열려 있어요. 공개 전에 App Attest 등으로 막는 걸 권장해요.

## 바로 받기: 서버 없이 같은 Wi-Fi로

> 호스트 앱의 이벤트는 이제 이 방식만 써요. 위의 릴레이(`worker/`) 설정은 App Clip 쪽 코드가 아직 남아 있어서 참고로 둔 거예요.

App Clip은 CloudKit에 쓸 수 없어서 게스트 업로드에는 릴레이가 필요했어요. 이 방식은 릴레이 대신 **호스트 iPhone이 직접 받습니다.** 받은 사진은 사진 앱의 이벤트 이름 앨범에 들어가고, iCloud 사진이 켜져 있으면 그대로 iCloud로 올라가요.

```
게스트 App Clip ── 같은 Wi-Fi, TCP ──▶ 호스트 모아 앱 (화면 켜 둠) ──▶ 사진 앱 → iCloud 사진
```

- QR은 Apple 기본 App Clip 링크 `https://appclip.apple.com/id?p=com.leeo.moa.Clip&host=…&port=…&key=…` 라서 도메인이 필요 없어요.
- App Clip에서는 Bonjour를 쓸 수 없어서, QR에 호스트의 IP·포트·일회용 키를 담아요. 화면을 다시 열면 키가 바뀌어요.
- 전송 형식과 규칙은 `Shared/DirectTransfer.swift` 맨 위에 있어요.

### 기기 두 대로 검증하기

1. 호스트 iPhone에서 `Moa` 스킴을 실행하고 이벤트를 만든 뒤 그 이벤트를 열어요. 사진 권한과 로컬 네트워크 권한을 허용하면 QR이 나와요.
2. **테스트용 링크 공유**로 URL을 Mac에 보내요.
3. 게스트 iPhone에서 `MoaClip` 스킴 → Edit Scheme → Run → Environment Variables에 `_XCAppClipURL` = 그 URL을 넣고 실행해요. 로컬 네트워크 권한을 허용한 뒤 사진을 보내요.
   - 카메라로 QR을 찍는 흐름을 보려면 설정 → 개발자 → App Clips Testing → Local Experiences에 URL 접두사 `https://appclip.apple.com/id?p=com.leeo.moa.Clip`을 등록해 보세요. Apple 도메인이 로컬 등록을 허용하는지는 아직 확인하지 않았어요.
4. 확인할 것: 호스트 화면의 숫자가 올라가는지, 사진 앱에서 **촬영 날짜 자리**에 들어갔는지, Live Photo가 살아 있는지.

**가장 먼저 볼 것은 실제 장소의 Wi-Fi예요.** 기기끼리 통신을 막는 Wi-Fi(클라이언트 격리)에서는 연결이 안 되고, 게스트 화면에 "연결하지 못했어요"가 나와요. 그러면 호스트가 개인용 핫스팟을 켜고 게스트가 거기에 붙는 방법으로 시험해 볼 수 있어요. 앱이 핫스팟 주소도 자동으로 잡아요. 다만 핫스팟은 동시 접속 수가 적어서 대안이 되기는 어려워요.

## 설계 메모

- **왜 CloudKit이 아닌가:** App Clip은 공개 DB 읽기만 가능하고 쓰기, private, shared 컨테이너는 막혀 있어요. 그래서 게스트 업로드에는 외부 릴레이가 필요해요.
- **원본 보존:** PHPicker를 `preferredAssetRepresentationMode = .current`로 써서 HEIC와 EXIF(촬영 시각, 위치)를 그대로 올려요. 호스트는 파일 그대로 `PHAssetCreationRequest`에 넣기 때문에 Photos가 메타데이터를 직접 읽어 타임라인 제자리에 배치해요.
- **Live Photo:** `com.apple.live-photo-bundle` 표현을 받아 사진과 `.pairedVideo`를 함께 보내요. 이 표현을 못 받으면 정지 사진으로 대체해요.
- **중복 방지:** 가져온 항목 ID를 호스트 기기에 기록해서, 원격 삭제가 실패해도 두 번 들어가지 않아요.
- **전송 완료 판정:** 모든 파일이 올라간 뒤 `manifest.json`이 써져야 호스트 목록에 나타나요. 중간에 끊긴 업로드는 보이지 않고 수명 주기 규칙으로 정리돼요.

## 알려진 한계 (MVP)

- 호스트 앱이 **열려 있을 때만** 가져와요. 백그라운드 가져오기(BGTaskScheduler 또는 푸시)는 다음 단계예요.
- 파일당 최대 100MB (Workers 요청 크기 제한). 긴 4K 영상은 R2 멀티파트 업로드로 확장해야 해요.
- App Clip 업로드는 화면이 켜져 있어야 해요. 업로드 중에는 자동 잠금을 꺼 두도록 처리했어요.
- 업로더 이름은 manifest에만 있고, 사진 앱에는 기록할 공개 API가 없어요.
- 이벤트를 만든 기기에서만 가져올 수 있어요(호스트 토큰이 그 기기의 키체인에 있음).
