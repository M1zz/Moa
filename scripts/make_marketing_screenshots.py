#!/usr/bin/env python3
"""App Store 마케팅 스크린샷: 원본 캡처(docs/screenshots/raw/<언어>/) 위에 헤드라인과 기기 목업을 얹어
docs/screenshots/marketing/<언어>/ 에 1242x2688 로 렌더링한다. 헤드리스 Chrome 을 쓴다.

원본 캡처는 시뮬레이터(iPhone 17 Pro Max)에서 DEBUG 실행 인자로 찍는다:
  호스트  -moa-screenshots [-moa-open-first] [-moa-scroll-to-photos] [-moa-open-photo]
  App Clip  환경변수 MOA_DEMO_DIR=<사진 폴더>
  언어는 -AppleLanguages "(en)" -AppleLocale en_US, 온보딩은 -hasSeenOnboarding YES 로 건너뛴다.

사용법: python3 scripts/make_marketing_screenshots.py
"""
import pathlib, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "screenshots" / "raw"
OUT = ROOT / "docs" / "screenshots" / "marketing"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 1242, 2688

SHOTS = {
    "ko": [
        ("01-qr", "QR 하나로 사진을 모아요", "보여주기만 하면 모두의 사진이 내 iPhone으로"),
        ("02-clip", "앱 설치 없이 바로 보내요", "QR을 찍고 사진을 고르면 끝"),
        ("03-grid", "찍은 시각 그대로 사진 앱에", "원본 화질, 라이브 포토까지 그대로"),
        ("04-viewer", "누가 보냈는지 한눈에", "사진마다 보낸 사람 이름이 붙어요"),
        ("05-list", "행사마다 앨범 하나씩", "받은 사진이 이벤트별로 차곡차곡"),
    ],
    "en": [
        ("01-qr", "One QR Code,<br>Everyone's Photos", "Show it, and the photos come to you"),
        ("02-clip", "Guests Send<br>Without an App", "Scan the code, pick photos, done"),
        ("03-grid", "Right Where They<br>Were Taken", "Full quality, Live Photos included"),
        ("04-viewer", "See Who Sent<br>Each Photo", "Every photo carries a name"),
        ("05-list", "An Album for<br>Every Event", "Everything sorted, event by event"),
    ],
}

PAGE = """<!doctype html><html><head><meta charset="utf-8"><style>
* {{ margin:0; padding:0; box-sizing:border-box; }}
html,body {{ width:{W}px; height:{H}px; overflow:hidden; }}
body {{ background:linear-gradient(180deg,#155d6b 0%,#0f3f4b 100%);
  font-family:-apple-system,"Apple SD Gothic Neo",sans-serif; color:#fff; text-align:center; }}
.headline {{ font-size:{size}px; font-weight:800; letter-spacing:-2px; line-height:1.18; word-break:keep-all; white-space:nowrap; margin:{top}px 60px 0; }}
.sub {{ font-size:52px; font-weight:500; color:rgba(255,255,255,.78); margin-top:40px; padding:0 60px; }}
.phone {{ width:1030px; margin:{gap}px auto 0; background:#111; border-radius:120px; padding:24px;
  box-shadow:0 40px 120px rgba(0,0,0,.35); }}
.phone img {{ width:100%; display:block; border-radius:98px; }}
</style></head><body>
<div class="headline">{headline}</div><div class="sub">{sub}</div>
<div class="phone"><img src="{img}"></div>
</body></html>"""

def render(lang, name, headline, sub):
    two_lines = "<br>" in headline
    html = PAGE.format(W=W, H=H, headline=headline, sub=sub, img=(RAW / lang / f"{name}.png").as_uri(),
                       size=104, top=170 if two_lines else 230,
                       gap=110 if two_lines else 150)
    out = OUT / lang / f"{name}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as f:
        f.write(html)
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    f"--window-size={W},{H}", f"--screenshot={out}", "--allow-file-access-from-files",
                    f"file://{f.name}"], check=True, capture_output=True)
    print(out.relative_to(ROOT))

for lang, shots in SHOTS.items():
    for shot in shots:
        render(lang, *shot)
