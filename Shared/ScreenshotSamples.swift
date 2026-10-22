#if DEBUG
import Foundation

/// Sample event and guest names for App Store screenshots (`-moa-screenshots`, `MOA_DEMO_DIR`).
/// Each store language gets names a local user would actually type, so no screenshot mixes languages.
/// DEBUG only: nothing here ships in the release build.
enum ScreenshotSamples {
    struct Set {
        /// Main event, then four past events (newest first).
        let events: [String]
        /// Guests shown as senders; the first one is the App Clip's own name.
        let people: [String]
    }

    static var current: Set {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return all[language] ?? all[String(language.prefix(2))] ?? all["en"]!
    }

    private static let all: [String: Set] = [
        "ko": Set(events: ["가을 캠핑", "지민이 돌잔치", "9월 멘토링 세션", "대학 동기 모임", "제주 가족 여행"],
                  people: ["지민", "서준", "하은", "도윤", "민서", "유나"]),
        "en": Set(events: ["Fall Camping Trip", "Lily's First Birthday", "September Mentoring", "College Reunion", "Family Trip to Hawaii"],
                  people: ["Emma", "Noah", "Olivia", "Liam", "Ava", "Mia"]),
        "en-GB": Set(events: ["Autumn Camping Trip", "Lily's First Birthday", "September Mentoring", "Uni Reunion", "Family Trip to Cornwall"],
                     people: ["Olivia", "Oliver", "Amelia", "George", "Isla", "Harry"]),
        "zh-Hans": Set(events: ["秋季露营", "朵朵的周岁宴", "九月导师交流会", "大学同学聚会", "云南家庭旅行"],
                       people: ["小雨", "子轩", "欣怡", "浩然", "梓涵", "一诺"]),
        "zh-Hant": Set(events: ["秋季露營", "朵朵的週歲宴", "九月導師交流會", "大學同學會", "花蓮家族旅行"],
                       people: ["怡君", "冠宇", "雅婷", "家豪", "詩涵", "承恩"]),
        "ja": Set(events: ["秋のキャンプ", "ひなの1歳の誕生日", "9月のメンタリング", "大学の同窓会", "沖縄家族旅行"],
                  people: ["さくら", "蓮", "陽菜", "湊", "結衣", "悠真"]),
        "ru": Set(events: ["Осенний поход", "Первый день рождения Сони", "Сентябрьская встреча", "Встреча однокурсников", "Семейная поездка в Сочи"],
                  people: ["Анна", "Максим", "Мария", "Артём", "София", "Иван"]),
        "es": Set(events: ["Acampada de otoño", "Primer cumple de Lucía", "Mentoría de septiembre", "Reencuentro de la uni", "Viaje familiar a Mallorca"],
                  people: ["Lucía", "Hugo", "Martina", "Pablo", "Sofía", "Mateo"]),
        "de": Set(events: ["Herbst-Camping", "Mias erster Geburtstag", "Mentoring im September", "Klassentreffen", "Familienurlaub an der Ostsee"],
                  people: ["Lena", "Felix", "Hannah", "Paul", "Emilia", "Jonas"]),
        "fr": Set(events: ["Camping d’automne", "Premier anniversaire de Léa", "Mentorat de septembre", "Retrouvailles de promo", "Vacances en Bretagne"],
                  people: ["Léa", "Hugo", "Chloé", "Louis", "Manon", "Jules"]),
        "it": Set(events: ["Campeggio d'autunno", "Primo compleanno di Giulia", "Mentoring di settembre", "Rimpatriata dell'università", "Vacanza in Sardegna"],
                  people: ["Giulia", "Luca", "Sofia", "Marco", "Aurora", "Matteo"]),
        "pt-BR": Set(events: ["Acampamento de outono", "Primeiro aninho da Alice", "Mentoria de setembro", "Encontro da faculdade", "Viagem em família a Floripa"],
                     people: ["Ana", "Pedro", "Júlia", "Lucas", "Beatriz", "Gabriel"]),
        "th": Set(events: ["แคมป์ปิ้งปลายฝน", "วันเกิดครบ 1 ขวบน้องมะลิ", "มีตติ้งเมนเทอร์เดือนกันยา", "งานเลี้ยงรุ่นมหาลัย", "เที่ยวเชียงใหม่กับครอบครัว"],
                  people: ["มายด์", "ภูมิ", "แพรว", "ต้น", "ฟ้า", "บอส"]),
        "vi": Set(events: ["Cắm trại mùa thu", "Thôi nôi bé Na", "Buổi mentoring tháng 9", "Họp lớp đại học", "Du lịch Đà Lạt cùng gia đình"],
                  people: ["Linh", "Minh", "Trang", "Huy", "Mai", "Nam"]),
        "cs": Set(events: ["Podzimní kempování", "Aniččiny první narozeniny", "Zářijový mentoring", "Sraz spolužáků", "Rodinná dovolená na Šumavě"],
                  people: ["Tereza", "Jakub", "Eliška", "Tomáš", "Anna", "Matěj"]),
        "da": Set(events: ["Efterårscamping", "Idas 1-års fødselsdag", "Mentoring i september", "Studiekammerat-træf", "Familietur til Skagen"],
                  people: ["Ida", "William", "Freja", "Oscar", "Emma", "Noah"]),
        "el": Set(events: ["Φθινοπωρινό κάμπινγκ", "Τα πρώτα γενέθλια της Ελένης", "Mentoring Σεπτεμβρίου", "Συνάντηση συμφοιτητών", "Οικογενειακές διακοπές στη Νάξο"],
                  people: ["Μαρία", "Γιώργος", "Ελένη", "Νίκος", "Σοφία", "Δημήτρης"]),
        "fi": Set(events: ["Syysretki teltalla", "Ellan 1-vuotissynttärit", "Syyskuun mentorointi", "Opiskelukavereiden tapaaminen", "Perhematka Lappiin"],
                  people: ["Aino", "Eino", "Ella", "Leo", "Sofia", "Onni"]),
        "id": Set(events: ["Kemah musim kemarau", "Ulang tahun pertama Aisyah", "Mentoring September", "Reuni kampus", "Liburan keluarga ke Bali"],
                  people: ["Putri", "Rizky", "Aisyah", "Bima", "Nadia", "Dimas"]),
        "nb": Set(events: ["Høsttur med telt", "Noras 1-årsdag", "Mentormøte i september", "Studietreff", "Familietur til Lofoten"],
                  people: ["Nora", "Jakob", "Emma", "Filip", "Ingrid", "Lukas"]),
        "nl": Set(events: ["Herfstkamperen", "Eerste verjaardag van Julia", "Mentoring in september", "Reünie van de studie", "Familieweekend op Texel"],
                  people: ["Julia", "Daan", "Emma", "Sem", "Tess", "Lucas"]),
        "pl": Set(events: ["Jesienny biwak", "Roczek Zosi", "Wrześniowy mentoring", "Zjazd absolwentów", "Rodzinny wyjazd nad morze"],
                  people: ["Zosia", "Jakub", "Hania", "Antek", "Maja", "Kuba"]),
        "sv": Set(events: ["Hösttältning", "Elsas första födelsedag", "Mentorträff i september", "Klassåterträff", "Familjeresa till Gotland"],
                  people: ["Elsa", "William", "Alice", "Hugo", "Maja", "Liam"]),
        "tr": Set(events: ["Sonbahar kampı", "Elif'in ilk doğum günü", "Eylül mentorluk buluşması", "Üniversite buluşması", "Kapadokya aile gezisi"],
                  people: ["Elif", "Yusuf", "Zeynep", "Emir", "Defne", "Kerem"]),
    ]
}
#endif
