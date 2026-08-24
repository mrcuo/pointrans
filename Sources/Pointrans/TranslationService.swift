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

    private let localDict = LocalDictionary()
    private let cache = TranslationCache()

    private init() {}

    /// Fallback dictionary lookup (exact hash hit; English falls back to light morphology).
    private func lookupLocal(word: String, direction: String) -> String? {
        localDict.lookup(word: word, direction: direction)
    }

    /// Immediate local-dictionary result, or nil if the word is not covered. Shown instantly
    /// and then superseded by `translateOnline` once that returns.
    func localTranslate(word: String, direction: String) -> GoogleTranslationResult? {
        guard let translation = lookupLocal(word: word, direction: direction) else { return nil }
        let badge = Localization.string(for: "offline_local_badge")
        return GoogleTranslationResult(translation: "\(badge) \(translation)", phonetic: nil)
    }

    /// Online translation (cache -> Google -> Bing). Returns nil when every online endpoint
    /// fails; the caller decides how to degrade. Successful results are cached.
    func translateOnline(word: String, direction: String) async -> GoogleTranslationResult? {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return nil }

        let cacheKey = "\(direction)|\(trimmedWord.lowercased())"
        if let cached = cache.value(for: cacheKey) {
            return cached
        }

        if let result = await googleTranslate(word: trimmedWord, direction: direction) {
            cache.set(result, for: cacheKey)
            return result
        }
        if let result = await bingTranslate(word: trimmedWord, direction: direction) {
            cache.set(result, for: cacheKey)
            return result
        }
        return nil
    }

    private func googleTranslate(word: String, direction: String) async -> GoogleTranslationResult? {
        let sl = direction == "zh-to-en" ? "zh-CN" : "en"
        let tl = direction == "zh-to-en" ? "en" : "zh-CN"
        guard let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }

        // Try several Google hosts: the default endpoint can be blocked by regional
        // networks/firewalls while an alternate host still works.
        let hosts = [
            "https://translate.googleapis.com",
            "https://translate.google.com",
            "https://clients5.google.com"
        ]

        for host in hosts {
            guard let url = URL(string: "\(host)/translate_a/single?client=gtx&sl=\(sl)&tl=\(tl)&dt=t&dt=rm&q=\(encodedWord)") else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 8.0
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let result = Self.parseGoogleResponse(data) {
                    return result
                }
            } catch {
                print("[TranslationService] Google host failed (\(host)): \(error)")
            }
        }
        return nil
    }

    /// Parses a Google Translate response (with dt=rm):
    /// [[["translation", "original", null, null, 1], [null, null, "targetTranslit", "sourceTranslit"]], null, "en"]
    private static func parseGoogleResponse(_ data: Data) -> GoogleTranslationResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
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

                // Transliteration/phonetic of the source word, if present (always at index 3)
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

/// Loads the offline dictionary (~6MB, ~170k entries) asynchronously on a background thread
/// so it never blocks launch. Lookups are O(1) hash hits; English falls back to lightweight
/// suffix stripping for inflected forms. A full-dictionary fuzzy scan was deliberately removed
/// because it would traverse the whole table on every hover.
final class LocalDictionary {
    private var enToZh: [String: String] = [:]
    private var zhToEn: [String: String] = [:]
    private let lock = NSLock()
    private(set) var isLoaded = false

    init() {
        Task.detached(priority: .utility) {
            let (en, zh) = Self.loadFromBundle()
            self.apply(en: en, zh: zh)
        }
    }

    private func apply(en: [String: String], zh: [String: String]) {
        lock.lock()
        enToZh = en
        zhToEn = zh
        isLoaded = true
        lock.unlock()
    }

    func lookup(word: String, direction: String) -> String? {
        let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        lock.lock()
        defer { lock.unlock() }
        guard isLoaded else { return nil }

        if direction == "zh-to-en" {
            return zhToEn[cleaned]
        }

        let w = cleaned.lowercased()
        if let v = enToZh[w] { return v }
        return inflectedLookup(w)
    }

    /// English inflected-form fallback (settings -> setting, used -> use, boxes -> box).
    private func inflectedLookup(_ word: String) -> String? {
        let stems = ["ing", "ies", "ed", "es", "ly", "s"].compactMap { suffix -> String? in
            guard word.count > suffix.count + 2, word.hasSuffix(suffix) else { return nil }
            return String(word.dropLast(suffix.count))
        }
        for stem in stems {
            if let v = enToZh[stem] { return v }
        }
        if word.hasSuffix("ies") {
            let y = String(word.dropLast(3)) + "y"
            if let v = enToZh[y] { return v }
        }
        return nil
    }

    private static func loadFromBundle() -> ([String: String], [String: String]) {
        guard let url = Bundle.main.url(forResource: "local_dict", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]],
              let en = root["en_to_zh"],
              let zh = root["zh_to_en"] else {
            print("[LocalDictionary] Failed to load local_dict.json.")
            return ([:], [:])
        }
        print("[LocalDictionary] Loaded \(en.count) EN and \(zh.count) ZH entries.")
        return (en, zh)
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
