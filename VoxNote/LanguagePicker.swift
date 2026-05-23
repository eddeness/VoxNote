import SwiftUI

struct LanguagePicker: View {

    @Binding var selectedCode: String

    private let languages: [(code: String, label: String)] = [
        ("ko", "한국어"),
        ("en", "English"),
        ("ja", "日本語"),
        ("zh", "中文"),
        ("es", "Español"),
        ("fr", "Français"),
        ("de", "Deutsch"),
    ]

    var body: some View {
        Picker("Language", selection: $selectedCode) {
            ForEach(languages, id: \.code) { lang in
                Text(lang.label).tag(lang.code)
            }
        }
        .pickerStyle(.menu)
    }
}
