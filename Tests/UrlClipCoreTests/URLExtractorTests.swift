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

    func testExtractsPredefinedPatternMatches() {
        let text = "Email hello@example.com from 192.168.1.10 about #AABBCC."
        XCTAssertEqual(
            ClipboardExtractor.extractMatches(
                from: text,
                patterns: ClipboardPatternCatalog.predefined
            ).map(\.value),
            ["hello@example.com", "192.168.1.10", "#AABBCC"]
        )
    }

    func testCustomPatternUsesFirstCaptureGroup() {
        let pattern = ClipboardPattern(
            id: "ticket",
            name: "Tickets",
            pattern: #"\b[A-Z]+-(\d+)\b"#
        )

        XCTAssertEqual(
            ClipboardExtractor.extractMatches(from: "Fix APP-123 today.", patterns: [pattern]),
            [ClipboardMatch(value: "123", patternID: "ticket", patternName: "Tickets")]
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
