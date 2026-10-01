#!/bin/sh
# 배포 전 게이트 — 여기서 실패하면 DeployBar 가 아카이브를 만들지 않는다.
#
# 사용법:
#   sh scripts/predeploy.sh
#
# 다국어(.xcstrings) 검사는 DeployBar 에 내장돼 있으므로 여기서 다시 하지 않는다.
# 이 스크립트는 "이 앱만의" 검사 — 테스트, 금지 패턴 검사 등 — 를 담는다.
#
# ⚠️ CODE_SIGNING_ALLOWED=NO 로 테스트를 빠르게 만들지 말 것.
#    entitlements 가 빠지면 CloudKit 등 실제 배포 경로에서만 터지는 문제를 놓친다.
set -e
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

SCHEME="Moa"
PROJECT_FLAG="-project"
PROJECT="Moa.xcodeproj"

# 시뮬레이터는 **가장 최신 iOS 런타임의 iPhone** 으로 고른다.
# `grep iPhone | head -1` 로 고르면 구버전 런타임 기기가 먼저 잡혀
# "Unable to find a destination matching..." (exit 70) 로 죽는다.
DEST_ID="$(xcrun simctl list devices available --json | python3 -c '
import json, re, sys
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        if d.get("isAvailable") and "iPhone" in d.get("name", ""):
            if best is None or version > best[0]:
                best = (version, d["udid"])
print(best[1] if best else "")
')"
if [ -z "$DEST_ID" ]; then
  echo "❌ 사용 가능한 iPhone 시뮬레이터가 없습니다"
  xcrun simctl list devices available | head -30
  exit 1
fi
DEST="platform=iOS Simulator,id=$DEST_ID"

# 원거리(iCloud) 전송은 출시 빌드에서 productionKeyID 를 쓴다. 비어 있으면 같은 Wi-Fi 가 아닐 때
# 게스트가 보낼 길이 없어 심사에서 "QR 찍었더니 오류" 로 반려된다(1.0 (3) 반려 사유).
CONFIG="Shared/CloudKitConfig.swift"
if [ ! -f "$CONFIG" ]; then
  echo "❌ $CONFIG 가 없습니다 — Config/CloudKitConfig.example.swift 를 보고 만드세요"
  exit 1
fi
for field in containerID productionKeyID privateKeyBase64; do
  if grep -Eq "static let $field = \"\"" "$CONFIG"; then
    echo "❌ $CONFIG 의 $field 가 비어 있습니다 — 출시 빌드에서 원거리 전송이 꺼집니다"
    exit 1
  fi
done

# 테스트 타겟이 없어 빌드(앱 + App Clip)로 컴파일을 확인한다.
echo "🔨 빌드 확인 ($SCHEME, Release)"
xcodebuild build \
  "$PROJECT_FLAG" "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "$DEST" \
  -quiet

echo ""
echo "✅ 게이트 통과 — 배포 가능"
