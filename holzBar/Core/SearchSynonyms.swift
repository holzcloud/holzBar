//
//  SearchSynonyms.swift
//  holzBar
//

import Foundation

/// Short names for the items of the menu bar: typing "bt" finds Bluetooth, "wlan" finds Wi-Fi,
/// "dnd" finds Focus.
///
/// An entry maps short names (aliases) to the full names the item can carry, in English and in
/// the languages holzBar speaks, because the system items carry the Mac's language ("Akku",
/// "Batterie", "バッテリー"). The search matches the typed text as before and, when it is an
/// alias, also each full name; the full names rank a little below a direct hit.
nonisolated enum SearchSynonyms {
    /// One entry of the table.
    nonisolated struct Entry {
        /// The short names, written without case, accents or punctuation.
        let aliases: [String]
        /// The full names of the item.
        let names: [String]
    }

    /// The table. Aliases are short; each alias belongs to one entry.
    static let entries: [Entry] = [
        Entry(aliases: ["bt"], names: ["Bluetooth"]),
        Entry(aliases: ["wifi", "wf", "wlan", "wl"], names: ["Wi-Fi", "WLAN"]),
        Entry(
            aliases: ["bat", "batt", "pwr", "power", "akku", "charge"],
            names: [
                "Battery", "Batterie", "Akku", "Batteria", "Batería", "Bateria", "Аккумулятор", "Батарея",
                "バッテリー", "电池", "배터리",
            ]
        ),
        Entry(
            aliases: ["vol", "volume", "snd", "audio", "mute"],
            names: [
                "Sound", "Volume", "Ton", "Lautstärke", "Son", "Suono", "Sonido", "Som", "Звук",
                "サウンド", "声音", "사운드",
            ]
        ),
        Entry(
            aliases: ["dnd", "focus", "fokus"],
            names: [
                "Focus", "Do Not Disturb", "Fokus", "Nicht stören", "Concentration", "Ne pas déranger",
                "Concentrazione", "Concentración", "Foco", "Фокусирование", "集中モード", "专注模式", "집중 모드",
            ]
        ),
        Entry(
            aliases: ["cc", "cctr", "controls"],
            names: [
                "Control Center", "Control Centre", "Kontrollzentrum", "Centre de contrôle",
                "Centro di controllo", "Centro de control", "Central de Controle", "Пункт управления",
                "コントロールセンター", "控制中心", "제어 센터",
            ]
        ),
        Entry(
            aliases: ["clk", "time", "date", "uhr"],
            names: ["Clock", "Uhr", "Horloge", "Orologio", "Reloj", "Relógio", "Часы", "時計", "时钟", "시계"]
        ),
        Entry(aliases: ["tm"], names: ["Time Machine"]),
        Entry(
            aliases: ["kb", "kbd", "keys", "lang", "input"],
            names: [
                "Input", "Keyboard", "Text Input", "Eingabe", "Tastatur", "Clavier", "Tastiera", "Teclado",
                "Ввод", "入力", "输入", "입력",
            ]
        ),
        Entry(aliases: ["spot", "sl"], names: ["Spotlight"]),
        Entry(
            aliases: ["airplay", "mirror", "cast"],
            names: [
                "Screen Mirroring", "AirPlay", "Bildschirmsynchronisierung", "Recopie de l'écran",
                "Mirroring schermo", "Duplicar pantalla", "Espelhamento de Tela", "Повтор экрана",
                "画面ミラーリング", "屏幕镜像", "화면 미러링",
            ]
        ),
        Entry(
            aliases: ["nc", "notif", "notifs"],
            names: [
                "Notification Center", "Notification Centre", "Mitteilungszentrale", "Centre de notifications",
                "Centro notifiche", "Centro de notificaciones", "Central de Notificações",
                "Центр уведомлений", "通知センター", "通知中心", "알림 센터",
            ]
        ),
        Entry(
            aliases: ["bright", "brt", "screen"],
            names: [
                "Display", "Brightness", "Bildschirm", "Helligkeit", "Écran", "Luminosité", "Schermo",
                "Luminosità", "Pantalla", "Brillo", "Tela", "Brilho", "Дисплей", "Яркость",
                "ディスプレイ", "显示器", "디스플레이",
            ]
        ),
        Entry(
            aliases: ["loc", "gps", "geo"],
            names: [
                "Location", "Location Services", "Standort", "Ortungsdienste", "Localisation", "Posizione",
                "Ubicación", "Localização", "Геопозиция", "位置情報", "定位", "위치",
            ]
        ),
        Entry(
            aliases: ["mic"],
            names: [
                "Microphone", "Mikrofon", "Microfono", "Micrófono", "Microfone", "Микрофон", "マイク",
                "麦克风", "마이크",
            ]
        ),
        Entry(
            aliases: ["cam"],
            names: [
                "Camera", "Kamera", "Caméra", "Fotocamera", "Cámara", "Câmera", "Камера", "カメラ",
                "摄像头", "카메라",
            ]
        ),
        Entry(
            aliases: ["np", "music", "media"],
            names: [
                "Now Playing", "Music", "Musik", "Musique", "Musica", "Música", "Музыка", "ミュージック",
                "音乐", "음악",
            ]
        ),
        Entry(
            aliases: ["a11y", "ax"],
            names: [
                "Accessibility", "Bedienungshilfen", "Accessibilité", "Accessibilità", "Accesibilidad",
                "Acessibilidade", "Универсальный доступ", "アクセシビリティ", "辅助功能", "손쉬운 사용",
            ]
        ),
        Entry(aliases: ["drop"], names: ["AirDrop"]),
        Entry(
            aliases: ["fus", "usr"],
            names: [
                "User", "Fast User Switching", "Benutzer", "Utilisateur", "Utente", "Usuario", "Usuário",
                "Пользователь", "ユーザ", "用户", "사용자",
            ]
        ),
    ]

    /// The longest alias: the aliases are short names, not words.
    static let longestAlias = 8

    /// The text without case, accents, spaces and punctuation, the form aliases are compared in.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// The full names a typed text stands for, or none when it is no alias.
    ///
    /// The names come without punctuation ("Wi-Fi" is "WiFi"), because the system writes it with
    /// a non-breaking hyphen the search does not need to match.
    static func expansions(for query: String) -> [String] {
        let key = normalized(query)
        guard !key.isEmpty, key.count <= longestAlias else {
            return []
        }
        return entries
            .filter { $0.aliases.contains(key) }
            .flatMap(\.names)
            .map { $0.filter { $0.isLetter || $0.isNumber || $0.isWhitespace } }
    }
}
