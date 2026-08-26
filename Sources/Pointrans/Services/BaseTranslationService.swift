import Foundation
import NaturalLanguage
@preconcurrency import Translation

protocol DeviceTranslating: Sendable {
    func translate(_ text: String, direction: TranslationDirection) async throws -> String
}

private enum EnglishMorphology {
    struct Analysis {
        let lemma: String
        let isVerb: Bool
    }

    static func analyze(word: String, context: String) -> Analysis? {
        let normalizedWord = word.lowercased()
        let source = context.isEmpty ? word : context
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = source

        var result: Analysis?
        tagger.enumerateTags(
            in: source.startIndex..<source.endIndex,
            unit: .word,
            scheme: .lemma,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { lemmaTag, tokenRange in
            guard source[tokenRange].lowercased() == normalizedWord,
                  let lemma = lemmaTag?.rawValue.lowercased(),
                  !lemma.isEmpty else { return true }
            let lexicalClass = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lexicalClass).0
            result = Analysis(lemma: lemma, isVerb: lexicalClass == .verb)
            return false
        }

        if let result { return result }

        tagger.string = word
        let lemma = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma).0?.rawValue.lowercased()
        let lexicalClass = tagger.tag(at: word.startIndex, unit: .word, scheme: .lexicalClass).0
        guard let lemma, !lemma.isEmpty else { return nil }
        return Analysis(lemma: lemma, isVerb: lexicalClass == .verb)
    }
}

actor AppleTranslationService: DeviceTranslating {
    enum AppleTranslationError: Error, Sendable {
        case languagePackUnavailable
    }

    private var sessions: [TranslationDirection: TranslationSession] = [:]

    func isReady(for direction: TranslationDirection) async -> Bool {
        let session = session(for: direction)
        return await session.isReady
    }

    func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        try Task.checkCancellation()
        let session = session(for: direction)
        guard await session.isReady else { throw AppleTranslationError.languagePackUnavailable }
        let response = try await session.translate(text)
        try Task.checkCancellation()
        return response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel(direction: TranslationDirection) {
        sessions[direction]?.cancel()
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
    private let apple: any DeviceTranslating

    init(dictionary: DictionaryStore, apple: any DeviceTranslating = AppleTranslationService()) {
        self.dictionary = dictionary
        self.apple = apple
    }

    func translate(
        word: String,
        context: String,
        direction: TranslationDirection
    ) async throws -> BaseTranslation {
        try Task.checkCancellation()
        let exact = try await dictionary.lookup(
            word,
            direction: direction,
            allowsInflectionFallback: false
        )
        var entry = exact

        if direction == .englishToChinese,
           let analysis = EnglishMorphology.analyze(word: word, context: context),
           analysis.lemma.caseInsensitiveCompare(word) != .orderedSame,
           let lemmaEntry = try await dictionary.lookup(
               analysis.lemma,
               direction: direction,
               allowsInflectionFallback: false
           ) {
            if analysis.isVerb || exact == nil {
                entry = merged(primary: lemmaEntry, secondary: exact)
            }
        }

        if entry == nil {
            entry = try await dictionary.lookup(word, direction: direction)
        }
        return BaseTranslation(
            meanings: entry?.meanings ?? [],
            deviceTranslation: nil,
            phonetic: entry?.phonetic,
            pinyin: entry?.pinyin,
            source: .dictionary
        )
    }

    private func merged(
        primary: DictionaryStore.Entry,
        secondary: DictionaryStore.Entry?
    ) -> DictionaryStore.Entry {
        var seen: Set<String> = []
        let meanings = (primary.meanings + (secondary?.meanings ?? [])).filter { meaning in
            seen.insert(meaning.lowercased()).inserted
        }
        return DictionaryStore.Entry(
            meanings: Array(meanings.prefix(8)),
            phonetic: secondary?.phonetic ?? primary.phonetic,
            pinyin: secondary?.pinyin ?? primary.pinyin
        )
    }

    func enrich(
        _ base: BaseTranslation,
        word: String,
        context: String,
        direction: TranslationDirection
    ) async throws -> BaseTranslation {
        do {
            let translated = try await apple.translate(word, direction: direction)
            return BaseTranslation(
                meanings: base.meanings,
                deviceTranslation: translated,
                phonetic: base.phonetic,
                pinyin: base.pinyin,
                source: base.meanings.isEmpty ? .appleTranslation : .dictionaryAndApple
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard !base.meanings.isEmpty else { throw error }
            return base
        }
    }
}
