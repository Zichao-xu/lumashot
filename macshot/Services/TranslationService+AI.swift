import Foundation
import NaturalLanguage
import Combine
import SwiftUI
import Security

extension TranslationService {
    // MARK: - AI Translation (OpenAI-compatible chat completions)

    static func translateBatchAI(
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

    static func aiChatCompletionsURL(from baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }
        let withoutSlash = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(withoutSlash)/chat/completions")
    }

    static func aiMessageContent(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslationError.parseError
        }
        return content
    }

    static func aiErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let error = json["error"] as? [String: Any] {
            return (error["message"] as? String) ?? String(describing: error)
        }
        return String(data: data, encoding: .utf8)
    }

    static func parseAITranslations(from content: String, expectedCount: Int) -> [String] {
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

    static func decodeAITranslations(from string: String) -> [String]? {
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

    static func cleanPlainAITranslation(from content: String) -> String {
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

    static func stripMarkdownCodeFence(from content: String) -> String {
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

}
