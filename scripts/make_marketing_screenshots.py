#!/usr/bin/env python3
"""App Store 마케팅 스크린샷: 원본 캡처(docs/screenshots/raw/<언어>/) 위에 헤드라인과 기기 목업을 얹어
docs/screenshots/marketing/<언어>/ 에 1242x2688 로 렌더링한다. 헤드리스 Chrome 을 쓴다.

원본 캡처는 시뮬레이터(iPhone 17 Pro Max)에서 DEBUG 실행 인자로 찍는다:
  호스트  -moa-screenshots [-moa-open-first] [-moa-scroll-to-photos] [-moa-open-photo]
  App Clip  환경변수 MOA_DEMO_DIR=<사진 폴더>
  언어는 -AppleLanguages "(en)" -AppleLocale en_US, 온보딩은 -hasSeenOnboarding YES 로 건너뛴다.

사용법: python3 scripts/make_marketing_screenshots.py [언어 ...]     (없으면 전부)
"""
import pathlib, subprocess, sys, tempfile

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
    "en-GB": [
        ("01-qr", "One QR Code,<br>Everyone's Photos", "Show it and the photos come to you"),
        ("02-clip", "Guests Send<br>Without an App", "Scan the code, choose photos, done"),
        ("03-grid", "Right Where They<br>Were Taken", "Full quality, Live Photos and all"),
        ("04-viewer", "See Who Sent<br>Each Photo", "Every photo carries a name"),
        ("05-list", "An Album for<br>Every Event", "Everything neatly organised by event"),
    ],
    "zh-Hans": [
        ("01-qr", "一个二维码<br>收齐大家的照片", "亮出二维码，照片就传到你的 iPhone"),
        ("02-clip", "无需安装 App<br>直接发送", "扫码、选照片，完成"),
        ("03-grid", "按拍摄时间<br>存入“照片”", "原画质，实况照片也原样保留"),
        ("04-viewer", "谁发的<br>一目了然", "每张照片都带有发送者的名字"),
        ("05-list", "每场活动<br>一个相册", "收到的照片按活动整齐归类"),
    ],
    "zh-Hant": [
        ("01-qr", "一個 QR Code<br>收齊大家的照片", "出示 QR Code，照片就傳到你的 iPhone"),
        ("02-clip", "不必安裝 App<br>直接傳送", "掃描、選照片，完成"),
        ("03-grid", "依拍攝時間<br>存入「照片」", "原畫質，實況照片也原樣保留"),
        ("04-viewer", "誰傳的<br>一目了然", "每張照片都附上傳送者的名字"),
        ("05-list", "每場活動<br>一個相簿", "收到的照片依活動整齊歸類"),
    ],
    "ja": [
        ("01-qr", "QR一つで<br>写真が集まる", "見せるだけでみんなの写真が手元のiPhoneに"),
        ("02-clip", "アプリなしで<br>そのまま送れる", "QRを読み取って写真を選ぶだけ"),
        ("03-grid", "撮影した日時のまま<br>写真アプリへ", "オリジナル画質、ライブフォトもそのまま"),
        ("04-viewer", "誰が送ったか<br>ひと目でわかる", "写真ごとに送った人の名前が付きます"),
        ("05-list", "イベントごとに<br>アルバムを作成", "届いた写真がきれいに整理されます"),
    ],
    "ru": [
        ("01-qr", "Один QR-код —<br>фото всех гостей", "Покажите его, и фото придут к вам"),
        ("02-clip", "Гости отправляют<br>без приложения", "Отсканировать, выбрать фото — и всё"),
        ("03-grid", "Фото на дате<br>съёмки", "Оригинальное качество, вместе с Live Photos"),
        ("04-viewer", "Видно, кто<br>отправил", "У каждого фото есть имя отправителя"),
        ("05-list", "Альбом для<br>каждого события", "Всё разложено по событиям"),
    ],
    "es": [
        ("01-qr", "Un solo QR,<br>las fotos de todos", "Muéstralo y las fotos llegan a ti"),
        ("02-clip", "Envían sin<br>instalar nada", "Escanean, eligen fotos y listo"),
        ("03-grid", "Cada foto en<br>su fecha", "Calidad original, con Live Photos incluidas"),
        ("04-viewer", "Quién envió<br>cada foto", "Cada foto lleva un nombre"),
        ("05-list", "Un álbum por<br>cada evento", "Todo ordenado, evento a evento"),
    ],
    "de": [
        ("01-qr", "Ein QR-Code,<br>alle Fotos", "Zeigen, und die Fotos kommen zu dir"),
        ("02-clip", "Senden ganz<br>ohne App", "Scannen, Fotos wählen, fertig"),
        ("03-grid", "Genau zum<br>Aufnahmedatum", "Originalqualität, auch Live Photos"),
        ("04-viewer", "Sieh, wer<br>was gesendet hat", "Jedes Foto trägt einen Namen"),
        ("05-list", "Ein Album für<br>jedes Event", "Alles sortiert, Event für Event"),
    ],
    "fr": [
        ("01-qr", "Un QR code,<br>les photos de tous", "Montrez-le, les photos arrivent chez vous"),
        ("02-clip", "Envoi sans<br>aucune app", "Scanner, choisir, c’est fini"),
        ("03-grid", "Chaque photo<br>à sa date", "Qualité d’origine, Live Photos comprises"),
        ("04-viewer", "Qui a envoyé<br>quelle photo", "Chaque photo porte un nom"),
        ("05-list", "Un album pour<br>chaque événement", "Tout est classé, événement par événement"),
    ],
    "it": [
        ("01-qr", "Un solo QR,<br>le foto di tutti", "Mostralo e le foto arrivano da te"),
        ("02-clip", "Si invia<br>senza app", "Inquadra il QR, scegli le foto, fatto"),
        ("03-grid", "Alla data<br>in cui sono state scattate", "Qualità originale, Live Photos incluse"),
        ("04-viewer", "Chi ha inviato<br>ogni foto", "Ogni foto porta il nome di chi l'ha inviata"),
        ("05-list", "Un album<br>per ogni evento", "Tutto in ordine, evento per evento"),
    ],
    "pt-BR": [
        ("01-qr", "Um só QR,<br>as fotos de todos", "Mostre e as fotos chegam até você"),
        ("02-clip", "Convidados enviam<br>sem app", "Escaneie, escolha as fotos e pronto"),
        ("03-grid", "Cada foto na data<br>em que foi tirada", "Qualidade total, com Live Photos"),
        ("04-viewer", "Veja quem enviou<br>cada foto", "Cada foto leva o nome de quem enviou"),
        ("05-list", "Um álbum<br>para cada evento", "Tudo organizado, evento por evento"),
    ],
    "th": [
        ("01-qr", "QR เดียว<br>ได้รูปของทุกคน", "แค่แสดง รูปก็มาหาคุณ"),
        ("02-clip", "แขกส่งได้<br>โดยไม่ต้องโหลดแอป", "สแกนโค้ด เลือกรูป เสร็จเลย"),
        ("03-grid", "อยู่ตรงวันที่<br>ถ่ายจริง", "คุณภาพเต็ม รวมถึง Live Photos"),
        ("04-viewer", "ดูได้ว่าใคร<br>ส่งรูปไหนมา", "ทุกรูปมีชื่อผู้ส่งกำกับ"),
        ("05-list", "หนึ่งอีเวนต์<br>หนึ่งอัลบั้ม", "จัดเรียบร้อย แยกตามอีเวนต์"),
    ],
    "vi": [
        ("01-qr", "Một mã QR,<br>ảnh của mọi người", "Hiện mã lên, ảnh sẽ về với bạn"),
        ("02-clip", "Khách gửi ảnh<br>không cần app", "Quét mã, chọn ảnh, xong"),
        ("03-grid", "Nằm đúng ngày<br>chụp", "Chất lượng gốc, cả Live Photos"),
        ("04-viewer", "Biết ai gửi<br>từng bức ảnh", "Mỗi ảnh đều kèm tên người gửi"),
        ("05-list", "Mỗi sự kiện<br>một album", "Mọi thứ gọn gàng theo từng sự kiện"),
    ],
    "cs": [
        ("01-qr", "Jeden QR kód,<br>fotky všech", "Ukažte ho a fotky přijdou k vám"),
        ("02-clip", "Hosté pošlou<br>bez aplikace", "Naskenují, vyberou fotky a hotovo"),
        ("03-grid", "Přesně tam,<br>kde vznikly", "Plná kvalita, včetně Live Photos"),
        ("04-viewer", "Vidíte, kdo<br>co poslal", "U každé fotky je jméno"),
        ("05-list", "Album pro<br>každou akci", "Vše roztříděné podle akcí"),
    ],
    "da": [
        ("01-qr", "Én QR-kode,<br>alle billederne", "Vis den, så kommer billederne til dig"),
        ("02-clip", "Gæster sender<br>uden en app", "Scan koden, vælg billeder, færdig"),
        ("03-grid", "Præcis hvor de<br>blev taget", "Fuld kvalitet, også Live Photos"),
        ("04-viewer", "Se hvem der<br>sendte hvad", "Hvert billede har et navn"),
        ("05-list", "Et album til<br>hver begivenhed", "Alt sorteret, begivenhed for begivenhed"),
    ],
    "el": [
        ("01-qr", "Ένα QR,<br>οι φωτογραφίες όλων", "Δείξτε το και οι φωτογραφίες έρχονται σε εσάς"),
        ("02-clip", "Στέλνουν οι καλεσμένοι<br>χωρίς εφαρμογή", "Σαρώστε, επιλέξτε φωτογραφίες, έτοιμο"),
        ("03-grid", "Ακριβώς εκεί<br>που τραβήχτηκαν", "Πλήρης ποιότητα, και Live Photos"),
        ("04-viewer", "Δείτε ποιος<br>έστειλε τι", "Κάθε φωτογραφία έχει ένα όνομα"),
        ("05-list", "Ένα άλμπουμ για<br>κάθε εκδήλωση", "Όλα ταξινομημένα, εκδήλωση προς εκδήλωση"),
    ],
    "fi": [
        ("01-qr", "Yksi QR-koodi,<br>kaikkien kuvat", "Näytä se, ja kuvat tulevat sinulle"),
        ("02-clip", "Vieraat lähettävät<br>ilman sovellusta", "Skannaa koodi, valitse kuvat, valmis"),
        ("03-grid", "Siellä, minne<br>ne kuuluvat", "Täysi laatu, myös Live Photos"),
        ("04-viewer", "Näet, kuka<br>lähetti minkä", "Jokaisessa kuvassa on nimi"),
        ("05-list", "Albumi jokaiselle<br>tapahtumalle", "Kaikki järjestyksessä tapahtuma kerrallaan"),
    ],
    "id": [
        ("01-qr", "Satu QR,<br>semua foto terkumpul", "Tunjukkan, foto langsung masuk ke iPhone-mu"),
        ("02-clip", "Tamu kirim<br>tanpa app", "Pindai kode, pilih foto, selesai"),
        ("03-grid", "Tepat di tanggal<br>foto diambil", "Kualitas penuh, termasuk Live Photo"),
        ("04-viewer", "Lihat siapa<br>pengirim tiap foto", "Setiap foto membawa nama pengirim"),
        ("05-list", "Satu album<br>untuk tiap acara", "Semua tertata, acara demi acara"),
    ],
    "nb": [
        ("01-qr", "Én QR-kode,<br>alles bilder", "Vis den, så kommer bildene til deg"),
        ("02-clip", "Gjester sender<br>uten app", "Skann koden, velg bilder, ferdig"),
        ("03-grid", "Akkurat der de<br>ble tatt", "Full kvalitet, også Live Photos"),
        ("04-viewer", "Se hvem som<br>sendte hva", "Hvert bilde har et navn"),
        ("05-list", "Ett album per<br>arrangement", "Alt ordnet, arrangement for arrangement"),
    ],
    "nl": [
        ("01-qr", "Eén QR-code,<br>alle foto's", "Laat hem zien, de foto's komen naar je toe"),
        ("02-clip", "Gasten sturen<br>zonder app", "Scan de code, kies foto's, klaar"),
        ("03-grid", "Precies waar ze<br>zijn gemaakt", "Volle kwaliteit, ook Live Photos"),
        ("04-viewer", "Zie wie elke<br>foto stuurde", "Elke foto draagt een naam"),
        ("05-list", "Een album voor<br>elk evenement", "Alles netjes geordend per evenement"),
    ],
    "pl": [
        ("01-qr", "Jeden kod QR,<br>zdjęcia od wszystkich", "Pokaż go, a zdjęcia same do Ciebie dotrą"),
        ("02-clip", "Goście wysyłają<br>bez aplikacji", "Zeskanuj kod, wybierz zdjęcia i gotowe"),
        ("03-grid", "Na dacie, kiedy<br>zostały zrobione", "Pełna jakość, także Live Photos"),
        ("04-viewer", "Widać, kto<br>wysłał zdjęcie", "Każde zdjęcie ma imię autora"),
        ("05-list", "Album dla każdego<br>wydarzenia", "Wszystko ułożone wydarzenie po wydarzeniu"),
    ],
    "sv": [
        ("01-qr", "En QR-kod,<br>allas bilder", "Visa den så kommer bilderna till dig"),
        ("02-clip", "Gäster skickar<br>utan app", "Skanna koden, välj bilder, klart"),
        ("03-grid", "Precis där de<br>togs i tiden", "Full kvalitet, Live Photos inkluderade"),
        ("04-viewer", "Se vem som<br>skickat bilden", "Varje bild får ett namn"),
        ("05-list", "Ett album för<br>varje event", "Allt ordnat, event för event"),
    ],
    "tr": [
        ("01-qr", "Tek QR kod,<br>herkesin fotoğrafları", "Göster, fotoğraflar sana gelsin"),
        ("02-clip", "Misafirler uygulamasız<br>gönderir", "Kodu okut, fotoğrafları seç, bitti"),
        ("03-grid", "Çekildikleri<br>yere yerleşir", "Tam kalite, Live Photos dahil"),
        ("04-viewer", "Kimin gönderdiği<br>görünür", "Her fotoğrafta bir isim var"),
        ("05-list", "Her etkinliğe<br>bir albüm", "Her şey etkinlik etkinlik düzenli"),
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
    if len(sys.argv) > 1 and lang not in sys.argv[1:]:
        continue
    for shot in shots:
        render(lang, *shot)
