# 보태줘 todo

## 아이폰 듀오 대응 (2026-10-30, 듀오 시뮬레이터 빌드 성공 · 실기기 확인 안 함)
- [x] 루트에 `.foldAware()`, 시트 · 알림창이 접힌 선을 비킨다
- [x] 펴면 왼쪽(세로면 아래) 이벤트 목록 · QR | 오른쪽(위) 그 이벤트에 받은 사진(`Views/FoldEventPhotos.swift`). 목록에 있으면 맨 위 이벤트
- [x] 펼쳐 있으면 이벤트 화면 안의 사진 격자는 빼고 오른쪽 판에만 (같은 것을 두 번 그리지 않는다)
- [x] 온보딩 · 사진 크게 보기는 `.foldConfined()`
- [x] 툴바의 글자만 있던 단추(닫기 · 취소 · 만들기)에 아이콘
- [ ] App Clip(MoaClip)은 LeeoKit 을 쓰지 않아 손대지 않음
- [ ] 기기 부하로 시뮬레이터 화면 캡처는 못 봄. `-FoldPretend -moa-screenshots -moa-open-first` 로 펼친 화면 확인
- [ ] 가로로 편 화면 · 실기기 확인 (⚠️ Xcode 27.1 로 빌드해야 듀오 배치가 켜진다)

## 1.0 심사 반려 대응 (2026-11-05)
- 반려 사유 원문은 레포 · DeployBar 로그 어디에도 없다 (App Store Connect API 로 Resolution Center 를 못 읽는다). 사람이 원문을 붙여 줘야 정확히 고친다.
- [x] 이벤트 화면의 "테스트용 링크 공유" → "초대 링크 보내기"(24개 언어), 개발용 IP:포트 표시 제거 — 출시 앱에 시험용 단추 · 디버그 정보가 보이지 않게
- [ ] 사람: App Store Connect ▸ 앱 클립 ▸ 고급 경험에 `https://m1zz.github.io/moa/c` 가 등록 · 승인됐는지 확인. 안 되어 있으면 QR 을 카메라로 찍어도 앱 클립 카드가 뜨지 않는다(심사자가 앱 클립을 못 연다)
- [ ] 사람: 앱 심사 정보 ▸ 메모에 아래 글 붙여넣기 (계정 없음 · 기기 두 대 필요)

```
No account or sign-in is needed.

Botaejwo needs two iPhones: one host and one guest.
1. On the host iPhone, open Botaejwo, tap Create Event, enter any name and tap Create. The event screen shows a QR code. Keep this screen open; photos arrive only while it is open.
2. On the guest iPhone, scan the QR code with the built-in Camera app and tap Open on the App Clip card. The App Clip (com.leeo.moa.Clip) opens. Nothing needs to be installed.
3. In the App Clip, tap Choose Photos and Videos, pick a few items and send them.
4. On the host iPhone they appear in the Photos app, in an album with the event name, at the time each photo was taken.

If the two iPhones are on the same Wi-Fi, photos go directly from phone to phone. Otherwise they are encrypted on the guest's iPhone with a key that exists only in the QR code, pass briefly through our CloudKit public database and are deleted once the host receives them.
If the guest cannot scan, tap Send Invite Link on the host's event screen and open the link on the guest iPhone.
App Clip experience URL: https://m1zz.github.io/moa/c
```

## 완료
- [x] 서버(Cloudflare Worker 릴레이) 제거, 같은 Wi-Fi 직접 전송만 남김
- [x] App Clip 엔타이틀먼트에서 가짜 도메인(associated domains) 제거
- [x] 촬영 시각과 위치를 함께 보내고 호스트가 사진 앱에 명시적으로 지정

- [x] App Clip 링크를 `appclip.apple.com`에서 FindMe와 같은 `m1zz.github.io` 도메인으로 변경

- [x] 근거리 실패 시 iCloud(CloudKit 공개 DB)로 자동 전환, 파일·메타데이터 암호화

- [x] 받은 사진마다 보낸 사람 이름 표시 (격자·전체 화면)
- [x] 첫 실행 온보딩 3장 추가 (한국어·영어)
- [x] GitHub Pages에 소개 페이지와 개인정보 처리방침 공개
- [x] App Store 스크린샷 5장 (6.5인치 1242×2688, `Screenshots/`), DEBUG 전용 샘플 데이터(`-moa-screenshots`, `MOA_DEMO_DIR`)
- [x] 심사 반려(2.3.8) 대응: 기기 표시 이름을 스토어 이름과 같은 "보태줘"로 변경 (앱·App Clip·화면 제목·권한 안내 문구)

- [x] 심사 반려(2.1(a)) 대응: App Clip이 초대 없이 열리면 오류 대신 QR 안내, 앱·App Clip 영어 지원, iCloud 원거리 전송 켬(Development)
- [x] 한국어·영어 스토어 문구(`APPSTORE.md`), 릴리즈노트, 언어별 스크린샷(`docs/screenshots/`)
- [x] CloudKit 원거리 전송 켬: 컨테이너·스키마(Production 배포)·서버 키(Development·Production), 두 환경 모두 올리기·조회·삭제 검증
- [x] 이름 통일: 공개 페이지(소개·개인정보·`/moa/c`)를 보태줘/Botaejwo로, 영어 페이지 `/moa/en/` 추가, 기본 App Clip 카드 작업 "열기"·부제목 변경

## 다음
- [ ] App Store Connect에 개인정보 처리방침 URL(`https://m1zz.github.io/moa/privacy.html`)과 마케팅 URL(`https://m1zz.github.io/moa/`) 입력
- [ ] 호스트가 앱을 열지 않아도 알 수 있게 푸시 알림 (CloudKit 구독)
- [ ] 기기 두 대로 실제 전송 검증 (Live Photo, HEIC 사진, 동영상, 촬영 날짜 위치)
- [ ] Local Experience에 `https://m1zz.github.io/moa/c` 등록하고 카메라로 QR 찍어 App Clip 카드 뜨는지 확인
- [ ] App Store Connect에서 App Clip 고급 경험(`https://m1zz.github.io/moa/c`) 설정, 대한민국 판매 포함
- [ ] 고급 App Clip 경험 수정본(부제목·작업 "열기") "Apple로 전송" (사람이 직접)
- [ ] 작은 폰트(.caption, .footnote, .subheadline)를 .body 이상으로 바꾸기
