import Foundation

public enum URLExtractor {
    private static let pattern = #"(?i)(?:https?://|www\.)[^\s<>"']+"#
    private static let trailingPunctuation = Set(".,;:!?]}>\"'")

    public static func extractURLs(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var urls: [String] = []
        var seen = Set<String>()

        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard
                let range = match?.range,
                let swiftRange = Range(range, in: text)
            else {
                return
            }

            let url = trimURL(String(text[swiftRange]))
            guard !url.isEmpty, !seen.contains(url) else {
                return
            }

            seen.insert(url)
            urls.append(url)
        }

        return urls
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
        var value = trimURL(url)
        if value.lowercased().hasPrefix("www.") {
            value = "https://\(value)"
        }

        guard var components = URLComponents(string: value) else {
            return value
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
}

private extension String {
    func removingTrailingSlash() -> String? {
        guard self != "/" else {
            return self
        }
        return hasSuffix("/") ? String(dropLast()) : self
    }
}
