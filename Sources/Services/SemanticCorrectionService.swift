import Alamofire
import Foundation
import os.log

internal final class SemanticCorrectionService {
    private let mlxService = MLXCorrectionService()
    private let keychainService: KeychainServiceProtocol
    private let personalDictionaryProvider: PersonalDictionaryProviding
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.whisp.app", category: "SemanticCorrection")

    // Chunking configuration for 32k context window
    // 32k tokens ≈ 24k words (0.75 ratio) ≈ 120k chars
    // Use conservative 6k words to leave room for system prompt
    private static let chunkSizeWords = 6000
    private static let overlapSizeWords = 200  // Small overlap for context continuity

    private func categoryFor(bundleId: String?) -> CategoryDefinition {
        guard let id = bundleId else { return CategoryDefinition.fallback }
        return AppCategoryManager.shared.category(for: id)
    }

    init(
        keychainService: KeychainServiceProtocol = KeychainService.shared,
        personalDictionaryProvider: PersonalDictionaryProviding = PersonalDictionaryStore.shared,
        defaults: UserDefaults = .standard
    ) {
        self.keychainService = keychainService
        self.personalDictionaryProvider = personalDictionaryProvider
        self.defaults = defaults
    }

    func correct(text: String, providerUsed: TranscriptionProvider, sourceAppBundleId: String? = nil) async
        -> String
    {
        let outcome = await correctWithWarning(
            text: text, providerUsed: providerUsed, sourceAppBundleId: sourceAppBundleId)
        return outcome.text
    }

    /// Like `correct(...)`, but returns a warning string when semantic correction is enabled but cannot run.
    ///
    /// This is used by the recording UI to reduce "silent failure" confusion for local MLX correction.
    func correctWithWarning(
        text: String, providerUsed: TranscriptionProvider, sourceAppBundleId: String? = nil
    ) async -> (text: String, warning: String?) {
        let modeRaw =
            defaults.string(forKey: AppDefaults.Keys.semanticCorrectionMode)
            ?? SemanticCorrectionMode.off.rawValue
        let mode = SemanticCorrectionMode(rawValue: modeRaw) ?? .off
        let personalDictionary = currentPersonalDictionarySnapshot()

        let category = categoryFor(bundleId: sourceAppBundleId)
        logger.info("Correction category: \(category.id) for bundleId: \(sourceAppBundleId ?? "nil")")

        let outcome: (text: String, warning: String?)

        switch mode {
        case .off:
            return (text, nil)
        case .localMLX:
            logger.info("Running local MLX correction")
            outcome = await correctLocallyWithMLX(
                text: text,
                category: category,
                personalDictionary: personalDictionary
            )
        case .cloud:
            switch providerUsed {
            case .openai:
                logger.info("Running cloud correction: OpenAI")
                outcome = (
                    await correctWithOpenAI(
                        text: text,
                        category: category,
                        personalDictionary: personalDictionary
                    ),
                    nil
                )
            case .gemini:
                logger.info("Running cloud correction: Gemini")
                outcome = (
                    await correctWithGemini(
                        text: text,
                        category: category,
                        personalDictionary: personalDictionary
                    ),
                    nil
                )
            case .local, .parakeet, .gemma, .whisperMLX:
                // Don't send local text to cloud.
                outcome = (text, nil)
            }
        }

        return (
            canonicalizeUsingPersonalDictionaryIfEnabled(
                outcome.text,
                mode: mode,
                snapshot: personalDictionary
            ),
            outcome.warning
        )
    }

    // MARK: - Local (MLX)
    private func correctLocallyWithMLX(
        text: String,
        category: CategoryDefinition,
        personalDictionary: PersonalDictionarySnapshot?
    ) async -> (text: String, warning: String?) {
        guard Arch.isAppleSilicon else {
            return (text, "Local semantic correction requires an Apple Silicon Mac.")
        }
        let modelRepo =
            defaults.string(forKey: AppDefaults.Keys.semanticCorrectionModelRepo)
            ?? AppDefaults.defaultSemanticCorrectionModelRepo
        do {
            let pyURL = try UvBootstrap.ensureVenv(userPython: nil)
            let prompt = loadPrompt(for: category, personalDictionary: personalDictionary)
            let output = try await mlxService.correct(
                text: text, modelRepo: modelRepo, pythonPath: pyURL.path, systemPrompt: prompt)
            let merged = Self.safeMerge(original: text, corrected: output, maxChangeRatio: 0.6)
            if merged == text {
                logger.info("MLX correction produced no accepted change (kept original)")
            } else {
                logger.info("MLX correction applied changes")
            }
            return (merged, nil)
        } catch {
            logger.error("MLX correction failed: \(error.localizedDescription)")
            return (
                text,
                "Semantic correction unavailable (Local MLX). Open Settings → Providers to install dependencies and download the model."
            )
        }
    }

    // MARK: - Cloud (OpenAI)
    private func correctWithOpenAI(
        text: String,
        category: CategoryDefinition,
        personalDictionary: PersonalDictionarySnapshot?
    ) async -> String {
        guard let apiKey = keychainService.getQuietly(service: "Whisp", account: "OpenAI") else {
            return text
        }
        let prompt = loadPrompt(for: category, personalDictionary: personalDictionary)
        let url = "https://api.openai.com/v1/chat/completions"
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json",
        ]
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text],
            ],
            "temperature": 0.3,
            "max_completion_tokens": 8192,
        ]

        do {
            let result = try await withCheckedThrowingContinuation {
                (cont: CheckedContinuation<String, Error>) in
                AF.request(
                    url, method: .post, parameters: body, encoding: JSONEncoding.default, headers: headers
                )
                .responseDecodable(of: OpenAIChatResponse.self) { response in
                    switch response.result {
                    case .success(let r):
                        let content = r.choices.first?.message.content ?? text
                        cont.resume(returning: content)
                    case .failure(let err):
                        cont.resume(throwing: err)
                    }
                }
            }
            return Self.safeMerge(original: text, corrected: result, maxChangeRatio: 0.25)
        } catch {
            return text
        }
    }

    // MARK: - Cloud (Gemini)
    private var geminiBaseURL: String {
        let custom = defaults.string(forKey: "geminiBaseURL") ?? ""
        if custom.isEmpty {
            return "https://generativelanguage.googleapis.com"
        }
        return custom.hasSuffix("/") ? String(custom.dropLast()) : custom
    }

    private func correctWithGemini(
        text: String,
        category: CategoryDefinition,
        personalDictionary: PersonalDictionarySnapshot?
    ) async -> String {
        guard let apiKey = keychainService.getQuietly(service: "Whisp", account: "Gemini") else {
            return text
        }
        let url = "\(geminiBaseURL)/v1beta/models/gemini-2.5-flash-lite:generateContent"
        let headers: HTTPHeaders = [
            "X-Goog-Api-Key": apiKey,
            "Content-Type": "application/json",
        ]
        let prompt = loadPrompt(for: category, personalDictionary: personalDictionary)
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": "\(prompt)\n\n\(text)"
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 8192,
            ],
        ]
        do {
            let result = try await withCheckedThrowingContinuation {
                (cont: CheckedContinuation<String, Error>) in
                AF.request(
                    url, method: .post, parameters: body, encoding: JSONEncoding.default, headers: headers
                )
                .responseDecodable(of: GeminiResponse.self) { response in
                    switch response.result {
                    case .success(let r):
                        let content = r.candidates.first?.content.parts.first?.text ?? text
                        cont.resume(returning: content)
                    case .failure(let err):
                        cont.resume(throwing: err)
                    }
                }
            }
            return Self.safeMerge(original: text, corrected: result, maxChangeRatio: 0.25)
        } catch {
            return text
        }
    }

    // MARK: - Prompt file helpers
    private func promptsBaseDir() -> URL? {
        return try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        .appendingPathComponent("Whisp/prompts", isDirectory: true)
    }

    private func loadPrompt(
        for category: CategoryDefinition,
        personalDictionary: PersonalDictionarySnapshot?
    ) -> String {
        let basePrompt: String

        if let base = promptsBaseDir() {
            let url = base.appendingPathComponent("\(category.id)_prompt.txt")
            if let userPrompt = try? String(contentsOf: url, encoding: .utf8), !userPrompt.isEmpty {
                basePrompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                let trimmed = category.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    basePrompt = trimmed
                } else {
                    basePrompt = CategoryDefinition.fallback.promptTemplate.trimmingCharacters(
                        in: .whitespacesAndNewlines)
                }
            }
        } else {
            let trimmed = category.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                basePrompt = trimmed
            } else {
                basePrompt = CategoryDefinition.fallback.promptTemplate.trimmingCharacters(
                    in: .whitespacesAndNewlines)
            }
        }

        guard let personalDictionary,
            let instructions = Self.personalDictionaryInstructions(for: personalDictionary)
        else {
            return basePrompt
        }

        return "\(basePrompt)\n\n\(instructions)"
    }

    private func readPromptFile(name: String) -> String? {
        guard let base = promptsBaseDir() else { return nil }
        let url = base.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func canonicalizeUsingPersonalDictionaryIfEnabled(
        _ text: String,
        mode: SemanticCorrectionMode? = nil
    ) -> String {
        let effectiveMode: SemanticCorrectionMode
        if let mode {
            effectiveMode = mode
        } else {
            let rawValue =
                defaults.string(forKey: AppDefaults.Keys.semanticCorrectionMode)
                ?? SemanticCorrectionMode.off.rawValue
            effectiveMode = SemanticCorrectionMode(rawValue: rawValue) ?? .off
        }

        return canonicalizeUsingPersonalDictionaryIfEnabled(
            text,
            mode: effectiveMode,
            snapshot: currentPersonalDictionarySnapshot()
        )
    }

    private func currentPersonalDictionarySnapshot() -> PersonalDictionarySnapshot? {
        guard defaults.bool(forKey: AppDefaults.Keys.personalDictionaryEnabled) else {
            return nil
        }

        let snapshot = personalDictionaryProvider.snapshot()
        return snapshot.isEmpty ? nil : snapshot
    }

    private func canonicalizeUsingPersonalDictionaryIfEnabled(
        _ text: String,
        mode: SemanticCorrectionMode,
        snapshot: PersonalDictionarySnapshot?
    ) -> String {
        guard mode != .off, let snapshot, !snapshot.isEmpty else {
            return text
        }

        return Self.applyPersonalDictionary(to: text, snapshot: snapshot)
    }

    // MARK: - Safety Guard (internal for testability)
    static func personalDictionaryInstructions(
        for snapshot: PersonalDictionarySnapshot,
        maximumRenderedLength: Int = 1800
    ) -> String? {
        guard !snapshot.isEmpty else { return nil }

        let omittedLine = "- Additional terms omitted for brevity."
        let headerLines = [
            "Personal dictionary:",
            "- When one of these terms is relevant, use the exact preferred spelling.",
            "- Do not invent a dictionary term unless the audio clearly referred to it.",
        ]

        let headerLength = headerLines.joined(separator: "\n").count
        guard headerLength <= maximumRenderedLength else { return nil }

        var lines = headerLines
        var renderedLength = headerLength
        var includedCount = 0

        func appendLineIfFits(_ line: String) -> Bool {
            let separatorLength = lines.isEmpty ? 0 : 1
            guard renderedLength + separatorLength + line.count <= maximumRenderedLength else {
                return false
            }

            lines.append(line)
            renderedLength += separatorLength + line.count
            return true
        }

        for rule in snapshot.rules {
            let line: String
            if rule.aliases.isEmpty {
                line = "- \(rule.preferredText)"
            } else {
                line = "- \(rule.preferredText): \(rule.aliases.joined(separator: ", "))"
            }

            guard appendLineIfFits(line) else {
                break
            }
            includedCount += 1
        }

        if includedCount < snapshot.rules.count {
            while !appendLineIfFits(omittedLine), includedCount > 1 {
                let removedLine = lines.removeLast()
                renderedLength -= removedLine.count + 1
                includedCount -= 1
            }

            _ = appendLineIfFits(omittedLine)
        }

        return lines.joined(separator: "\n")
    }

    static func applyPersonalDictionary(to text: String, snapshot: PersonalDictionarySnapshot) -> String {
        guard !text.isEmpty, !snapshot.isEmpty else { return text }

        var result = text
        for pattern in canonicalizationPatterns(from: snapshot) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = pattern.regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: pattern.replacement
            )
        }

        return result
    }

    static func safeMerge(original: String, corrected: String, maxChangeRatio: Double) -> String {
        guard !corrected.isEmpty else { return original }
        let ratio = normalizedEditDistance(a: original, b: corrected)
        if ratio > maxChangeRatio { return original }
        return corrected.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedEditDistance(a: String, b: String) -> Double {
        if a == b { return 0 }

        let maxLength = 5000
        let aChars = Array(a.prefix(maxLength))
        let bChars = Array(b.prefix(maxLength))

        let m = aChars.count
        let n = bChars.count
        if m == 0 || n == 0 { return 1 }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                dp[i][j] = min(
                    dp[i - 1][j] + 1,
                    dp[i][j - 1] + 1,
                    dp[i - 1][j - 1] + cost
                )
            }
        }
        let dist = dp[m][n]
        let denom = max(m, n)
        return Double(dist) / Double(denom)
    }

    private static func canonicalizationPatterns(
        from snapshot: PersonalDictionarySnapshot
    ) -> [(regex: NSRegularExpression, replacement: String, length: Int)] {
        var patterns: [(regex: NSRegularExpression, replacement: String, length: Int)] = []

        for rule in snapshot.rules {
            for variant in [rule.preferredText] + rule.aliases {
                let escapedVariant = NSRegularExpression.escapedPattern(for: variant)
                let pattern =
                    "(?<![\\p{L}\\p{N}@_\\-/])(?<![\\p{L}\\p{N}]\\.)\(escapedVariant)(?![\\p{L}\\p{N}@_\\-/])(?!\\.[\\p{L}\\p{N}])"

                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                else {
                    continue
                }

                patterns.append(
                    (
                        regex: regex,
                        replacement: NSRegularExpression.escapedTemplate(for: rule.preferredText),
                        length: variant.count
                    ))
            }
        }

        patterns.sort {
            if $0.length == $1.length {
                return $0.replacement.count > $1.replacement.count
            }
            return $0.length > $1.length
        }

        return patterns
    }
}

// MARK: - Response Models
internal struct OpenAIChatResponse: Codable {
    struct Choice: Codable { let message: Message }
    struct Message: Codable {
        let role: String
        let content: String
    }
    let choices: [Choice]
}
