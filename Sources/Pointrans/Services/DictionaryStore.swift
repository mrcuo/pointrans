import Foundation
import SQLite3

actor DictionaryStore {
    enum StoreError: Error, Sendable {
        case resourceMissing
        case openFailed(String)
        case queryFailed(String)
    }

    struct Entry: Equatable, Sendable {
        let meanings: [String]
        let phonetic: String?
        let pinyin: String?
    }

    private final class SQLiteHandle: @unchecked Sendable {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
        deinit { sqlite3_close_v2(pointer) }
    }

    private var database: SQLiteHandle?
    private let databaseURL: URL

    init(databaseURL: URL? = nil, bundle: Bundle = .main) throws {
        if let databaseURL {
            self.databaseURL = databaseURL
        } else if let resource = bundle.url(forResource: "Dictionary", withExtension: "sqlite3") {
            self.databaseURL = resource
        } else {
            throw StoreError.resourceMissing
        }
    }

    func lookup(
        _ rawTerm: String,
        direction: TranslationDirection,
        allowsInflectionFallback: Bool = true
    ) throws -> Entry? {
        let term = normalizedTerm(rawTerm, direction: direction)
        guard !term.isEmpty else { return nil }
        try ensureOpen()

        let table = direction == .englishToChinese ? "en_zh" : "zh_en"
        let auxiliaryColumn = direction == .englishToChinese ? "phonetic" : "pinyin"
        let sql = "SELECT meanings, \(auxiliaryColumn) FROM \(table) WHERE term = ? LIMIT 1"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database?.pointer, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(lastError())
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, term, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            if allowsInflectionFallback,
               direction == .englishToChinese,
               let stem = englishStem(term),
               stem != term {
                return try lookup(stem, direction: direction, allowsInflectionFallback: false)
            }
            return nil
        }

        let meaningsText = String(cString: sqlite3_column_text(statement, 0))
        let auxiliary = sqlite3_column_text(statement, 1).map { String(cString: $0) }
        let meanings = meaningsText
            .components(separatedBy: " / ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Entry(
            meanings: meanings,
            phonetic: direction == .englishToChinese ? auxiliary : nil,
            pinyin: direction == .chineseToEnglish ? auxiliary : nil
        )
    }

    private func ensureOpen() throws {
        guard database == nil else { return }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK else {
            let message = lastError(handle)
            if let handle { sqlite3_close_v2(handle) }
            throw StoreError.openFailed(message)
        }
        if let handle { database = SQLiteHandle(handle) }
    }

    private func normalizedTerm(_ term: String, direction: TranslationDirection) -> String {
        let value = term.trimmingCharacters(in: .whitespacesAndNewlines)
        return direction == .englishToChinese ? value.lowercased() : value
    }

    private func englishStem(_ word: String) -> String? {
        guard word.count > 3 else { return nil }
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("ing"), word.count > 5 { return String(word.dropLast(3)) }
        if word.hasSuffix("ed"), word.count > 4 { return String(word.dropLast(2)) }
        if word.hasSuffix("es"), word.count > 4 { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), word.count > 3 { return String(word.dropLast()) }
        return nil
    }

    private func lastError(_ handle: OpaquePointer? = nil) -> String {
        let active = handle ?? database?.pointer
        guard let active, let message = sqlite3_errmsg(active) else { return "Unknown SQLite error" }
        return String(cString: message)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
