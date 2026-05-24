import Foundation
import MLX
import MLXLMCommon
import MLXLLM
import Tokenizers

/// On-device LLM service using MLX Swift.
/// Used for summarization after transcription.
@Observable
@MainActor
class LocalLLMService {
    var isLoaded = false
    var loadStatus = "Not loaded"
    var isGenerating = false

    private var modelContainer: ModelContainer?

    // MARK: - Supported summary languages
    struct SummaryLanguage: Identifiable, Hashable {
        let id: String
        let label: String
        let prompt: String
        let englishName: String
    }

    static let summaryLanguages: [SummaryLanguage] = [
        SummaryLanguage(id: "ko", label: "한국어", prompt: "한국어로", englishName: "Korean"),
        SummaryLanguage(id: "en", label: "English", prompt: "in English", englishName: "English"),
        SummaryLanguage(id: "ja", label: "日本語", prompt: "日本語で", englishName: "Japanese"),
        SummaryLanguage(id: "zh-Hans", label: "中文 (简体)", prompt: "用简体中文", englishName: "Simplified Chinese"),
        SummaryLanguage(id: "zh-Hant", label: "中文 (繁體)", prompt: "用繁體中文", englishName: "Traditional Chinese"),
        SummaryLanguage(id: "es", label: "Español", prompt: "en español", englishName: "Spanish"),
        SummaryLanguage(id: "fr", label: "Français", prompt: "en français", englishName: "French"),
        SummaryLanguage(id: "de", label: "Deutsch", prompt: "auf Deutsch", englishName: "German"),
        SummaryLanguage(id: "pt-BR", label: "Português", prompt: "em português", englishName: "Portuguese"),
        SummaryLanguage(id: "it", label: "Italiano", prompt: "in italiano", englishName: "Italian"),
        SummaryLanguage(id: "ru", label: "Русский", prompt: "на русском", englishName: "Russian"),
        SummaryLanguage(id: "ar", label: "العربية", prompt: "باللغة العربية", englishName: "Arabic"),
        SummaryLanguage(id: "vi", label: "Tiếng Việt", prompt: "bằng tiếng Việt", englishName: "Vietnamese"),
        SummaryLanguage(id: "th", label: "ภาษาไทย", prompt: "ในภาษาไทย", englishName: "Thai"),
    ]

    // MARK: - Load model
    func load() async throws {
        guard !isLoaded else { return }
        loadStatus = "Loading LLM…"

        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

        let config = selectModel()
        modelContainer = try await LLMModelFactory.shared.loadContainer(
            configuration: config
        ) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.loadStatus = "Downloading… \(Int(progress.fractionCompleted * 100))%"
            }
        }

        isLoaded = true
        loadStatus = "LLM ready"
    }

    // MARK: - Summarize
    func summarize(
        text: String,
        language: SummaryLanguage,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard let modelContainer else { throw LLMError.notLoaded }

        isGenerating = true
        defer { isGenerating = false }

        let prompt = """
        Summarize the following transcript in \(language.englishName). \
        Use bullet points (3-5 items). \
        Respond ONLY in \(language.englishName), no other language.

        Transcript:
        \(text)
        """

        let input = UserInput(prompt: .text(prompt))

        try await modelContainer.perform { context in
            let lmInput = try await context.processor.prepare(input: input)
            let _ = try MLXLMCommon.generate(
                input: lmInput,
                parameters: GenerateParameters(maxTokens: 1024, temperature: 0.6),
                context: context
            ) { tokens in
                let decoded = context.tokenizer.decode(tokens: tokens)
                Task { @MainActor in onToken(decoded) }
                return .more
            }
        }
    }

    // MARK: - Unload
    func unload() {
        modelContainer = nil
        isLoaded = false
        loadStatus = "Not loaded"
    }

    // MARK: - Model selection
    private func selectModel() -> ModelConfiguration {
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
#if os(macOS)
        return ramGB >= 16
            ? ModelConfiguration(id: "mlx-community/Qwen2.5-7B-Instruct-4bit")
            : ModelConfiguration(id: "mlx-community/Qwen2.5-3B-Instruct-4bit")
#else
        return ramGB >= 6
            ? ModelConfiguration(id: "mlx-community/Qwen2.5-3B-Instruct-4bit")
            : ModelConfiguration(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit")
#endif
    }
}

enum LLMError: LocalizedError {
    case notLoaded
    var errorDescription: String? { "LLM model is not loaded." }
}
