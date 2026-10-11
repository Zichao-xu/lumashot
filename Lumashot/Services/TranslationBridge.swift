import Foundation
import NaturalLanguage
import Combine
import SwiftUI
import Security
@preconcurrency import Translation

@available(macOS 15.0, *)
@MainActor
final class TranslationBridge: ObservableObject {
    static let shared = TranslationBridge()

    @Published var config: TranslationSession.Configuration?
    var hostingView: NSView?
    var pendingTexts: [String] = []
    var pendingCompletion: ((Result<[String], Error>) -> Void)?

    var translationID: UUID?

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

    func sessionReady(_ session: TranslationSession) {
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

    func cleanup() {
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
