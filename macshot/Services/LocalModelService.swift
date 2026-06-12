import Foundation
import NaturalLanguage
import Combine
import SwiftUI
import Security

final class LocalModelService {
    static let shared = LocalModelService()
    static let statusChangedNotification = Notification.Name("LocalModelServiceStatusChanged")

    enum Constants {
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
    var currentDownloadProgress: Double = 0
    var currentDownloadingFile: String = ""

    var serverProcess: Process?
    var serverLogHandle: FileHandle?
    var externalServerHealthy = false
    var installing = false
    var statusText: String = ""

    init() {
        refreshStatus()
    }

    var isInstalling: Bool { installing }
    var isEngineInstalled: Bool { FileManager.default.fileExists(atPath: serverBinaryURL.path) }
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

    func translateLineByLine(
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

    func maxTokens(for text: String) -> Int {
        min(384, max(64, text.count * 3 + 24))
    }

    var baseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Lumashot/LocalModel", isDirectory: true)
    }

    var engineArchiveURL: URL {
        baseDirectory.appendingPathComponent("llama-\(Constants.engineVersion)-macos-arm64.tar.gz")
    }

    /// The llama engine ships INSIDE the app bundle (Contents/Resources/llama-engine)
    /// and is signed together with the app, so the App Sandbox permits executing it.
    /// A downloaded engine sitting in the container cannot be executed under the
    /// sandbox (access(X_OK) is denied), which is why it must be bundled.
    var engineDirectory: URL {
        (Bundle.main.resourceURL ?? Bundle.main.bundleURL)
            .appendingPathComponent("llama-engine", isDirectory: true)
    }

    var serverBinaryURL: URL {
        engineDirectory.appendingPathComponent("llama-server")
    }

    var modelURL: URL {
        baseDirectory.appendingPathComponent(Constants.modelFileName)
    }

    var serverLogURL: URL {
        baseDirectory.appendingPathComponent("llama-server.log")
    }

    var isServerRunning: Bool {
        if let process = serverProcess, process.isRunning { return true }
        return false
    }

    func installEngineIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        // The engine is bundled inside the app and signed with it — there is
        // nothing to download or extract. (Running a downloaded engine from the
        // container is blocked by the App Sandbox.) Just verify it's present.
        if isEngineInstalled {
            completion(.success(()))
        } else {
            completion(.failure(TranslationError.aiTranslation(L("Bundled translation engine is missing — reinstall the app."))))
        }
    }

    func legacyInstallEngineIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
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

    func installModelIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
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

    func downloadFile(from remoteURL: URL, to destination: URL, fileName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let delegate = DownloadTaskDelegate(fileName: fileName, destination: destination) { [weak self] progress in
            self?.downloadProgressHandler?(progress)
        } completion: { result in
            completion(result)
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: remoteURL)
        task.resume()
    }

    func downloadWithFallback(primary: URL, mirrors: [URL], to destination: URL, fileName: String, completion: @escaping (Result<Void, Error>) -> Void) {
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

    func tryNextMirror(mirrors: [URL], destination: URL, fileName: String, completion: @escaping (Result<Void, Error>) -> Void) {
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

    func downloadWithFallback(primary: URL, mirror: URL, to destination: URL, fileName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        downloadWithFallback(primary: primary, mirrors: [mirror], to: destination, fileName: fileName, completion: completion)
    }

    class DownloadTaskDelegate: NSObject, URLSessionDownloadDelegate {
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

    func extractEngine() throws {
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

    func ensureServerRunning(completion: @escaping (Result<Void, Error>) -> Void) {
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

    func launchServer(completion: @escaping (Result<Void, Error>) -> Void) {
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

    func waitForHealth(deadline: Date, completion: @escaping (Result<Void, Error>) -> Void) {
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

    enum ServerProbeState {
        case ready
        case responding
        case unavailable
    }

    func probeServer(completion: @escaping (ServerProbeState) -> Void) {
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

    func openServerLog() throws -> FileHandle {
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

    func recentServerLog() -> String {
        guard let data = try? Data(contentsOf: serverLogURL), !data.isEmpty else {
            return L("No local model log was captured.")
        }
        let maxBytes = 6000
        let suffix = data.suffix(maxBytes)
        return String(data: suffix, encoding: .utf8) ?? L("Could not read local model log.")
    }
}

enum KeychainStore {
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

    static func baseQuery(service: String, account: String) -> [String: Any] {
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
