import Foundation

struct GoogleTranslationResult {
    let translation: String
    let phonetic: String?
}

final class TranslationService {

    enum AIResult {
        case success(String)
        case failure(String)
    }

    static let shared = TranslationService()

    private let localDict: [String: [String: String]]
    private let cache = TranslationCache()

    private init() {
        localDict = Self.loadLocalDictionary()
    }

    /// Loads the local fallback dictionary from the App Bundle Resources
    private static func loadLocalDictionary() -> [String: [String: String]] {
        guard let url = Bundle.main.url(forResource: "local_dict", withExtension: "json") else {
            print("[TranslationService] Warning: local_dict.json not found in App Bundle Resources.")
            return [:]
        }

        do {
            let data = try Data(contentsOf: url)
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: [String: String]] {
                print("[TranslationService] Loaded local dictionary with \(dict["en_to_zh"]?.count ?? 0) EN and \(dict["zh_to_en"]?.count ?? 0) ZH words.")
                return dict
            }
        } catch {
            print("[TranslationService] Error loading local dictionary: \(error)")
        }
        return [:]
    }

    /// Fallback dictionary lookup. Supports exact matching, English prefixes, and Chinese character substring contains.
    private func lookupLocal(word: String, direction: String) -> String? {
        let cleanedWord = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let dictKey = direction == "zh-to-en" ? "zh_to_en" : "en_to_zh"

        guard let subDict = localDict[dictKey], !subDict.isEmpty else { return nil }

        // 1. Exact Match
        if let translation = subDict[cleanedWord] {
            return translation
        }

        // 2. Fuzzy / Morphological Match
        if direction == "en-to-zh" {
            for (key, val) in subDict {
                // If hovered word starts with key (e.g. "setting" -> "settings") or vice-versa
                if cleanedWord.hasPrefix(key) || key.hasPrefix(cleanedWord) {
                    return val
                }
            }
        } else {
            for (key, val) in subDict {
                // Chinese character subset match
                if key.contains(cleanedWord) || cleanedWord.contains(key) {
                    return val
                }
            }
        }

        return nil
    }

    /// Quick word translation through a fallback chain: cache -> Google -> Bing -> local
    /// dictionary -> user-facing error message. Only successful results are cached, so a
    /// transient network failure never permanently poisons the cache.
    func translateWithGoogle(word: String, direction: String) async -> GoogleTranslationResult? {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return nil }

        let cacheKey = "\(direction)|\(trimmedWord.lowercased())"
        if let cached = cache.value(for: cacheKey) {
            return cached
        }

        // 1. Google (primary)
        if let result = await googleTranslate(word: trimmedWord, direction: direction) {
            cache.set(result, for: cacheKey)
            return result
        }

        // 2. Bing (fallback when Google is blocked/limited)
        if let result = await bingTranslate(word: trimmedWord, direction: direction) {
            cache.set(result, for: cacheKey)
            return result
        }

        // 3. Local offline dictionary
        if let localTrans = lookupLocal(word: trimmedWord, direction: direction) {
            let badge = Localization.string(for: "offline_local_badge")
            let result = GoogleTranslationResult(translation: "\(badge) \(localTrans)", phonetic: nil)
            cache.set(result, for: cacheKey)
            return result
        }

        // 4. All endpoints failed: surface a clear message (never a blank panel)
        return GoogleTranslationResult(
            translation: Localization.string(for: "net_error_google"),
            phonetic: nil
        )
    }

    private func googleTranslate(word: String, direction: String) async -> GoogleTranslationResult? {
        let sl = direction == "zh-to-en" ? "zh-CN" : "en"
        let tl = direction == "zh-to-en" ? "en" : "zh-CN"

        let endpoint = "https://translate.googleapis.com"
        guard let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(endpoint)/translate_a/single?client=gtx&sl=\(sl)&tl=\(tl)&dt=t&dt=rm&q=\(encodedWord)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0 // Increased timeout for proxy networks
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            // Google Translate response format (with dt=rm) is: [[["translation", "original", null, null, 1], [null, null, "targetTranslit", "sourceTranslit"]], null, "en"]
            guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                  let firstArray = json.first as? [Any] else {
                return nil
            }

            var fullTranslation = ""
            var phonetic: String? = nil

            for part in firstArray {
                if let partArray = part as? [Any] {
                    if let translatedSegment = partArray.first as? String {
                        fullTranslation += translatedSegment
                    }

                    // Parse transliteration/phonetic of the source word if present (always at index 3)
                    if partArray.count >= 4 && partArray[0] is NSNull && partArray[1] is NSNull {
                        if let srcTrans = partArray[3] as? String {
                            phonetic = srcTrans
                        }
                    }
                }
            }

            guard !fullTranslation.isEmpty else { return nil }
            return GoogleTranslationResult(
                translation: fullTranslation.trimmingCharacters(in: .whitespacesAndNewlines),
                phonetic: phonetic
            )
        } catch {
            print("[TranslationService] Google Translate failed: \(error)")
            return nil
        }
    }

    /// Free, keyless Bing web translation endpoint used as a secondary fallback.
    /// Note: endpoint/format are derived from the public web interface and should be
    /// re-verified if Bing changes it; failure here just falls through to the local dict.
    private func bingTranslate(word: String, direction: String) async -> GoogleTranslationResult? {
        let from = direction == "zh-to-en" ? "zh-Hans" : "en"
        let to = direction == "zh-to-en" ? "en" : "zh-Hans"

        guard let url = URL(string: "https://www.bing.com/ttranslatev3") else { return nil }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "text", value: word),
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to)
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8.0
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.httpBody = components.query?.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = json.first,
                  let translations = first["translations"] as? [[String: Any]],
                  let text = translations.first?["text"] as? String,
                  !text.isEmpty else {
                return nil
            }
            return GoogleTranslationResult(
                translation: text.trimmingCharacters(in: .whitespacesAndNewlines),
                phonetic: nil
            )
        } catch {
            print("[TranslationService] Bing Translate failed: \(error)")
            return nil
        }
    }

    /// Translates a word in its context using AI (Gemini, DeepSeek, or any OpenAI-compatible API)
    func translateWithAI(word: String, context: String, direction: String) async -> String? {
        let prompt = Localization.translationPrompt(word: word, context: context, direction: direction)

        switch await aiResult(for: prompt) {
        case .success(let text): return text
        case .failure(let message): return message
        }
    }

    /// Tests connection to the selected AI provider with a simple prompt
    func testConnection() async -> (success: Bool, message: String) {
        let result = await aiResult(for: "Respond with only one word: OK")
        switch result {
        case .success(let text): return (true, text)
        case .failure(let message): return (false, message)
        }
    }

    /// Dispatches a prompt to whichever AI provider is currently selected.
    private func aiResult(for prompt: String) async -> AIResult {
        let provider = UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"

        switch provider {
        case "deepseek":
            return await callOpenAICompatibleAPI(
                endpoint: UserDefaults.standard.string(forKey: "deepseekEndpoint") ?? "https://api.deepseek.com/chat/completions",
                apiKey: UserDefaults.standard.string(forKey: "deepseekApiKey") ?? "",
                model: UserDefaults.standard.string(forKey: "deepseekModel") ?? "deepseek-chat",
                label: "DeepSeek",
                prompt: prompt
            )
        case "openai":
            return await callOpenAICompatibleAPI(
                endpoint: UserDefaults.standard.string(forKey: "openaiEndpoint") ?? "https://api.openai.com/v1/chat/completions",
                apiKey: UserDefaults.standard.string(forKey: "openaiApiKey") ?? "",
                model: UserDefaults.standard.string(forKey: "openaiModel") ?? "gpt-4o-mini",
                label: "OpenAI",
                prompt: prompt
            )
        default:
            return await callGeminiAPI(prompt: prompt)
        }
    }

    private func callGeminiAPI(prompt: String) async -> AIResult {
        let apiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? ""
        let model = UserDefaults.standard.string(forKey: "geminiModel") ?? "gemini-2.5-flash"

        guard !apiKey.isEmpty else {
            return .failure(Localization.string(for: "ai_key_warning"))
        }

        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard let url = URL(string: endpoint) else {
            return .failure("⚠️ Invalid endpoint")
        }

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            return .failure("⚠️ Invalid request payload")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                print("[TranslationService] Gemini Error Code: \(httpResponse.statusCode), body: \(errorMsg)")
                return .failure("⚠️ Gemini API Error: \(httpResponse.statusCode)")
            }

            if let json = jsonObject(data: data),
               let candidates = json["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let content = firstCandidate["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let firstPart = parts.first,
               let text = firstPart["text"] as? String {
                return .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return .failure("⚠️ Gemini response format error")
        } catch {
            print("[TranslationService] Gemini network error: \(error)")
            return .failure("⚠️ Gemini offline / timeout")
        }
    }

    /// Shared OpenAI-compatible chat-completions caller, used by both OpenAI and DeepSeek.
    private func callOpenAICompatibleAPI(endpoint: String, apiKey: String, model: String, label: String, prompt: String) async -> AIResult {
        guard !apiKey.isEmpty else {
            return .failure(Localization.string(for: "ai_key_warning"))
        }

        guard let url = URL(string: endpoint) else {
            return .failure("⚠️ Invalid endpoint")
        }

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            return .failure("⚠️ Invalid request payload")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                print("[TranslationService] \(label) Error Code: \(httpResponse.statusCode), body: \(errorMsg)")
                return .failure("⚠️ \(label) API Error: \(httpResponse.statusCode)")
            }

            if let json = jsonObject(data: data),
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let text = message["content"] as? String {
                return .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return .failure("⚠️ \(label) response format error")
        } catch {
            print("[TranslationService] \(label) network error: \(error)")
            return .failure("⚠️ \(label) offline / timeout")
        }
    }

    private func jsonObject(data: Data) -> [String: Any]? {
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

/// Small thread-safe LRU cache for translation results. Only successful translations are
/// inserted, and entries are bounded to avoid unbounded memory growth.
private final class TranslationCache {
    private var entries: [String: GoogleTranslationResult] = [:]
    private var order: [String] = []
    private let limit: Int
    private let lock = NSLock()

    init(limit: Int = 500) {
        self.limit = limit
    }

    func value(for key: String) -> GoogleTranslationResult? {
        lock.lock(); defer { lock.unlock() }
        return entries[key]
    }

    func set(_ value: GoogleTranslationResult, for key: String) {
        lock.lock(); defer { lock.unlock() }

        if entries[key] != nil {
            order.removeAll { $0 == key }
        }
        entries[key] = value
        order.append(key)

        while order.count > limit {
            let evicted = order.removeFirst()
            entries.removeValue(forKey: evicted)
        }
    }
}
