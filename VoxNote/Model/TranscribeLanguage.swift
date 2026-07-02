import Foundation

struct TranscribeLanguage: Identifiable, Hashable {
    let code: String  // "auto", "en", "ko", etc.
    let label: String  // "Auto", "EN", "KO", etc.
    let displayName: String  // "Auto-detect", "English", "한국어"

    var id: String { code }

    static let supported: [TranscribeLanguage] = [
        TranscribeLanguage(code: "en", label: "EN", displayName: "English"),
        TranscribeLanguage(code: "ko", label: "KO", displayName: "한국어"),
        TranscribeLanguage(code: "ja", label: "JA", displayName: "日本語"),
        TranscribeLanguage(code: "zh", label: "ZH", displayName: "中文"),
        TranscribeLanguage(code: "es", label: "ES", displayName: "Español"),
        TranscribeLanguage(code: "fr", label: "FR", displayName: "Français"),
        TranscribeLanguage(code: "de", label: "DE", displayName: "Deutsch"),
        TranscribeLanguage(code: "pt", label: "PT", displayName: "Português"),
        TranscribeLanguage(code: "it", label: "IT", displayName: "Italiano"),
        TranscribeLanguage(code: "ru", label: "RU", displayName: "Русский"),
        TranscribeLanguage(code: "ar", label: "AR", displayName: "العربية"),
        TranscribeLanguage(code: "vi", label: "VI", displayName: "Tiếng Việt"),
        TranscribeLanguage(code: "th", label: "TH", displayName: "ภาษาไทย"),
    ]

    static func from(code: String) -> TranscribeLanguage {
        supported.first { $0.code == code } ?? supported[0]
    }
}
