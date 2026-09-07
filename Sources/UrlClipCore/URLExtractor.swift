import Foundation

public struct ClipboardPattern: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let pattern: String
    public let trimsURLPunctuation: Bool
    public let caseInsensitiveDeduplication: Bool

    public init(
        id: String,
        name: String,
        pattern: String,
        trimsURLPunctuation: Bool = false,
        caseInsensitiveDeduplication: Bool = false
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.trimsURLPunctuation = trimsURLPunctuation
        self.caseInsensitiveDeduplication = caseInsensitiveDeduplication
    }
}

public struct ClipboardMatch: Equatable, Sendable {
    public let value: String
    public let patternID: String
    public let patternName: String
}

public enum ClipboardPatternCatalog {
    public static let url = ClipboardPattern(
        id: "url",
        name: "URLs",
        pattern: #"(?i)(?:https?://|www\.)[^\s<>"']+"#,
        trimsURLPunctuation: true,
        caseInsensitiveDeduplication: true
    )

    public static let predefined: [ClipboardPattern] = [
        url,
        ClipboardPattern(
            id: "email",
            name: "Email Addresses",
            pattern: #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            caseInsensitiveDeduplication: true
        ),
        ClipboardPattern(
            id: "phone_us",
            name: "US Phone Numbers",
            pattern: #"\b(?:\+?1[-.\s]?)?(?:\([2-9]\d{2}\)|[2-9]\d{2})[-.\s]?[2-9]\d{2}[-.\s]?\d{4}\b"#
        ),
        ClipboardPattern(
            id: "uuid",
            name: "UUIDs",
            pattern: #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b"#,
            caseInsensitiveDeduplication: true
        ),
        ClipboardPattern(
            id: "ipv4",
            name: "IPv4 Addresses",
            pattern: #"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b"#
        ),
        ClipboardPattern(
            id: "hex_color",
            name: "Hex Colors",
            pattern: #"(?i)(?<![0-9a-f])#(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})\b"#,
            caseInsensitiveDeduplication: true
        ),
        ClipboardPattern(
            id: "git_sha",
            name: "Git SHAs",
            pattern: #"(?i)\b[0-9a-f]{7,40}\b"#,
            caseInsensitiveDeduplication: true
        )
    ]

    public static let defaultEnabledPatternIDs: Set<String> = Set(predefined.map(\.id))
}

public enum ClipboardExtractor {
    public static func extractMatches(from text: String, patterns: [ClipboardPattern]) -> [ClipboardMatch] {
        var matches: [PendingMatch] = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.pattern) else {
                continue
            }

            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
                guard let match else {
                    return
                }

                let selectedRange = firstCaptureRange(in: match)
                guard
                    selectedRange.location != NSNotFound,
                    let swiftRange = Range(selectedRange, in: text)
                else {
                    return
                }

                let value = normalizedMatchValue(
                    String(text[swiftRange]),
                    trimsURLPunctuation: pattern.trimsURLPunctuation
                )
                guard !value.isEmpty else {
                    return
                }

                matches.append(
                    PendingMatch(
                        range: selectedRange,
                        value: value,
                        pattern: pattern
                    )
                )
            }
        }

        return matches
            .sorted {
                if $0.range.location == $1.range.location {
                    return $0.range.length > $1.range.length
                }
                return $0.range.location < $1.range.location
            }
            .reduce(into: DeduplicatedMatches()) { result, match in
                let key = match.pattern.caseInsensitiveDeduplication
                    ? match.value.lowercased()
                    : match.value
                guard !result.seenKeys.contains(key) else {
                    return
                }

                result.seenKeys.insert(key)
                result.matches.append(
                    ClipboardMatch(
                        value: match.value,
                        patternID: match.pattern.id,
                        patternName: match.pattern.name
                    )
                )
            }
            .matches
    }

    public static func normalizedCapturedValue(_ value: String) -> String {
        var value = URLExtractor.trimURL(value.trimmingCharacters(in: .whitespacesAndNewlines))
        if value.lowercased().hasPrefix("www.") {
            value = "https://\(value)"
        }

        guard value.isLikelyURL, var components = URLComponents(string: value) else {
            return value.lowercased()
        }

        components.scheme = components.scheme?.lowercased() ?? "https"
        components.host = components.host?.lowercased()
        components.fragment = nil

        if (components.scheme == "https" && components.port == 443)
            || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }

        if let path = components.path.isEmpty ? "/" : components.path.removingTrailingSlash() {
            components.path = path
        }

        return components.string ?? value
    }

    public static func isLikelyURL(_ value: String) -> Bool {
        value.isLikelyURL || value.lowercased().hasPrefix("www.")
    }

    private static func firstCaptureRange(in match: NSTextCheckingResult) -> NSRange {
        guard match.numberOfRanges > 1 else {
            return match.range
        }

        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            if range.location != NSNotFound {
                return range
            }
        }

        return match.range
    }

    private static func normalizedMatchValue(_ value: String, trimsURLPunctuation: Bool) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimsURLPunctuation ? URLExtractor.trimURL(trimmed) : trimmed
    }
}

public enum URLExtractor {
    private static let trailingPunctuation = Set(".,;:!?]}>\"'")

    public static func extractURLs(from text: String) -> [String] {
        ClipboardExtractor.extractMatches(from: text, patterns: [ClipboardPatternCatalog.url])
            .map(\.value)
    }

    public static func trimURL(_ url: String) -> String {
        var value = url

        while let last = value.last, trailingPunctuation.contains(last) {
            value.removeLast()
        }

        while value.last == ")", value.filter({ $0 == "(" }).count < value.filter({ $0 == ")" }).count {
            value.removeLast()
        }

        return value
    }

    public static func normalizedURL(_ url: String) -> String {
        ClipboardExtractor.normalizedCapturedValue(url)
    }
}

private struct PendingMatch {
    let range: NSRange
    let value: String
    let pattern: ClipboardPattern
}

private struct DeduplicatedMatches {
    var matches: [ClipboardMatch] = []
    var seenKeys = Set<String>()
}

private extension String {
    var isLikelyURL: Bool {
        let lowercasedValue = lowercased()
        return lowercasedValue.hasPrefix("http://")
            || lowercasedValue.hasPrefix("https://")
    }

    func removingTrailingSlash() -> String? {
        guard self != "/" else {
            return self
        }
        return hasSuffix("/") ? String(dropLast()) : self
    }
}
