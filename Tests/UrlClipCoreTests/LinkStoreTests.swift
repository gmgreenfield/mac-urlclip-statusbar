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

    private func temporaryDatabaseURL() -> URL {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite3")
    }
}
