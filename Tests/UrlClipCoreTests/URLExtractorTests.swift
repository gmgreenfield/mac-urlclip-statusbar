import XCTest
@testable import UrlClipCore

final class URLExtractorTests: XCTestCase {
    func testExtractsAndTrimsURLs() {
        let text = "Read https://example.com/a(b). Then see <https://foo.test/x?y=1>."
        XCTAssertEqual(
            URLExtractor.extractURLs(from: text),
            ["https://example.com/a(b)", "https://foo.test/x?y=1"]
        )
    }

    func testExtractsWWWURLs() {
        XCTAssertEqual(
            URLExtractor.extractURLs(from: "saved from www.example.com/path."),
            ["www.example.com/path"]
        )
    }

    func testNormalizesCommonVariants() {
        XCTAssertEqual(
            URLExtractor.normalizedURL("HTTPS://Example.COM:443/path/#section"),
            "https://example.com/path"
        )
        XCTAssertEqual(
            URLExtractor.normalizedURL("www.Example.com"),
            "https://www.example.com/"
        )
    }
}
