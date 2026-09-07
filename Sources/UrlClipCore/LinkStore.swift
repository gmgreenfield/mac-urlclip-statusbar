import Foundation
import SQLite3

public struct CapturedLink: Identifiable, Equatable {
    public let id: Int64
    public let url: String
    public let normalizedURL: String
    public let firstSeen: String
    public let lastSeen: String
    public let copyCount: Int
    public let lastClipboard: String
}

public final class LinkStore {
    public static let defaultURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/urlclip-statusbar/links.sqlite3")

    private let db: OpaquePointer?

    public init(path: URL = LinkStore.defaultURL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        guard sqlite3_open(path.path, &handle) == SQLITE_OK else {
            throw StoreError.openFailed(String(cString: sqlite3_errmsg(handle)))
        }

        db = handle
        try execute("PRAGMA journal_mode=WAL")
        try execute(
            """
            CREATE TABLE IF NOT EXISTS links (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                url TEXT NOT NULL,
                normalized_url TEXT NOT NULL UNIQUE,
                first_seen TEXT NOT NULL,
                last_seen TEXT NOT NULL,
                copy_count INTEGER NOT NULL DEFAULT 1,
                last_clipboard TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS idx_links_last_seen
            ON links(last_seen DESC)
            """
        )
    }

    deinit {
        sqlite3_close(db)
    }

    @discardableResult
    public func capture(urls: [String], clipboardText: String, now: Date = Date()) throws -> Int {
        let timestamp = iso8601Timestamp(from: now)
        var count = 0

        for rawURL in urls {
            let url = URLExtractor.trimURL(rawURL)
            guard !url.isEmpty else {
                continue
            }

            let normalizedURL = URLExtractor.normalizedURL(url)
            try withStatement(
                """
                INSERT INTO links (
                    url,
                    normalized_url,
                    first_seen,
                    last_seen,
                    copy_count,
                    last_clipboard
                )
                VALUES (?, ?, ?, ?, 1, ?)
                ON CONFLICT(normalized_url) DO UPDATE SET
                    url = excluded.url,
                    last_seen = excluded.last_seen,
                    copy_count = links.copy_count + 1,
                    last_clipboard = excluded.last_clipboard
                """
            ) { statement in
                bind(url, at: 1, in: statement)
                bind(normalizedURL, at: 2, in: statement)
                bind(timestamp, at: 3, in: statement)
                bind(timestamp, at: 4, in: statement)
                bind(clipboardText, at: 5, in: statement)

                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw StoreError.statementFailed(errorMessage)
                }
            }

            count += 1
        }

        return count
    }

    public func recent(limit: Int = 12) throws -> [CapturedLink] {
        try query(
            """
            SELECT id, url, normalized_url, first_seen, last_seen, copy_count, last_clipboard
            FROM links
            ORDER BY last_seen DESC
            LIMIT ?
            """,
            bindings: { statement in
                sqlite3_bind_int(statement, 1, Int32(limit))
            }
        )
    }

    public func search(_ queryText: String, limit: Int = 20) throws -> [CapturedLink] {
        let needle = "%\(queryText)%"
        return try query(
            """
            SELECT id, url, normalized_url, first_seen, last_seen, copy_count, last_clipboard
            FROM links
            WHERE url LIKE ? OR normalized_url LIKE ? OR last_clipboard LIKE ?
            ORDER BY last_seen DESC
            LIMIT ?
            """,
            bindings: { statement in
                bind(needle, at: 1, in: statement)
                bind(needle, at: 2, in: statement)
                bind(needle, at: 3, in: statement)
                sqlite3_bind_int(statement, 4, Int32(limit))
            }
        )
    }

    public func stats() throws -> (uniqueURLs: Int, capturedCopies: Int) {
        var result = (uniqueURLs: 0, capturedCopies: 0)
        try withStatement("SELECT COUNT(*), COALESCE(SUM(copy_count), 0) FROM links") { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw StoreError.statementFailed(errorMessage)
            }
            result.uniqueURLs = Int(sqlite3_column_int(statement, 0))
            result.capturedCopies = Int(sqlite3_column_int(statement, 1))
        }
        return result
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.statementFailed(errorMessage)
        }
    }

    private func query(_ sql: String, bindings: (OpaquePointer?) -> Void) throws -> [CapturedLink] {
        var links: [CapturedLink] = []
        try withStatement(sql) { statement in
            bindings(statement)
            while sqlite3_step(statement) == SQLITE_ROW {
                links.append(
                    CapturedLink(
                        id: sqlite3_column_int64(statement, 0),
                        url: columnText(statement, 1),
                        normalizedURL: columnText(statement, 2),
                        firstSeen: columnText(statement, 3),
                        lastSeen: columnText(statement, 4),
                        copyCount: Int(sqlite3_column_int(statement, 5)),
                        lastClipboard: columnText(statement, 6)
                    )
                )
            }
        }
        return links
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer?) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.statementFailed(errorMessage)
        }
        defer {
            sqlite3_finalize(statement)
        }
        return try body(statement)
    }

    private var errorMessage: String {
        String(cString: sqlite3_errmsg(db))
    }
}

public enum StoreError: Error, LocalizedError {
    case openFailed(String)
    case statementFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "Could not open database: \(message)"
        case .statementFailed(let message):
            return "Database error: \(message)"
        }
    }
}

private func bind(_ value: String, at index: Int32, in statement: OpaquePointer?) {
    sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
}

private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
    guard let text = sqlite3_column_text(statement, index) else {
        return ""
    }
    return String(cString: text)
}

private func iso8601Timestamp(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}
