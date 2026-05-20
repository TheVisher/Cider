import Foundation

struct BookmarkEnrichmentPayload {
    let title: String?
    let thumbnailURL: URL?
    let screenshotData: Data?
    let thumbnailFallbackData: Data?
    let recipeExtractionText: String?
    var carouselImageURLs: [URL]?  // Additional images (e.g. Reddit gallery)

    init(
        title: String?,
        thumbnailURL: URL?,
        screenshotData: Data?,
        thumbnailFallbackData: Data? = nil,
        recipeExtractionText: String? = nil,
        carouselImageURLs: [URL]? = nil
    ) {
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.screenshotData = screenshotData
        self.thumbnailFallbackData = thumbnailFallbackData
        self.recipeExtractionText = recipeExtractionText
        self.carouselImageURLs = carouselImageURLs
    }
}

enum EnrichmentRetryThresholds {
    static let firstHour: TimeInterval = 60 * 60
    static let socialEarly: TimeInterval = 60 * 5
    static let socialSteady: TimeInterval = 60 * 45
    static let noThumbnailEarly: TimeInterval = 60 * 10
    static let noThumbnailSteady: TimeInterval = 60 * 60 * 3
    static let defaultSteady: TimeInterval = 60 * 60 * 6
}

enum BookmarkMetadataParser {
    private static let titleRegex = try? NSRegularExpression(
        pattern: #"(?is)<title\b[^>]*>(.*?)</title>"#,
        options: []
    )
    private static let metaRegex = try? NSRegularExpression(
        pattern: #"(?is)<meta\b[^>]*>"#,
        options: []
    )
    private static let linkRegex = try? NSRegularExpression(
        pattern: #"(?is)<link\b[^>]*>"#,
        options: []
    )
    private static let scriptRegex = try? NSRegularExpression(
        pattern: #"(?is)<script\b([^>]*)>(.*?)</script>"#,
        options: []
    )
    private static let attributeRegex = try? NSRegularExpression(
        pattern: #"([A-Za-z_:][A-Za-z0-9_:\-\.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
        options: []
    )

    static func parse(html: String, pageURL: URL) -> BookmarkEnrichmentPayload? {
        let host = normalizedHost(for: pageURL)

        let titleCandidates = [
            metaContent(html: html, keys: [("property", "og:title")]),
            metaContent(html: html, keys: [("name", "twitter:title")]),
            metaContent(html: html, keys: [("name", "title")]),
            jsonLDTitle(html: html),
            titleTagContent(html: html),
        ]

        let title = titleCandidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        let imageMetaRaw = [
            metaContent(html: html, keys: [("property", "og:image")]),
            metaContent(html: html, keys: [("name", "twitter:image")]),
            metaContent(html: html, keys: [("name", "twitter:image:src")]),
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        let imageMetaURL = imageMetaRaw.flatMap { resolvedRemoteURL(from: $0, baseURL: pageURL) }
        let jsonLDURL = jsonLDImageURL(html: html, pageURL: pageURL)
        let siteAdapterURL = siteSpecificThumbnailURL(html: html, pageURL: pageURL)
        let thumbnailCandidates: [URL?]
        if host.contains("reddit.com") {
            // Reddit meta tags frequently point to removed/default placeholders.
            thumbnailCandidates = [
                siteAdapterURL,
                jsonLDURL,
            ]
        } else if host == "x.com" || host == "twitter.com" || host.contains("digg.com") {
            // Prefer real media URLs for social feeds; icon fallbacks are too noisy here.
            thumbnailCandidates = [
                siteAdapterURL,
                imageMetaURL,
                jsonLDURL,
            ]
        } else {
            thumbnailCandidates = [
                imageMetaURL,
                jsonLDURL,
                siteAdapterURL,
            ]
        }

        let thumbnailURL = thumbnailCandidates
            .compactMap { $0 }
            .first(where: { isThumbnailCandidateAcceptable($0, for: pageURL) })

        let recipeExtractionText = recipeJSONLDExtractionText(html: html)
        guard title != nil || thumbnailURL != nil || recipeExtractionText != nil else { return nil }
        return BookmarkEnrichmentPayload(
            title: title,
            thumbnailURL: thumbnailURL,
            screenshotData: nil,
            recipeExtractionText: recipeExtractionText
        )
    }

    private static func titleTagContent(html: String) -> String? {
        guard let titleRegex else { return nil }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = titleRegex.firstMatch(in: html, options: [], range: nsRange),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return decodeHTMLEntities(String(html[range]))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func metaContent(html: String, keys: [(String, String)]) -> String? {
        guard let metaRegex else { return nil }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = metaRegex.matches(in: html, options: [], range: nsRange)

        for match in matches {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            let attributes = parseAttributes(tag)

            let isMatch = keys.allSatisfy { key, expectedValue in
                attributes[key.lowercased()]?.lowercased() == expectedValue.lowercased()
            }
            if !isMatch { continue }

            if let content = attributes["content"], !content.isEmpty {
                return decodeHTMLEntities(content)
            }
        }

        return nil
    }

    private static func jsonLDTitle(html: String) -> String? {
        for object in jsonLDObjects(fromHTML: html) {
            if let title = firstJSONLDString(
                forKeys: ["headline", "name", "title"],
                in: object
            ) {
                return title
            }
        }
        return nil
    }

    private static func jsonLDImageURL(html: String, pageURL: URL) -> URL? {
        for object in jsonLDObjects(fromHTML: html) {
            if let imageRaw = firstJSONLDString(
                forKeys: ["image", "thumbnailUrl", "thumbnailURL", "contentUrl", "primaryImageOfPage", "associatedMedia"],
                in: object
            ),
               let imageURL = resolvedRemoteURL(from: imageRaw, baseURL: pageURL) {
                return imageURL
            }
        }
        return nil
    }

    private static func jsonLDObjects(fromHTML html: String) -> [Any] {
        guard let scriptRegex else { return [] }
        // Cap input to first 100KB to prevent ReDoS on pages with large inline JS bundles.
        // JSON-LD <script> tags are always in the <head>, well within this limit.
        let cappedHTML = html.count > 100_000 ? String(html.prefix(100_000)) : html
        let nsRange = NSRange(cappedHTML.startIndex..<cappedHTML.endIndex, in: cappedHTML)
        let matches = scriptRegex.matches(in: cappedHTML, options: [], range: nsRange)
        guard !matches.isEmpty else { return [] }

        var results: [Any] = []
        results.reserveCapacity(matches.count)

        for match in matches {
            guard let attrsRange = Range(match.range(at: 1), in: cappedHTML),
                  let bodyRange = Range(match.range(at: 2), in: cappedHTML) else {
                continue
            }

            let attributes = parseAttributes(String(cappedHTML[attrsRange]))
            guard let scriptType = attributes["type"]?.lowercased(),
                  scriptType.contains("application/ld+json") else {
                continue
            }

            let scriptBody = String(cappedHTML[bodyRange])
            guard let object = parseJSONLDObject(from: scriptBody) else { continue }
            results.append(object)
        }

        return results
    }

    private static func recipeJSONLDExtractionText(html: String) -> String? {
        guard let scriptRegex else { return nil }
        let cappedHTML = html.count > 200_000 ? String(html.prefix(200_000)) : html
        let nsRange = NSRange(cappedHTML.startIndex..<cappedHTML.endIndex, in: cappedHTML)
        let matches = scriptRegex.matches(in: cappedHTML, options: [], range: nsRange)

        for match in matches {
            guard let attrsRange = Range(match.range(at: 1), in: cappedHTML),
                  let bodyRange = Range(match.range(at: 2), in: cappedHTML) else { continue }

            let attributes = parseAttributes(String(cappedHTML[attrsRange]))
            guard let scriptType = attributes["type"]?.lowercased(),
                  scriptType.contains("application/ld+json") else { continue }

            let scriptBody = String(cappedHTML[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let object = parseJSONLDObject(from: scriptBody), jsonLDContainsRecipe(object) else { continue }

            return """
            Cider native recipe extraction source:
            <script type=\"application/ld+json\">
            \(scriptBody)
            </script>
            """
        }

        return nil
    }

    private static func jsonLDContainsRecipe(_ object: Any) -> Bool {
        if let dict = object as? [String: Any] {
            if jsonLDTypeContainsRecipe(dict["@type"]) { return true }
            if let graph = dict["@graph"] as? [Any], graph.contains(where: jsonLDContainsRecipe) { return true }
            if let mainEntity = dict["mainEntity"], jsonLDContainsRecipe(mainEntity) { return true }
            if let itemListElement = dict["itemListElement"], jsonLDContainsRecipe(itemListElement) { return true }
        }
        if let array = object as? [Any] {
            return array.contains(where: jsonLDContainsRecipe)
        }
        return false
    }

    private static func jsonLDTypeContainsRecipe(_ value: Any?) -> Bool {
        if let string = value as? String { return string.localizedCaseInsensitiveContains("Recipe") }
        if let strings = value as? [String] { return strings.contains { $0.localizedCaseInsensitiveContains("Recipe") } }
        if let values = value as? [Any] { return values.contains { jsonLDTypeContainsRecipe($0) } }
        return false
    }

    private static func parseJSONLDObject(from raw: String) -> Any? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidates = jsonLDCandidates(from: trimmed)
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                return object
            }
        }

        return nil
    }

    private static func jsonLDCandidates(from raw: String) -> [String] {
        var normalized = raw
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.hasSuffix(";") {
            normalized.removeLast()
            normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return [raw, normalized]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func firstJSONLDString(forKeys keys: [String], in object: Any) -> String? {
        for key in keys {
            var values: [Any] = []
            collectJSONValues(forKey: key, from: object, into: &values)
            for value in values {
                if let stringValue = stringFromJSONValue(value), !stringValue.isEmpty {
                    return decodeEscapedURLString(stringValue)
                }
            }
        }
        return nil
    }

    private static func collectJSONValues(forKey key: String, from object: Any, depth: Int = 0, into values: inout [Any]) {
        guard depth < 20 else { return } // Prevent stack overflow on crafted JSON-LD
        if let dictionary = object as? [String: Any] {
            for (candidateKey, value) in dictionary {
                if candidateKey.lowercased() == key.lowercased() {
                    values.append(value)
                }
                collectJSONValues(forKey: key, from: value, depth: depth + 1, into: &values)
            }
            return
        }

        if let array = object as? [Any] {
            for item in array {
                collectJSONValues(forKey: key, from: item, depth: depth + 1, into: &values)
            }
        }
    }

    private static func stringFromJSONValue(_ value: Any) -> String? {
        if let string = value as? String {
            return string
        }

        if let array = value as? [Any] {
            for item in array {
                if let resolved = stringFromJSONValue(item) {
                    return resolved
                }
            }
            return nil
        }

        if let dictionary = value as? [String: Any] {
            let prioritizedKeys = ["url", "contentUrl", "thumbnailUrl", "thumbnailURL"]
            for key in prioritizedKeys {
                if let nested = dictionary[key],
                   let resolved = stringFromJSONValue(nested) {
                    return resolved
                }
            }
        }

        return nil
    }

    private static func siteSpecificThumbnailURL(html: String, pageURL: URL) -> URL? {
        let host = normalizedHost(for: pageURL)
        if host.contains("reddit.com") {
            return redditThumbnailURL(html: html, pageURL: pageURL)
        }
        if host == "x.com" || host == "twitter.com" {
            return xThumbnailURL(html: html, pageURL: pageURL)
        }
        return nil
    }

    private static func redditThumbnailURL(html: String, pageURL: URL) -> URL? {
        let patterns = [
            #"(?is)(https?:\\/\\/(?:i|preview)\.redd\.it\\/[^"'\\s<]+)"#,
            #"(?is)(https?://(?:i|preview)\.redd\.it/[^"'\\s<]+)"#,
            #"(?is)(https?:\\/\\/external-preview\.redd\.it\\/[^"'\\s<]+)"#,
            #"(?is)(https?://external-preview\.redd\.it/[^"'\\s<]+)"#,
        ]

        var best: (score: Int, url: URL)?
        for pattern in patterns {
            for match in regexCaptureMatches(pattern: pattern, in: html) {
                guard let resolved = resolvedRemoteURL(from: match.rawValue, baseURL: pageURL) else { continue }
                let score = redditThumbnailCandidateScore(url: resolved, context: match.context)
                guard score >= 0 else { continue }
                if best == nil || score > best!.score {
                    best = (score, resolved)
                }
            }
        }

        return best?.url
    }

    private static func xThumbnailURL(html: String, pageURL: URL) -> URL? {
        let patterns = [
            #"(?is)(https?:\\/\\/pbs\.twimg\.com\\/(?:media|amplify_video_thumb)\\/[^"'\\s<]+)"#,
            #"(?is)(https?://pbs\.twimg\.com/(?:media|amplify_video_thumb)/[^"'\\s<]+)"#,
        ]

        for pattern in patterns {
            if let raw = firstRegexCapture(pattern: pattern, in: html),
               let resolved = resolvedRemoteURL(from: raw, baseURL: pageURL) {
                return resolved
            }
        }

        return nil
    }

    private static func faviconURL(html: String, pageURL: URL) -> URL? {
        let host = normalizedHost(for: pageURL)
        if host.contains("reddit.com")
            || host == "x.com"
            || host == "twitter.com"
            || host.contains("digg.com")
            || host.contains("tiktok.com") {
            return nil
        }

        guard let linkRegex else { return defaultFaviconURL(for: pageURL) }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = linkRegex.matches(in: html, options: [], range: nsRange)

        var bestCandidate: (priority: Int, url: URL)?
        for match in matches {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            let attributes = parseAttributes(tag)
            guard let href = attributes["href"], !href.isEmpty else { continue }

            let rel = attributes["rel"]?.lowercased() ?? ""
            let priority: Int
            if rel.contains("apple-touch-icon") {
                priority = 0
            } else if rel.contains("shortcut icon") {
                priority = 1
            } else if rel.contains("icon") || rel.contains("mask-icon") {
                priority = 2
            } else {
                continue
            }

            guard let resolved = resolvedRemoteURL(from: href, baseURL: pageURL) else { continue }
            if let currentBest = bestCandidate {
                if priority < currentBest.priority {
                    bestCandidate = (priority, resolved)
                }
            } else {
                bestCandidate = (priority, resolved)
            }
        }

        return bestCandidate?.url ?? defaultFaviconURL(for: pageURL)
    }

    private static func isThumbnailCandidateAcceptable(_ url: URL, for pageURL: URL) -> Bool {
        if isLikelyIconURL(url) || isMalformedImageFragment(url) {
            return false
        }

        let host = normalizedHost(for: pageURL)
        if host.contains("reddit.com"),
           isLikelyRedditPlaceholderImage(url: url) {
            return false
        }
        return true
    }

    private static func isLikelyIconURL(_ url: URL) -> Bool {
        let fingerprint = [
            url.host ?? "",
            url.path,
            url.query ?? "",
        ]
            .joined(separator: " ")
            .lowercased()

        let iconFragments = [
            "favicon",
            "apple-touch-icon",
            "touch-icon",
            "mask-icon",
            "/site-icon",
            "/app-icon",
        ]

        return iconFragments.contains { fingerprint.contains($0) }
    }

    private static func isMalformedImageFragment(_ url: URL) -> Bool {
        let fingerprint = [
            url.path,
            url.query ?? "",
            url.fragment ?? "",
        ]
            .joined(separator: " ")
            .lowercased()

        return fingerprint.contains("%22")
            || fingerprint.contains("\"")
            || fingerprint.contains("%2c%22")
            || fingerprint.contains("created_time")
            || fingerprint.contains("createdtime")
    }

    private static func isLikelyRedditPlaceholderImage(url: URL) -> Bool {
        let fingerprint = [
            url.host ?? "",
            url.path,
            url.query ?? "",
        ]
            .joined(separator: " ")
            .lowercased()

        let blockedFragments = [
            "if-you-are-looking-for-an-image",
            "if_you_are_looking_for_an_image",
            "/removed.",
            "/deleted.",
            "/default.",
            "/self.",
            "/nsfw.",
            "/spoiler.",
            "preview.redd.it/default",
            "preview.redd.it/self",
            "preview.redd.it/nsfw",
            "preview.redd.it/spoiler",
        ]

        return blockedFragments.contains { fragment in
            fingerprint.contains(fragment)
        }
    }

    private static func redditThumbnailCandidateScore(url: URL, context: String) -> Int {
        if isLikelyRedditPlaceholderImage(url: url) || isMalformedImageFragment(url) {
            return -1
        }

        let normalizedContext = context.lowercased()
        var score = 0
        let positiveContextFragments = [
            "data-testid=\"post-media\"",
            "data-testid='post-media'",
            "shreddit-post",
            "url_overridden_by_dest",
            "media_metadata",
            "gallery_data",
            "post-media",
            "preview",
        ]
        for fragment in positiveContextFragments where normalizedContext.contains(fragment) {
            score += 10
        }

        let blockedContextFragments = [
            "promotedlink",
            "promoted",
            "advertis",
            "ad-container",
            "ad_",
            "right-sidebar",
            "sidebar",
            "community-banner",
            "subreddit-icon",
            "avatar",
            "user-icon",
        ]
        let blockedScore = blockedContextFragments.reduce(0) { partial, fragment in
            normalizedContext.contains(fragment) ? partial + 12 : partial
        }
        score -= blockedScore
        if score < 0 {
            return -1
        }

        let host = normalizedHost(for: url)
        if host == "i.redd.it" {
            score += 6
        } else if host == "preview.redd.it" || host == "external-preview.redd.it" || host == "cf.preview.redd.it" {
            score += 4
        }

        return score
    }

    private static func defaultFaviconURL(for pageURL: URL) -> URL? {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            return nil
        }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func parseAttributes(_ tag: String) -> [String: String] {
        guard let attributeRegex else { return [:] }
        let nsRange = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        let matches = attributeRegex.matches(in: tag, options: [], range: nsRange)

        var attributes: [String: String] = [:]
        attributes.reserveCapacity(matches.count)

        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let name = String(tag[nameRange]).lowercased()

            let value: String
            if let range = Range(match.range(at: 2), in: tag) {
                value = String(tag[range])
            } else if let range = Range(match.range(at: 3), in: tag) {
                value = String(tag[range])
            } else if let range = Range(match.range(at: 4), in: tag) {
                value = String(tag[range])
            } else {
                continue
            }

            attributes[name] = value
        }

        return attributes
    }

    private static func resolvedURL(from rawValue: String, baseURL: URL) -> URL? {
        let decoded = decodeEscapedURLString(rawValue)
        if let absolute = URL(string: decoded), absolute.scheme != nil {
            return absolute
        }
        return URL(string: decoded, relativeTo: baseURL)?.absoluteURL
    }

    private static func resolvedRemoteURL(from rawValue: String, baseURL: URL) -> URL? {
        guard let resolved = resolvedURL(from: rawValue, baseURL: baseURL),
              let scheme = resolved.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            return nil
        }
        return resolved
    }

    static func normalizedHost(for pageURL: URL) -> String {
        let host = pageURL.host?.lowercased() ?? ""
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        if host.hasPrefix("m.") {
            return String(host.dropFirst(2))
        }
        return host
    }

    private static func firstRegexCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange) else {
            return nil
        }

        let captureRange: NSRange
        if match.numberOfRanges > 1 {
            captureRange = match.range(at: 1)
        } else {
            captureRange = match.range(at: 0)
        }

        guard let range = Range(captureRange, in: text) else {
            return nil
        }
        return String(text[range])
    }

    private struct RegexCaptureMatch {
        let rawValue: String
        let context: String
    }

    private static func regexCaptureMatches(pattern: String, in text: String, contextRadius: Int = 80) -> [RegexCaptureMatch] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)

        return matches.compactMap { match in
            let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
            guard let range = Range(captureRange, in: text) else { return nil }

            let lower = text.index(range.lowerBound, offsetBy: -contextRadius, limitedBy: text.startIndex) ?? text.startIndex
            let upper = text.index(range.upperBound, offsetBy: contextRadius, limitedBy: text.endIndex) ?? text.endIndex
            return RegexCaptureMatch(
                rawValue: String(text[range]),
                context: String(text[lower..<upper])
            )
        }
    }

    private static func decodeEscapedURLString(_ value: String) -> String {
        var decoded = decodeHTMLEntities(value)
        decoded = decoded
            .replacingOccurrences(of: #"\\/"#, with: "/", options: .regularExpression)
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u003A", with: ":")
            .replacingOccurrences(of: "\\u003D", with: "=")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\u0025", with: "%")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if decoded.hasPrefix("\""), decoded.hasSuffix("\""), decoded.count > 1 {
            decoded.removeFirst()
            decoded.removeLast()
        }

        return decoded
    }

    static let namedEntities: [String: String] = [
        "&quot;": "\"", "&apos;": "'", "&#39;": "'",
        "&gt;": ">", "&lt;": "<",
        "&ndash;": "\u{2013}", "&mdash;": "\u{2014}",
        "&lsquo;": "\u{2018}", "&rsquo;": "\u{2019}",
        "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}",
        "&nbsp;": " ", "&hellip;": "\u{2026}",
        "&trade;": "\u{2122}", "&copy;": "\u{00A9}", "&reg;": "\u{00AE}",
        "&bull;": "\u{2022}", "&middot;": "\u{00B7}",
        "&laquo;": "\u{00AB}", "&raquo;": "\u{00BB}",
        "&amp;": "&",  // must be last
    ]
    static let numericEntityRegex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")

    static func decodeHTMLEntities(_ value: String) -> String {
        var result = value
        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Decode numeric entities: &#123; and &#x1F4A9;
        if let regex = numericEntityRegex {
            let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = regex.matches(in: result, range: nsRange).reversed()
            for match in matches {
                guard let fullRange = Range(match.range, in: result),
                      let hexRange = Range(match.range(at: 1), in: result),
                      let numRange = Range(match.range(at: 2), in: result) else { continue }
                let isHex = !result[hexRange].isEmpty
                let numStr = String(result[numRange])
                let codePoint = isHex ? UInt32(numStr, radix: 16) : UInt32(numStr, radix: 10)
                if let cp = codePoint, let scalar = Unicode.Scalar(cp) {
                    result.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - oEmbed fallback

    static func oEmbedEndpointURL(for pageURL: URL) -> URL? {
        let host = normalizedHost(for: pageURL)
        let baseString: String?

        if host.contains("tiktok.com") {
            baseString = "https://www.tiktok.com/oembed"
        } else if host.contains("instagram.com") {
            baseString = "https://api.instagram.com/oembed"
        } else if host.contains("spotify.com") {
            baseString = "https://open.spotify.com/oembed"
        } else {
            return nil
        }

        guard let baseString,
              var components = URLComponents(string: baseString) else { return nil }
        components.queryItems = [URLQueryItem(name: "url", value: pageURL.absoluteString)]
        return components.url
    }

    static func fetchOEmbedPayload(for pageURL: URL) async -> BookmarkEnrichmentPayload? {
        guard let endpoint = oEmbedEndpointURL(for: pageURL) else { return nil }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode) else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let title = json["title"] as? String
            let thumbnailRaw = json["thumbnail_url"] as? String
            let thumbnailURL = thumbnailRaw.flatMap { URL(string: $0) }

            guard title != nil || thumbnailURL != nil else { return nil }
            return BookmarkEnrichmentPayload(title: title, thumbnailURL: thumbnailURL, screenshotData: nil)
        } catch {
            return nil
        }
    }
}
