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
    
    /// Translates a word using Google Translate (instant web API).
    /// If request fails due to network/firewall blocks, falls back to the local offline dictionary.
    func translateWithGoogle(word: String, direction: String) async -> GoogleTranslationResult? {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return nil }
        
        let sl = direction == "zh-to-en" ? "zh-CN" : "en"
        let tl = direction == "zh-to-en" ? "en" : "zh-CN"
        
        let endpoint = "https://translate.googleapis.com"
        guard let encodedWord = trimmedWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
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
            if let json = try JSONSerialization.jsonObject(with: data) as? [Any],
               let firstArray = json.first as? [Any] {
                
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
                
                if !fullTranslation.isEmpty {
                    return GoogleTranslationResult(
                        translation: fullTranslation.trimmingCharacters(in: .whitespacesAndNewlines),
                        phonetic: phonetic
                    )
                }
            }
            throw URLError(.cannotParseResponse)
        } catch {
            print("[TranslationService] Online Translate failed. Error: \(error). Falling back to local offline dictionary...")
            
            // Try local database lookup
            if let localTrans = lookupLocal(word: word, direction: direction) {
                let badge = Localization.string(for: "offline_local_badge")
                return GoogleTranslationResult(
                    translation: "\(badge) \(localTrans)",
                    phonetic: nil
                )
            }
            
            return GoogleTranslationResult(
                translation: Localization.string(for: "net_error_google"),
                phonetic: nil
            )
        }
    }
    
    /// Translates a word in its context using AI (Gemini or OpenAI-compatible API)
    func translateWithAI(word: String, context: String, direction: String) async -> String? {
        let provider = UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"
        let prompt = Localization.translationPrompt(word: word, context: context, direction: direction)

        let result: AIResult
        if provider == "gemini" {
            result = await callGeminiAPI(prompt: prompt)
        } else {
            result = await callOpenAIAPI(prompt: prompt)
        }

        switch result {
        case .success(let text): return text
        case .failure(let message): return message
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

    private func callOpenAIAPI(prompt: String) async -> AIResult {
        let apiKey = UserDefaults.standard.string(forKey: "openaiApiKey") ?? ""
        let endpoint = UserDefaults.standard.string(forKey: "openaiEndpoint") ?? "https://api.openai.com/v1/chat/completions"
        let model = UserDefaults.standard.string(forKey: "openaiModel") ?? "gpt-4o-mini"

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
                print("[TranslationService] OpenAI Error Code: \(httpResponse.statusCode), body: \(errorMsg)")
                return .failure("⚠️ API Error: \(httpResponse.statusCode)")
            }

            if let json = jsonObject(data: data),
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let text = message["content"] as? String {
                return .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return .failure("⚠️ API response format error")
        } catch {
            print("[TranslationService] OpenAI network error: \(error)")
            return .failure("⚠️ API offline / timeout")
        }
    }

    /// Tests connection to the selected AI provider with a simple prompt
    func testConnection() async -> (success: Bool, message: String) {
        let provider = UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"
        let prompt = "Respond with only one word: OK"

        let result: AIResult
        if provider == "gemini" {
            result = await callGeminiAPI(prompt: prompt)
        } else {
            result = await callOpenAIAPI(prompt: prompt)
        }

        switch result {
        case .success(let text): return (true, text)
        case .failure(let message): return (false, message)
        }
    }
    
    private func jsonObject(data: Data) -> [String: Any]? {
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
