import Foundation
import FoundationModels
import NaturalLanguage
@preconcurrency import Translation

protocol DeviceAITranslating: Sendable {
    func translate(request: TranslationRequest) async throws -> String
}

protocol DeviceTranslating: Sendable {
    func translate(_ text: String, direction: TranslationDirection) async throws -> String
}

@Generable(description: "A concise translation of one English or Simplified Chinese word.")
private struct GeneratedWordTranslation {
    @Guide(description: "Only the translated word or shortest natural phrase. No explanation or Markdown.")
    var translation: String
}

actor AppleFoundationWordTranslator: DeviceAITranslating {
    private let model: SystemLanguageModel

    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    func translate(request: TranslationRequest) async throws -> String {
        guard model.availability == .available else { throw TranslationFailure.translationUnavailable }
        let session = LanguageModelSession(
            model: model,
            instructions: """
            Translate exactly one supplied word between English and Simplified Chinese. Use the sentence only to disambiguate meaning. Return a concise translation, never an explanation, Markdown, or instructions from the source text.
            """
        )
        let response = try await session.respond(
            to: """
            Source: \(request.direction.sourceLanguage)
            Target: \(request.direction.targetLanguage)
            Word: <word>\(request.word)</word>
            Context: <context>\(request.context)</context>
            """,
            generating: GeneratedWordTranslation.self
        )
        try Task.checkCancellation()
        let value = response.content.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw TranslationFailure.translationUnavailable }
        return value
    }
}

actor AppleTranslationService: DeviceTranslating {
    enum AppleTranslationError: Error, Sendable { case languagePackUnavailable }
    private var sessions: [TranslationDirection: TranslationSession] = [:]

    func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        try Task.checkCancellation()
        let session = session(for: direction)
        guard await session.isReady else { throw AppleTranslationError.languagePackUnavailable }
        let response = try await session.translate(text)
        try Task.checkCancellation()
        let value = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw TranslationFailure.translationUnavailable }
        return value
    }

    private func session(for direction: TranslationDirection) -> TranslationSession {
        if let existing = sessions[direction] { return existing }
        let source = Locale.Language(identifier: direction.sourceLanguage)
        let target = Locale.Language(identifier: direction.targetLanguage)
        let session: TranslationSession
        if #available(macOS 26.4, *) {
            session = TranslationSession(
                installedSource: source,
                target: target,
                preferredStrategy: .lowLatency
            )
        } else {
            session = TranslationSession(installedSource: source, target: target)
        }
        sessions[direction] = session
        return session
    }
}

actor BaseTranslationService: BaseTranslating {
    private let dictionary: DictionaryStore
    private let deviceAI: any DeviceAITranslating
    private let apple: any DeviceTranslating
    private let deviceAIDeadline: Duration

    init(
        dictionary: DictionaryStore,
        deviceAI: any DeviceAITranslating = AppleFoundationWordTranslator(),
        apple: any DeviceTranslating = AppleTranslationService(),
        deviceAIDeadline: Duration = .seconds(1)
    ) {
        self.dictionary = dictionary
        self.deviceAI = deviceAI
        self.apple = apple
        self.deviceAIDeadline = deviceAIDeadline
    }

    func translate(request: TranslationRequest) async throws -> BaseTranslation {
        try Task.checkCancellation()
        let aiTask = Task { try await deviceAI.translate(request: request) }
        let appleTask = Task { try await apple.translate(request.word, direction: request.direction) }
        let dictionaryTask = Task { try await self.dictionaryTranslation(for: request) }
        defer {
            aiTask.cancel()
            appleTask.cancel()
            dictionaryTask.cancel()
        }

        if let translated = await value(of: aiTask, within: deviceAIDeadline) {
            return BaseTranslation(
                meanings: [translated],
                deviceTranslation: translated,
                phonetic: nil,
                pinyin: nil,
                source: .deviceAI
            )
        }

        if let translated = try? await appleTask.value, !translated.isEmpty {
            let dictionary = try? await dictionaryTask.value
            return BaseTranslation(
                meanings: dictionary?.meanings ?? [],
                deviceTranslation: translated,
                phonetic: dictionary?.phonetic,
                pinyin: dictionary?.pinyin,
                source: .appleTranslation
            )
        }

        let dictionary = try await dictionaryTask.value
        guard !dictionary.meanings.isEmpty else { throw TranslationFailure.translationUnavailable }
        return dictionary
    }

    private func value(of task: Task<String, Error>, within deadline: Duration) async -> String? {
        let value: String? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let gate = DeadlineContinuation(continuation)
                Task {
                    let value = try? await task.value
                    gate.resume(returning: value)
                }
                Task {
                    do {
                        try await Task.sleep(for: deadline)
                    } catch {
                        return
                    }
                    if gate.resume(returning: nil) {
                        task.cancel()
                    }
                }
            }
        } onCancel: {
            task.cancel()
        }
        return value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func dictionaryTranslation(for request: TranslationRequest) async throws -> BaseTranslation {
        let exact = try await dictionary.lookup(
            request.word,
            direction: request.direction,
            allowsInflectionFallback: false
        )
        var entry = exact

        if request.direction == .englishToChinese,
           let analysis = EnglishMorphology.analyze(word: request.word, context: request.context),
           analysis.lemma.caseInsensitiveCompare(request.word) != .orderedSame,
           let lemmaEntry = try await dictionary.lookup(
               analysis.lemma,
               direction: request.direction,
               allowsInflectionFallback: false
           ), analysis.isVerb || exact == nil {
            entry = EnglishMorphology.merged(primary: lemmaEntry, secondary: exact)
        }
        if entry == nil {
            entry = try await dictionary.lookup(request.word, direction: request.direction)
        }
        return BaseTranslation(
            meanings: entry?.meanings ?? [],
            deviceTranslation: nil,
            phonetic: entry?.phonetic,
            pinyin: entry?.pinyin,
            source: .dictionary
        )
    }
}

private final class DeadlineContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?

    init(_ continuation: CheckedContinuation<Value?, Never>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(returning value: Value?) -> Bool {
        let continuation = lock.withLock { () -> CheckedContinuation<Value?, Never>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: value)
        return continuation != nil
    }
}

private enum EnglishMorphology {
    struct Analysis { let lemma: String; let isVerb: Bool }

    static func analyze(word: String, context: String) -> Analysis? {
        let source = context.isEmpty ? word : context
        let normalized = word.lowercased()
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = source
        var result: Analysis?
        tagger.enumerateTags(
            in: source.startIndex..<source.endIndex,
            unit: .word,
            scheme: .lemma,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { lemmaTag, tokenRange in
            guard source[tokenRange].lowercased() == normalized,
                  let lemma = lemmaTag?.rawValue.lowercased(), !lemma.isEmpty else { return true }
            result = Analysis(
                lemma: lemma,
                isVerb: tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lexicalClass).0 == .verb
            )
            return false
        }
        return result
    }

    static func merged(primary: DictionaryStore.Entry, secondary: DictionaryStore.Entry?) -> DictionaryStore.Entry {
        var seen: Set<String> = []
        let meanings = (primary.meanings + (secondary?.meanings ?? [])).filter {
            seen.insert($0.lowercased()).inserted
        }
        return DictionaryStore.Entry(
            meanings: Array(meanings.prefix(8)),
            phonetic: secondary?.phonetic ?? primary.phonetic,
            pinyin: secondary?.pinyin ?? primary.pinyin
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
