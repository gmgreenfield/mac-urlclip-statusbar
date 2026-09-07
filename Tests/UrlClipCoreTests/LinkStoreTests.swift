import XCTest
@testable import UrlClipCore

final class LinkStoreTests: XCTestCase {
    func testStoreDedupesByNormalizedURL() throws {
        let store = try LinkStore(path: temporaryDatabaseURL())
        try store.capture(urls: ["https://example.com/a#one"], clipboardText: "first")
        try store.capture(urls: ["https://EXAMPLE.com/a#two"], clipboardText: "second")

        let links = try store.recent()
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].copyCount, 2)
        XCTAssertEqual(links[0].lastClipboard, "second")
    }

    func testStoreTrimsURLs() throws {
        let store = try LinkStore(path: temporaryDatabaseURL())
        try store.capture(urls: ["www.example.com/path."], clipboardText: "clipboard")

        let links = try store.recent()
        XCTAssertEqual(links[0].url, "www.example.com/path")
        XCTAssertEqual(links[0].normalizedURL, "https://www.example.com/path")
    }

    func testStoreCapturesAndDedupesRegexMatches() throws {
        let store = try LinkStore(path: temporaryDatabaseURL())
        try store.capture(
            matches: [
                ClipboardMatch(value: "Hello@Example.com", patternID: "email", patternName: "Email Addresses")
            ],
            clipboardText: "first"
        )
        try store.capture(
            matches: [
                ClipboardMatch(value: "hello@example.com", patternID: "email", patternName: "Email Addresses")
            ],
            clipboardText: "second"
        )

        let links = try store.recent()
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].url, "hello@example.com")
        XCTAssertEqual(links[0].normalizedURL, "hello@example.com")
        XCTAssertEqual(links[0].copyCount, 2)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite3")
    }
}
