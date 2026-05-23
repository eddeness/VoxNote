import Foundation
import Translation

/// Supported translation target languages.
/// Source is always auto-detected by Apple Translation API.
struct TranslationLanguage: Identifiable, Hashable {
    let id: String       // BCP-47 code
    let label: String

    var locale: Locale.Language { Locale.Language(identifier: id) }

    static let supported: [TranslationLanguage] = [
        TranslationLanguage(id: "ko", label: "한국어"),
        TranslationLanguage(id: "en", label: "English"),
        TranslationLanguage(id: "ja", label: "日本語"),
        TranslationLanguage(id: "zh-Hans", label: "中文 (简体)"),
        TranslationLanguage(id: "zh-Hant", label: "中文 (繁體)"),
        TranslationLanguage(id: "es", label: "Español"),
        TranslationLanguage(id: "fr", label: "Français"),
        TranslationLanguage(id: "de", label: "Deutsch"),
        TranslationLanguage(id: "pt-BR", label: "Português"),
        TranslationLanguage(id: "it", label: "Italiano"),
        TranslationLanguage(id: "ru", label: "Русский"),
        TranslationLanguage(id: "ar", label: "العربية"),
        TranslationLanguage(id: "vi", label: "Tiếng Việt"),
        TranslationLanguage(id: "th", label: "ภาษาไทย"),
    ]
}
