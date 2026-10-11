import Foundation
import NaturalLanguage
import Combine
import SwiftUI
import Security
@preconcurrency import Translation

extension TranslationService {
    // MARK: - Apple Translation (macOS 15.0+ via SwiftUI bridge)

    @available(macOS 15.0, *)
    static func translateBatchApple(
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
    static func appleLocale(from code: String) -> Locale.Language {
        switch code {
        case "zh-CN": return Locale.Language(identifier: "zh-Hans")
        case "zh-TW": return Locale.Language(identifier: "zh-Hant")
        case "nb":    return Locale.Language(identifier: "no")
        default:      return Locale.Language(identifier: code)
        }
    }
}
