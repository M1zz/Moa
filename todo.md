# 모아 todo

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

## 다음
- [ ] App Store Connect에 개인정보 처리방침 URL(`https://m1zz.github.io/moa/privacy.html`)과 마케팅 URL(`https://m1zz.github.io/moa/`) 입력
- [ ] 호스트가 앱을 열지 않아도 알 수 있게 푸시 알림 (CloudKit 구독)
- [ ] 기기 두 대로 실제 전송 검증 (Live Photo, HEIC 사진, 동영상, 촬영 날짜 위치)
- [ ] Local Experience에 `https://m1zz.github.io/moa/c` 등록하고 카메라로 QR 찍어 App Clip 카드 뜨는지 확인
- [ ] App Store Connect에서 App Clip 고급 경험(`https://m1zz.github.io/moa/c`) 설정, 대한민국 판매 포함
- [ ] m1zz.github.io/moa 소개·개인정보·`/moa/c` 페이지를 "보태줘"로 바꾸고 영어 추가
- [ ] App Store Connect App Clip 작업 버튼을 "실행"에서 "열기"로
- [ ] 작은 폰트(.caption, .footnote, .subheadline)를 .body 이상으로 바꾸기
