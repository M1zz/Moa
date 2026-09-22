# 모아 todo

## 완료
- [x] 서버(Cloudflare Worker 릴레이) 제거, 같은 Wi-Fi 직접 전송만 남김
- [x] App Clip 엔타이틀먼트에서 가짜 도메인(associated domains) 제거
- [x] 촬영 시각과 위치를 함께 보내고 호스트가 사진 앱에 명시적으로 지정

- [x] App Clip 링크를 `appclip.apple.com`에서 FindMe와 같은 `m1zz.github.io` 도메인으로 변경

- [x] 근거리 실패 시 iCloud(CloudKit 공개 DB)로 자동 전환, 파일·메타데이터 암호화

- [x] 받은 사진마다 보낸 사람 이름 표시 (격자·전체 화면)

## 다음
- [ ] CloudKit Console에서 컨테이너·서버 키 만들고 `Shared/CloudKitConfig.swift` 채우기 (사람이 직접)
- [ ] `MoaItem.eventID`를 Queryable로 표시하고, 실제 원거리 전송 한 번 검증
- [ ] 호스트가 앱을 열지 않아도 알 수 있게 푸시 알림 (CloudKit 구독)
- [ ] 기기 두 대로 실제 전송 검증 (Live Photo, HEIC 사진, 동영상, 촬영 날짜 위치)
- [ ] Local Experience에 `https://m1zz.github.io/moa/c` 등록하고 카메라로 QR 찍어 App Clip 카드 뜨는지 확인
- [ ] App Store Connect에서 App Clip 고급 경험(`https://m1zz.github.io/moa/c`) 설정, 대한민국 판매 포함
- [ ] 작은 폰트(.caption, .footnote, .subheadline)를 .body 이상으로 바꾸기
- [ ] String Catalog로 한국어/영어 다국어 지원
