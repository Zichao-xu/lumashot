import Foundation
import NaturalLanguage
import Combine
import SwiftUI
import Security
@preconcurrency import Translation

enum TranslationProvider: String {
    case apple = "apple"
    case google = "google"
    case ai = "ai"
    case local = "local"
}

enum TranslationService {

    // MARK: - Provider

    static var provider: TranslationProvider {
        get {
            if let raw = UserDefaults.standard.string(forKey: "translationProvider"),
               let p = TranslationProvider(rawValue: raw) { return p }
            return .google  // Google by default — Apple requires language pack downloads
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "translationProvider") }
    }

    /// Whether Apple Translation is available on this system.
    static var appleTranslationAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    /// Cached Apple language availability — populated on first check,
    /// reused instantly for subsequent popover opens.
    private static var cachedAppleAvailability: [String: Bool]?

    // MARK: - Target language

    static let automaticTargetLanguageCode = "auto"

    static var targetLanguage: String {
        get {
            let value = UserDefaults.standard.string(forKey: "translateTargetLang") ?? automaticTargetLanguageCode
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? automaticTargetLanguageCode : value
        }
        set { UserDefaults.standard.set(newValue, forKey: "translateTargetLang") }
    }

    // MARK: - AI translation settings

    static let defaultAIBaseURL = "https://api.openai.com/v1"
    static let defaultAIModel = "gpt-4o-mini"
    static var defaultAIPrompt: String {
        L("Translate accurately and naturally. Preserve names, numbers, code, URLs, markdown, and original line intent. Return only the translation.")
    }

    static var aiBaseURL: String {
        get {
            let value = UserDefaults.standard.string(forKey: "aiTranslationBaseURL") ?? ""
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultAIBaseURL : value
        }
        set { UserDefaults.standard.set(newValue, forKey: "aiTranslationBaseURL") }
    }

    static var aiAPIKey: String {
        get {
            if let key = KeychainStore.read(service: keychainService, account: "aiTranslationAPIKey") {
                return key
            }

            let legacyKey = UserDefaults.standard.string(forKey: "aiTranslationAPIKey") ?? ""
            if !legacyKey.isEmpty {
                KeychainStore.write(legacyKey, service: keychainService, account: "aiTranslationAPIKey")
                UserDefaults.standard.removeObject(forKey: "aiTranslationAPIKey")
            }
            return legacyKey
        }
        set {
            KeychainStore.write(newValue, service: keychainService, account: "aiTranslationAPIKey")
            UserDefaults.standard.removeObject(forKey: "aiTranslationAPIKey")
        }
    }

    static var aiModel: String {
        get {
            let value = UserDefaults.standard.string(forKey: "aiTranslationModel") ?? ""
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultAIModel : value
        }
        set { UserDefaults.standard.set(newValue, forKey: "aiTranslationModel") }
    }

    static var aiPrompt: String {
        get {
            let value = UserDefaults.standard.string(forKey: "aiTranslationPrompt") ?? ""
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultAIPrompt : value
        }
        set { UserDefaults.standard.set(newValue, forKey: "aiTranslationPrompt") }
    }

    private static let keychainService = "com.sw33tlie.macshot.translation"

    static let availableLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("ru", "Russian"),
        ("zh-CN", "Chinese (Simplified)"),
        ("zh-TW", "Chinese (Traditional)"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("ar", "Arabic"),
        ("tr", "Turkish"),
        ("sv", "Swedish"),
        ("da", "Danish"),
        ("fi", "Finnish"),
        ("nb", "Norwegian"),
        ("uk", "Ukrainian"),
        ("cs", "Czech"),
        ("ro", "Romanian"),
        ("hu", "Hungarian"),
        ("sk", "Slovak"),
        ("bg", "Bulgarian"),
        ("hr", "Croatian"),
        ("id", "Indonesian"),
        ("hi", "Hindi"),
        ("th", "Thai"),
        ("vi", "Vietnamese"),
    ]

    static var targetLanguageOptions: [(code: String, name: String)] {
        [(automaticTargetLanguageCode, L("Auto"))] + availableLanguages
    }

    static func resolvedTargetLanguage(for texts: [String], requestedTargetLang: String) -> String {
        requestedTargetLang == automaticTargetLanguageCode ? automaticTargetLanguage(for: texts) : requestedTargetLang
    }

    static func automaticTargetLanguage(for texts: [String]) -> String {
        let text = texts.joined(separator: "\n")
        let dominant = dominantLanguageFamily(for: text)

        // Auto mode uses the dominant visible language. Chinese-dominant text goes
        // to English; any foreign-dominant text goes to Chinese.
        if dominant == .chinese {
            return "en"
        }
        return "zh-CN"
    }

    private enum AutoLanguageFamily {
        case chinese
        case english
        case japanese
        case foreign
    }

    nonisolated private static func dominantLanguageFamily(for text: String) -> AutoLanguageFamily? {
        var chineseScore = 0
        var englishScore = 0
        var japaneseScore = 0
        var foreignScore = 0
        var currentRun: [Unicode.Scalar] = []

        func addScore(_ family: AutoLanguageFamily) {
            switch family {
            case .chinese:
                chineseScore += 1
            case .english:
                englishScore += 1
            case .japanese:
                japaneseScore += 1
            case .foreign:
                foreignScore += 1
            }
        }

        func flushRun() {
            guard !currentRun.isEmpty else { return }
            let hasKana = currentRun.contains(where: isJapaneseKanaScalar)

            for scalar in currentRun {
                if hasKana && isChineseScalar(scalar) {
                    addScore(.japanese)
                } else if isJapaneseKanaScalar(scalar) {
                    addScore(.japanese)
                } else if isChineseScalar(scalar) {
                    addScore(.chinese)
                } else if isLatinScalar(scalar) {
                    addScore(.english)
                } else if isLetterScalar(scalar) {
                    addScore(.foreign)
                }
            }
            currentRun.removeAll(keepingCapacity: true)
        }

        for scalar in text.unicodeScalars {
            if isLanguageScalar(scalar) {
                currentRun.append(scalar)
            } else {
                flushRun()
            }
        }
        flushRun()

        let scores: [(family: AutoLanguageFamily, score: Int)] = [
            (.chinese, chineseScore),
            (.english, englishScore),
            (.japanese, japaneseScore),
            (.foreign, foreignScore),
        ].filter { $0.score > 0 }

        return scores.max { lhs, rhs in
            if lhs.score == rhs.score {
                return languageTiePriority(lhs.family) < languageTiePriority(rhs.family)
            }
            return lhs.score < rhs.score
        }?.family
    }

    nonisolated private static func languageTiePriority(_ family: AutoLanguageFamily) -> Int {
        switch family {
        case .chinese: return 4
        case .english: return 3
        case .japanese: return 2
        case .foreign: return 1
        }
    }

    nonisolated private static func isChineseScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0x20000...0x2A6DF,
             0x2A700...0x2B73F,
             0x2B740...0x2B81F,
             0x2B820...0x2CEAF,
             0x2CEB0...0x2EBEF,
             0x30000...0x3134F:
            return true
        default:
            return false
        }
    }

    nonisolated private static func isJapaneseKanaScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x309F,  // Hiragana
             0x30A0...0x30FF,  // Katakana
             0x31F0...0x31FF,  // Katakana Phonetic Extensions
             0xFF66...0xFF9D:  // Halfwidth Katakana
            return true
        default:
            return false
        }
    }

    nonisolated private static func isLatinScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0041...0x005A,
             0x0061...0x007A,
             0x00C0...0x024F,
             0x1E00...0x1EFF:
            return true
        default:
            return false
        }
    }

    nonisolated private static func isLanguageScalar(_ scalar: Unicode.Scalar) -> Bool {
        isChineseScalar(scalar) || isJapaneseKanaScalar(scalar) || isLetterScalar(scalar)
    }

    nonisolated private static func isLetterScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return false
        }
    }

    /// Check which languages are available for Apple Translation.
    /// Returns a dict of language code → installed status.
    @available(macOS 15.0, *)
    static func checkAppleLanguageAvailability(completion: @escaping ([String: Bool]) -> Void) {
        // Return cache immediately if available
        if let cached = cachedAppleAvailability {
            completion(cached)
            return
        }

        Task {
            let availability = LanguageAvailability()
            let allLocales = availableLanguages.map { (code: $0.code, locale: appleLocale(from: $0.code)) }

            // Find the first installed pair to get a known-installed "probe" language.
            // Then check all remaining languages against that probe — O(n) instead of O(n²).
            var installed: [String: Bool] = [:]
            var probeLocale: Locale.Language?
            var probeCode: String?

            // Quick scan: find any installed pair
            outerLoop: for (i, lang) in allLocales.enumerated() {
                for other in allLocales[(i+1)...] {
                    let status = await availability.status(from: lang.locale, to: other.locale)
                    if status == .installed {
                        installed[lang.code] = true
                        installed[other.code] = true
                        probeLocale = lang.locale
                        probeCode = lang.code
                        break outerLoop
                    }
                }
            }

            // Check remaining languages against the probe
            if let probe = probeLocale, let pc = probeCode {
                for lang in allLocales where installed[lang.code] != true {
                    // Check both directions since the probe→lang direction
                    // might not be valid but lang→probe could be
                    let toStatus = await availability.status(from: probe, to: lang.locale)
                    let fromStatus = await availability.status(from: lang.locale, to: probe)
                    installed[lang.code] = (toStatus == .installed || fromStatus == .installed)
                }
                // Ensure the probe itself is marked
                installed[pc] = true
            }

            // Any language not checked stays false
            for lang in allLocales where installed[lang.code] == nil {
                installed[lang.code] = false
            }

            await MainActor.run {
                // Only cache if we found at least one installed language.
                // If the Translation framework wasn't ready (e.g. right after
                // launch), all languages come back as not-installed — don't
                // cache that or the popover stays empty for the whole session.
                if installed.values.contains(true) {
                    cachedAppleAvailability = installed
                }
                completion(installed)
            }
        }
    }

    // MARK: - Translate a batch of strings (auto-detect source)

    /// Translates multiple strings using the selected provider.
    /// Calls completion on the main queue.
    static func translateBatch(
        texts: [String],
        targetLang: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard !texts.isEmpty else {
            completion(.success([]))
            return
        }

        let resolvedTargetLang = resolvedTargetLanguage(for: texts, requestedTargetLang: targetLang)

        if #available(macOS 15.0, *), provider == .apple {
            translateBatchApple(texts: texts, targetLang: resolvedTargetLang, completion: completion)
        } else if provider == .ai {
            translateBatchAI(texts: texts, targetLang: resolvedTargetLang, completion: completion)
        } else if provider == .local {
            LocalModelService.shared.translateBatch(texts: texts, targetLang: resolvedTargetLang, completion: completion)
        } else {
            translateBatchGoogle(texts: texts, targetLang: resolvedTargetLang, completion: completion)
        }
    }

    // MARK: - Google Translate (unofficial endpoint)

    private static func translateBatchGoogle(
        texts: [String],
        targetLang: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        var results = Array(repeating: "", count: texts.count)
        let group = DispatchGroup()
        var firstError: Error?
        let lock = NSLock()

        for (i, text) in texts.enumerated() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                results[i] = text
                continue
            }
            group.enter()
            translateOneGoogle(text: trimmed, targetLang: targetLang) { result in
                lock.lock()
                switch result {
                case .success(let translated):
                    results[i] = translated
                case .failure(let error):
                    if firstError == nil { firstError = error }
                    results[i] = ""
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let error = firstError {
                completion(.failure(error))
            } else {
                completion(.success(results))
            }
        }
    }

    private static func translateOneGoogle(
        text: String,
        targetLang: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl",     value: "auto"),
            URLQueryItem(name: "tl",     value: targetLang),
            URLQueryItem(name: "dt",     value: "t"),
            URLQueryItem(name: "q",      value: text),
        ]
        guard let url = components.url else {
            completion(.failure(TranslationError.badURL))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(TranslationError.noData))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  let outer = json.first as? [[Any]] else {
                completion(.failure(TranslationError.parseError))
                return
            }
            let translated = outer.compactMap { $0.first as? String }.joined()
            guard !translated.isEmpty else {
                completion(.failure(TranslationError.emptyResult))
                return
            }
            completion(.success(translated))
        }.resume()
    }

    // MARK: - AI Translation (OpenAI-compatible chat completions)

    private static func translateBatchAI(
        texts: [String],
        targetLang: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        translateBatchOpenAICompatible(
            texts: texts,
            targetLang: targetLang,
            baseURL: aiBaseURL,
            apiKey: aiAPIKey,
            model: aiModel,
            prompt: aiPrompt,
            completion: completion
        )
    }

    static func translateBatchOpenAICompatible(
        texts: [String],
        targetLang: String,
        baseURL: String,
        apiKey: String,
        model: String,
        prompt: String,
        maxTokens: Int? = nil,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            DispatchQueue.main.async {
                completion(.failure(TranslationError.aiTranslation(L("AI translation model is not configured."))))
            }
            return
        }

        guard let url = aiChatCompletionsURL(from: baseURL) else {
            DispatchQueue.main.async {
                completion(.failure(TranslationError.aiTranslation(L("Invalid AI translation base URL."))))
            }
            return
        }

        let targetName = availableLanguages.first(where: { $0.code == targetLang })?.name ?? targetLang
        let userPayload: [String: Any] = [
            "target_language_code": targetLang,
            "target_language_name": targetName,
            "texts": texts,
        ]
        let userData = (try? JSONSerialization.data(withJSONObject: userPayload, options: [.prettyPrinted])) ?? Data()
        let userContent = String(data: userData, encoding: .utf8) ?? "{\"texts\":[]}"

        let systemPrompt = """
        \(prompt)

        You are translating OCR output to \(targetName) (\(targetLang)).
        The user will send JSON with a "texts" array.
        Return only valid JSON in this exact shape:
        {"translations":["first translation","second translation"]}
        The translations array must contain exactly \(texts.count) strings in the same order.
        Empty input strings must produce empty output strings.
        """

        var body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent],
            ],
        ]
        if let maxTokens {
            body["max_tokens"] = maxTokens
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            DispatchQueue.main.async {
                completion(.failure(TranslationError.aiTranslation(L("Could not encode AI translation request."))))
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(TranslationError.noData)) }
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let message = Self.aiErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                DispatchQueue.main.async {
                    let format = L("AI translation failed (%d): %@")
                    completion(.failure(TranslationError.aiTranslation(String(format: format, http.statusCode, message))))
                }
                return
            }

            do {
                let content = try Self.aiMessageContent(from: data)
                let translations = Self.parseAITranslations(from: content, expectedCount: texts.count)
                guard translations.count == texts.count else {
                    let format = L("AI translation returned %d result(s), expected %d.")
                    throw TranslationError.aiTranslation(String(format: format, translations.count, texts.count))
                }
                DispatchQueue.main.async { completion(.success(translations)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    static func translateOneOpenAICompatible(
        text: String,
        targetLang: String,
        baseURL: String,
        apiKey: String,
        model: String,
        prompt: String,
        maxTokens: Int? = nil,
        timeout: TimeInterval = 30,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            DispatchQueue.main.async {
                completion(.failure(TranslationError.aiTranslation(L("AI translation model is not configured."))))
            }
            return
        }

        guard let url = aiChatCompletionsURL(from: baseURL) else {
            DispatchQueue.main.async {
                completion(.failure(TranslationError.aiTranslation(L("Invalid AI translation base URL."))))
            }
            return
        }

        let targetName = availableLanguages.first(where: { $0.code == targetLang })?.name ?? targetLang
        let systemPrompt = """
        \(prompt)

        Translate the user's OCR text to \(targetName) (\(targetLang)).
        Return only the translated text.
        Do not return JSON, markdown, explanations, alternatives, or notes.
        Preserve numbers, URLs, code, product names, and obvious proper nouns.
        If the text is already in the target language, return it unchanged.
        """

        var body: [String: Any] = [
            "model": model,
            "temperature": 0.0,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ],
        ]
        if let maxTokens {
            body["max_tokens"] = maxTokens
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            DispatchQueue.main.async {
                completion(.failure(TranslationError.aiTranslation(L("Could not encode AI translation request."))))
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(TranslationError.noData)) }
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let message = Self.aiErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                DispatchQueue.main.async {
                    let format = L("AI translation failed (%d): %@")
                    completion(.failure(TranslationError.aiTranslation(String(format: format, http.statusCode, message))))
                }
                return
            }

            do {
                let content = try Self.aiMessageContent(from: data)
                let translated = Self.cleanPlainAITranslation(from: content)
                guard !translated.isEmpty else {
                    throw TranslationError.emptyResult
                }
                DispatchQueue.main.async { completion(.success(translated)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    private static func aiChatCompletionsURL(from baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }
        let withoutSlash = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(withoutSlash)/chat/completions")
    }

    private static func aiMessageContent(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslationError.parseError
        }
        return content
    }

    private static func aiErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let error = json["error"] as? [String: Any] {
            return (error["message"] as? String) ?? String(describing: error)
        }
        return String(data: data, encoding: .utf8)
    }

    private static func parseAITranslations(from content: String, expectedCount: Int) -> [String] {
        let cleaned = stripMarkdownCodeFence(from: content)
        if let translations = decodeAITranslations(from: cleaned) {
            return translations
        }

        if let arrayStart = cleaned.firstIndex(of: "["),
           let arrayEnd = cleaned.lastIndex(of: "]"),
           arrayStart <= arrayEnd {
            let arrayString = String(cleaned[arrayStart...arrayEnd])
            if let translations = decodeAITranslations(from: arrayString) {
                return translations
            }
        }

        if expectedCount == 1 {
            return [cleaned.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        return []
    }

    private static func decodeAITranslations(from string: String) -> [String]? {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }

        if let array = json as? [Any] {
            return array.map { ($0 as? String) ?? String(describing: $0) }
        }

        if let dict = json as? [String: Any],
           let array = dict["translations"] as? [Any] {
            return array.map { ($0 as? String) ?? String(describing: $0) }
        }

        return nil
    }

    private static func cleanPlainAITranslation(from content: String) -> String {
        let cleaned = stripMarkdownCodeFence(from: content)
        if let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            if let string = json as? String {
                return string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let dict = json as? [String: Any] {
                if let translation = dict["translation"] as? String {
                    return translation.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let translations = dict["translations"] as? [Any],
                   let first = translations.first as? String {
                    return first.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            if let array = json as? [Any],
               let first = array.first as? String {
                return first.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripMarkdownCodeFence(from content: String) -> String {
        var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.hasPrefix("```") else { return cleaned }

        let lines = cleaned.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return cleaned }
        var body = lines
        body.removeFirst()
        if body.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            body.removeLast()
        }
        cleaned = body.joined(separator: "\n")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Apple Translation (macOS 15.0+ via SwiftUI bridge)

    @available(macOS 15.0, *)
    private static func translateBatchApple(
        texts: [String],
        targetLang: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        let target = appleLocale(from: targetLang)

        // Auto-detect source language to avoid Apple's "Choose Language" dialog
        let combined = texts.joined(separator: " ")
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(combined)

        guard let detected = recognizer.dominantLanguage else {
            // Can't detect language (single word, ambiguous text) — assume English
            // rather than passing nil which triggers Apple's blocking "Choose Language" dialog
            completion(.failure(TranslationError.appleTranslation("Could not detect source language. Try selecting more text.")))
            return
        }

        let source = Locale.Language(identifier: detected.rawValue)
        let config = TranslationSession.Configuration(source: source, target: target)
        // Must dispatch to main — TranslationBridge adds a SwiftUI view which requires main thread
        DispatchQueue.main.async {
            TranslationBridge.shared.translate(texts: texts, configuration: config, completion: completion)
        }
    }

    /// Map our language codes to Apple's Locale.Language.
    @available(macOS 15.0, *)
    private static func appleLocale(from code: String) -> Locale.Language {
        switch code {
        case "zh-CN": return Locale.Language(identifier: "zh-Hans")
        case "zh-TW": return Locale.Language(identifier: "zh-Hant")
        case "nb":    return Locale.Language(identifier: "no")
        default:      return Locale.Language(identifier: code)
        }
    }
}

final class LocalModelService {
    static let shared = LocalModelService()
    static let statusChangedNotification = Notification.Name("LocalModelServiceStatusChanged")

    private enum Constants {
        static let engineVersion = "b8833"
        static let engineArchiveURL = URL(string: "https://github.com/ggml-org/llama.cpp/releases/download/b8833/llama-b8833-bin-macos-arm64.tar.gz")!
        // Mirror URLs for China mainland
        static let engineMirrorURL1 = URL(string: "https://mirror.ghproxy.com/https://github.com/ggml-org/llama.cpp/releases/download/b8833/llama-b8833-bin-macos-arm64.tar.gz")!
        static let engineMirrorURL2 = URL(string: "https://ghproxy.com/https://github.com/ggml-org/llama.cpp/releases/download/b8833/llama-b8833-bin-macos-arm64.tar.gz")!
        static let modelURL = URL(string: "https://huggingface.co/jc-builds/Qwen2.5-0.5B-Instruct-Q4_K_M-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf")!
        // Mirror URL for China mainland
        static let modelMirrorURL = URL(string: "https://hf-mirror.com/jc-builds/Qwen2.5-0.5B-Instruct-Q4_K_M-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf")!
        static let modelFileName = "Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"
        static let modelDisplayName = "Qwen2.5 0.5B Instruct Q4_K_M"
        static let port = 11487
    }

    // MARK: - Progress Tracking
    struct DownloadProgress {
        let bytesWritten: Int64
        let totalBytes: Int64
        let fileName: String
    }

    var downloadProgressHandler: ((DownloadProgress) -> Void)?
    private(set) var currentDownloadProgress: Double = 0
    private(set) var currentDownloadingFile: String = ""

    private var serverProcess: Process?
    private var serverLogHandle: FileHandle?
    private var externalServerHealthy = false
    private var installing = false
    private(set) var statusText: String = ""

    private init() {
        refreshStatus()
    }

    var isInstalling: Bool { installing }
    var isEngineInstalled: Bool { FileManager.default.isExecutableFile(atPath: serverBinaryURL.path) }
    var isModelInstalled: Bool { FileManager.default.fileExists(atPath: modelURL.path) }
    var isReady: Bool { isEngineInstalled && isModelInstalled }

    var installButtonTitle: String {
        if installing { return L("Downloading…") }
        if isReady { return L("Start Local Model") }
        return L("Download Local Model")
    }

    func refreshStatus() {
        if installing {
            statusText = L("Downloading local model assets…")
        } else if isServerRunning || externalServerHealthy {
            statusText = String(format: L("Local model running: %@"), Constants.modelDisplayName)
        } else if isReady {
            statusText = String(format: L("Local model ready: %@"), Constants.modelDisplayName)
        } else if isEngineInstalled {
            statusText = L("Local model runtime installed. Model download required.")
        } else {
            statusText = String(format: L("Local model not installed. Download size: about %@."), "408 MB")
        }
        NotificationCenter.default.post(name: Self.statusChangedNotification, object: self)
    }

    func install(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !installing else { return }
        installing = true
        refreshStatus()

        do {
            try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        } catch {
            installing = false
            refreshStatus()
            completion(.failure(error))
            return
        }

        installEngineIfNeeded { [weak self] engineResult in
            guard let self = self else { return }
            switch engineResult {
            case .failure(let error):
                self.installing = false
                self.refreshStatus()
                completion(.failure(error))
            case .success:
                self.installModelIfNeeded { modelResult in
                    self.installing = false
                    self.refreshStatus()
                    completion(modelResult)
                }
            }
        }
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        guard isReady else {
            completion(.failure(TranslationError.aiTranslation(L("Local model is not installed. Click Download Local Model first."))))
            return
        }
        ensureServerRunning(completion: completion)
    }

    func translateBatch(
        texts: [String],
        targetLang: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard isReady else {
            completion(.failure(TranslationError.aiTranslation(L("Local model is not installed. Click Download Local Model first."))))
            return
        }

        ensureServerRunning { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                self.translateLineByLine(texts: texts, targetLang: targetLang, completion: completion)
            }
        }
    }

    private func translateLineByLine(
        texts: [String],
        targetLang: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        var results = texts
        let workItems = texts.enumerated().filter { _, text in
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !workItems.isEmpty else {
            completion(.success(results))
            return
        }

        let prompt = L("Translate accurately and naturally. Preserve names, numbers, code, URLs, markdown, and original line intent. Return only the translation.")
        var cursor = 0
        var firstError: Error?
        var successCount = 0

        func finishIfDone() -> Bool {
            guard cursor >= workItems.count else { return false }
            if successCount == 0, let firstError {
                completion(.failure(firstError))
            } else {
                completion(.success(results))
            }
            return true
        }

        func translateNext() {
            guard !finishIfDone() else { return }

            let (index, sourceText) = workItems[cursor]
            let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)

            func request(retry: Bool) {
                TranslationService.translateOneOpenAICompatible(
                    text: trimmed,
                    targetLang: targetLang,
                    baseURL: "http://127.0.0.1:\(Constants.port)/v1",
                    apiKey: "",
                    model: "local",
                    prompt: prompt,
                    maxTokens: self.maxTokens(for: trimmed),
                    timeout: 20
                ) { result in
                    switch result {
                    case .success(let translated):
                        let cleaned = translated.trimmingCharacters(in: .whitespacesAndNewlines)
                        if cleaned.isEmpty, !retry {
                            request(retry: true)
                            return
                        }
                        results[index] = cleaned.isEmpty ? sourceText : cleaned
                        if !cleaned.isEmpty {
                            successCount += 1
                        }
                        cursor += 1
                        translateNext()

                    case .failure(let error):
                        if !retry {
                            request(retry: true)
                            return
                        }
                        if firstError == nil {
                            firstError = error
                        }
                        results[index] = sourceText
                        cursor += 1
                        translateNext()
                    }
                }
            }

            request(retry: false)
        }

        translateNext()
    }

    private func maxTokens(for text: String) -> Int {
        min(384, max(64, text.count * 3 + 24))
    }

    private var baseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Lumashot/LocalModel", isDirectory: true)
    }

    private var engineArchiveURL: URL {
        baseDirectory.appendingPathComponent("llama-\(Constants.engineVersion)-macos-arm64.tar.gz")
    }

    private var engineDirectory: URL {
        baseDirectory.appendingPathComponent("llama-\(Constants.engineVersion)", isDirectory: true)
    }

    private var serverBinaryURL: URL {
        engineDirectory.appendingPathComponent("llama-server")
    }

    private var modelURL: URL {
        baseDirectory.appendingPathComponent(Constants.modelFileName)
    }

    private var serverLogURL: URL {
        baseDirectory.appendingPathComponent("llama-server.log")
    }

    private var isServerRunning: Bool {
        if let process = serverProcess, process.isRunning { return true }
        return false
    }

    private func installEngineIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isEngineInstalled else {
            completion(.success(()))
            return
        }

        currentDownloadingFile = "Engine"
        downloadWithFallback(
            primary: Constants.engineArchiveURL,
            mirrors: [Constants.engineMirrorURL1, Constants.engineMirrorURL2],
            to: engineArchiveURL,
            fileName: "Engine"
        ) { [weak self] result in
            guard let self = self else { return }
            self.currentDownloadingFile = ""
            switch result {
            case .failure(let error):
                completion(.failure(TranslationError.aiTranslation(L("Engine download failed:") + " \(error.localizedDescription)")))
            case .success:
                do {
                    try self.extractEngine()
                    // Verify engine was extracted
                    guard self.isEngineInstalled else {
                        completion(.failure(TranslationError.aiTranslation(L("Engine extraction failed - binary not found"))))
                        return
                    }
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    private func installModelIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isModelInstalled else {
            completion(.success(()))
            return
        }
        currentDownloadingFile = "Model"
        downloadWithFallback(
            primary: Constants.modelURL,
            mirror: Constants.modelMirrorURL,
            to: modelURL,
            fileName: "Model"
        ) { [weak self] result in
            guard let self = self else { return }
            self.currentDownloadingFile = ""
            switch result {
            case .failure(let error):
                completion(.failure(TranslationError.aiTranslation(L("Model download failed:") + " \(error.localizedDescription)")))
            case .success:
                // Verify model file exists and has reasonable size
                guard self.isModelInstalled else {
                    completion(.failure(TranslationError.aiTranslation(L("Model file not found after download"))))
                    return
                }
                // Check file size is at least 1MB (model should be ~300MB)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: self.modelURL.path),
                   let size = attrs[.size] as? Int64, size < 1_000_000 {
                    completion(.failure(TranslationError.aiTranslation(L("Model file too small (\(size) bytes) - download may be corrupted"))))
                    return
                }
                completion(.success(()))
            }
        }
    }

    private func downloadFile(from remoteURL: URL, to destination: URL, fileName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let delegate = DownloadTaskDelegate(fileName: fileName, destination: destination) { [weak self] progress in
            self?.downloadProgressHandler?(progress)
        } completion: { result in
            completion(result)
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: remoteURL)
        task.resume()
    }

    private func downloadWithFallback(primary: URL, mirrors: [URL], to destination: URL, fileName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        downloadFile(from: primary, to: destination, fileName: fileName) { [weak self] result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure:
                // Try mirrors one by one
                self?.tryNextMirror(mirrors: mirrors, destination: destination, fileName: fileName, completion: completion)
            }
        }
    }

    private func tryNextMirror(mirrors: [URL], destination: URL, fileName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let mirror = mirrors.first else {
            completion(.failure(TranslationError.aiTranslation(L("All download sources failed"))))
            return
        }

        let remainingMirrors = Array(mirrors.dropFirst())
        downloadFile(from: mirror, to: destination, fileName: fileName) { [weak self] result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure:
                self?.tryNextMirror(mirrors: remainingMirrors, destination: destination, fileName: fileName, completion: completion)
            }
        }
    }

    private func downloadWithFallback(primary: URL, mirror: URL, to destination: URL, fileName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        downloadWithFallback(primary: primary, mirrors: [mirror], to: destination, fileName: fileName, completion: completion)
    }

    private class DownloadTaskDelegate: NSObject, URLSessionDownloadDelegate {
        let fileName: String
        let destination: URL
        let progressHandler: (LocalModelService.DownloadProgress) -> Void
        let completion: (Result<Void, Error>) -> Void
        private var totalBytes: Int64 = 0
        private var hasCompleted = false

        init(fileName: String, destination: URL, progressHandler: @escaping (LocalModelService.DownloadProgress) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
            self.fileName = fileName
            self.destination = destination
            self.progressHandler = progressHandler
            self.completion = completion
            super.init()
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            guard !hasCompleted else { return }
            hasCompleted = true

            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: location, to: destination)
                DispatchQueue.main.async { self.completion(.success(())) }
            } catch {
                DispatchQueue.main.async { self.completion(.failure(error)) }
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard !hasCompleted else { return }

            if let error = error {
                hasCompleted = true
                DispatchQueue.main.async { self.completion(.failure(error)) }
            }
            // If no error, don't call completion here - will be called in didFinishDownloadingTo
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            totalBytes = totalBytesExpectedToWrite
            let progress = LocalModelService.DownloadProgress(
                bytesWritten: totalBytesWritten,
                totalBytes: totalBytesExpectedToWrite,
                fileName: fileName
            )
            DispatchQueue.main.async { self.progressHandler(progress) }
        }
    }

    private func extractEngine() throws {
        if FileManager.default.fileExists(atPath: engineDirectory.path) {
            try FileManager.default.removeItem(at: engineDirectory)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", engineArchiveURL.path, "-C", baseDirectory.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw TranslationError.aiTranslation(L("Could not extract local model runtime."))
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: serverBinaryURL.path)
    }

    private func ensureServerRunning(completion: @escaping (Result<Void, Error>) -> Void) {
        probeServer { [weak self] state in
            guard let self = self else { return }

            switch state {
            case .ready:
                self.externalServerHealthy = true
                self.refreshStatus()
                completion(.success(()))

            case .responding:
                self.waitForHealth(deadline: Date().addingTimeInterval(60), completion: completion)

            case .unavailable:
                if self.isServerRunning {
                    self.waitForHealth(deadline: Date().addingTimeInterval(60), completion: completion)
                    return
                }
                self.launchServer(completion: completion)
            }
        }
    }

    private func launchServer(completion: @escaping (Result<Void, Error>) -> Void) {
        let process = Process()
        process.executableURL = serverBinaryURL
        process.currentDirectoryURL = engineDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_LIBRARY_PATH"] = engineDirectory.path
        if environment["PATH"]?.isEmpty ?? true {
            environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        }
        process.environment = environment
        process.arguments = [
            "--model", modelURL.path,
            "--host", "127.0.0.1",
            "--port", "\(Constants.port)",
            "--ctx-size", "4096",
            "-np", "1",
            "--cache-ram", "0",
            "--n-gpu-layers", "999",
            "--threads", "\(max(2, ProcessInfo.processInfo.activeProcessorCount / 2))",
        ]

        do {
            let logHandle = try openServerLog()
            process.standardOutput = logHandle
            process.standardError = logHandle
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.serverLogHandle?.closeFile()
                    self?.serverLogHandle = nil
                    self?.externalServerHealthy = false
                    self?.refreshStatus()
                }
            }

            try process.run()
            serverProcess = process
            serverLogHandle = logHandle
            externalServerHealthy = false
            refreshStatus()
            waitForHealth(deadline: Date().addingTimeInterval(60), completion: completion)
        } catch {
            completion(.failure(TranslationError.aiTranslation("\(error.localizedDescription)\n\n\(recentServerLog())")))
        }
    }

    private func waitForHealth(deadline: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        guard Date() < deadline else {
            completion(.failure(TranslationError.aiTranslation("\(L("Local model server timed out while starting."))\n\n\(recentServerLog())")))
            return
        }

        if let process = serverProcess, !process.isRunning {
            let format = L("Local model server exited with code %d.")
            completion(.failure(TranslationError.aiTranslation("\(String(format: format, process.terminationStatus))\n\n\(recentServerLog())")))
            return
        }

        guard let url = URL(string: "http://127.0.0.1:\(Constants.port)/health") else {
            completion(.failure(TranslationError.badURL))
            return
        }

        URLSession.shared.dataTask(with: url) { _, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                if code == 200 {
                    self.externalServerHealthy = true
                    self.refreshStatus()
                    completion(.success(()))
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.waitForHealth(deadline: deadline, completion: completion)
                    }
                }
            }
        }.resume()
    }

    private enum ServerProbeState {
        case ready
        case responding
        case unavailable
    }

    private func probeServer(completion: @escaping (ServerProbeState) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:\(Constants.port)/health") else {
            completion(.unavailable)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                if code == 200 {
                    completion(.ready)
                } else if code > 0 {
                    completion(.responding)
                } else {
                    completion(.unavailable)
                }
            }
        }.resume()
    }

    private func openServerLog() throws -> FileHandle {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: serverLogURL.path) {
            FileManager.default.createFile(atPath: serverLogURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: serverLogURL)
        try handle.seekToEnd()
        let header = "\n\n----- \(Date()) -----\n"
        if let data = header.data(using: .utf8) {
            handle.write(data)
        }
        return handle
    }

    private func recentServerLog() -> String {
        guard let data = try? Data(contentsOf: serverLogURL), !data.isEmpty else {
            return L("No local model log was captured.")
        }
        let maxBytes = 6000
        let suffix = data.suffix(maxBytes)
        return String(data: suffix, encoding: .utf8) ?? L("Could not read local model log.")
    }
}

private enum KeychainStore {
    static func read(service: String, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func write(_ value: String, service: String, account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = baseQuery(service: service, account: account)

        if trimmed.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(trimmed.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

// MARK: - SwiftUI bridge for Apple Translation

/// Uses a hidden SwiftUI view with .translationTask() to obtain a TranslationSession.
/// This is the supported way to use the Translation framework from AppKit.
@available(macOS 15.0, *)
@MainActor
final class TranslationBridge: ObservableObject {
    static let shared = TranslationBridge()

    @Published var config: TranslationSession.Configuration?
    private var hostingView: NSView?
    private var pendingTexts: [String] = []
    private var pendingCompletion: ((Result<[String], Error>) -> Void)?

    private var translationID: UUID?

    func translate(
        texts: [String],
        configuration: TranslationSession.Configuration,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        // Cancel any in-flight translation before starting a new one
        if pendingCompletion != nil {
            cleanup()
        }

        let thisID = UUID()
        translationID = thisID
        pendingTexts = texts
        pendingCompletion = completion

        // Create hidden SwiftUI view and attach to a window
        let view = TranslationBridgeView(bridge: self)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: -1, y: -1, width: 1, height: 1)
        if let window = NSApp.windows.first(where: { $0.contentView != nil }) {
            window.contentView?.addSubview(hosting)
        }
        hostingView = hosting

        // Setting config triggers .translationTask
        config = configuration

        // Timeout: if session doesn't respond in 10s, report error
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.translationID == thisID, self.pendingCompletion != nil else { return }
            let completion = self.pendingCompletion
            self.cleanup()
            completion?(.failure(TranslationError.appleTranslation("Apple Translation timed out. The language pack may need to be downloaded in System Settings.")))
        }
    }

    fileprivate func sessionReady(_ session: TranslationSession) {
        // Ignore stale sessions from cancelled translations
        guard pendingCompletion != nil else { return }
        let texts = pendingTexts
        let completion = pendingCompletion
        let activeID = translationID
        Task {
            do {
                var results = Array(repeating: "", count: texts.count)
                for (i, text) in texts.enumerated() {
                    // Bail if a new translation was started while we're iterating
                    let stillActive = await MainActor.run { self.translationID == activeID }
                    guard stillActive else { return }
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        results[i] = text
                        continue
                    }
                    let response = try await session.translate(trimmed)
                    results[i] = response.targetText
                }
                await MainActor.run {
                    guard self.translationID == activeID else { return }
                    self.cleanup()
                    completion?(.success(results))
                }
            } catch {
                await MainActor.run {
                    guard self.translationID == activeID else { return }
                    self.cleanup()
                    let desc = error.localizedDescription
                    let msg = "Apple Translation failed: \(desc). You can switch to Google Translate in Settings."
                    completion?(.failure(TranslationError.appleTranslation(msg)))
                }
            }
        }
    }

    private func cleanup() {
        hostingView?.removeFromSuperview()
        hostingView = nil
        pendingTexts = []
        pendingCompletion = nil
        config = nil
    }
}

@available(macOS 15.0, *)
private struct TranslationBridgeView: View {
    @ObservedObject var bridge: TranslationBridge

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(bridge.config) { session in
                await MainActor.run {
                    bridge.sessionReady(session)
                }
            }
    }
}

enum TranslationError: LocalizedError {
    case badURL, noData, parseError, emptyResult
    case appleTranslation(String)
    case aiTranslation(String)
    var errorDescription: String? {
        switch self {
        case .badURL:      return "Invalid translation URL"
        case .noData:      return "No response from translation service"
        case .parseError:  return "Could not parse translation response"
        case .emptyResult: return "Translation returned empty result"
        case .appleTranslation(let msg): return msg
        case .aiTranslation(let msg): return msg
        }
    }
}
