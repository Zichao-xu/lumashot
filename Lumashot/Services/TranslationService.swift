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
    static var cachedAppleAvailability: [String: Bool]?

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

    static let keychainService = "com.sw33tlie.macshot.translation"

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

    enum AutoLanguageFamily {
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
