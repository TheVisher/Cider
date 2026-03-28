import Foundation
import os

/// Fetches oEmbed metadata for URLs from sites that block normal scraping.
/// Returns structured data (title, author, description, thumbnail) that can
/// enrich bookmark notes and titles.
enum OEmbedService {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "OEmbedService"
    )

    // MARK: - oEmbed Providers

    private struct Provider: Sendable {
        let hostPatterns: [String]
        let endpoint: @Sendable (String) -> URL?
    }

    private static let providers: [Provider] = [
        Provider(
            hostPatterns: ["tiktok.com", "www.tiktok.com", "vm.tiktok.com"],
            endpoint: { url in URL(string: "https://www.tiktok.com/oembed?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)") }
        ),
        Provider(
            hostPatterns: ["youtube.com", "www.youtube.com", "youtu.be", "m.youtube.com"],
            endpoint: { url in URL(string: "https://www.youtube.com/oembed?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)&format=json") }
        ),
        Provider(
            hostPatterns: ["instagram.com", "www.instagram.com"],
            endpoint: { url in URL(string: "https://api.instagram.com/oembed?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)") }
        ),
        Provider(
            hostPatterns: ["twitter.com", "www.twitter.com", "x.com", "www.x.com"],
            endpoint: { url in URL(string: "https://publish.twitter.com/oembed?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)") }
        ),
    ]

    // MARK: - Result

    struct OEmbedResult {
        let title: String?
        let authorName: String?
        let authorURL: String?
        let providerName: String?
        let thumbnailURL: String?
    }

    // MARK: - Public API

    /// Returns true if this URL is from a site with oEmbed support.
    static func supports(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return false }
        return providers.contains { $0.hostPatterns.contains(host) }
    }

    /// Fetches oEmbed metadata for a URL. Returns nil if the site isn't supported or the fetch fails.
    static func fetch(for urlString: String) async -> OEmbedResult? {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return nil }

        guard let provider = providers.first(where: { $0.hostPatterns.contains(host) }),
              let oembedURL = provider.endpoint(urlString) else { return nil }

        do {
            var request = URLRequest(url: oembedURL)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.info("oEmbed fetch returned non-200 for \(host)")
                return nil
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let json else { return nil }

            let title = json["title"] as? String
            let authorName = json["author_name"] as? String
            let authorURL = json["author_url"] as? String
            let providerName = json["provider_name"] as? String
            let thumbnailURL = json["thumbnail_url"] as? String

            logger.info("oEmbed fetched for \(host): title=\(title ?? "nil"), author=\(authorName ?? "nil")")
            return OEmbedResult(
                title: title,
                authorName: authorName,
                authorURL: authorURL,
                providerName: providerName,
                thumbnailURL: thumbnailURL
            )
        } catch {
            logger.warning("oEmbed fetch failed for \(host): \(error.localizedDescription)")
            return nil
        }
    }

    /// Builds a concise notes string from oEmbed data.
    static func buildNotes(from result: OEmbedResult) -> String? {
        var parts: [String] = []

        if let title = result.title, !title.isEmpty {
            // Clean up TikTok-style descriptions: truncate very long ones
            let cleaned = title.count > 280 ? String(title.prefix(280)) + "..." : title
            parts.append(cleaned)
        }

        if let author = result.authorName, !author.isEmpty {
            parts.append("By \(author)")
        }

        if let provider = result.providerName, !provider.isEmpty {
            parts.append("Via \(provider)")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    /// Suggests a better bookmark title from oEmbed data.
    /// Returns nil if the oEmbed title isn't meaningfully better than the current title.
    static func suggestTitle(from result: OEmbedResult, currentTitle: String, urlString: String) -> String? {
        guard let oembedTitle = result.title, !oembedTitle.isEmpty else { return nil }

        // If current title is just the site name or a short URL fragment, oEmbed is better
        let generic = isGenericTitle(currentTitle, urlString: urlString)
        guard generic else { return nil }

        // Extract a meaningful short title from the oEmbed description
        // TikTok titles are full descriptions — take the first sentence or meaningful chunk
        let cleaned = cleanTitle(oembedTitle, authorName: result.authorName)
        guard !cleaned.isEmpty, cleaned.count >= 4 else { return nil }
        return cleaned
    }

    // MARK: - Private Helpers

    private static func isGenericTitle(_ title: String, urlString: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty { return true }

        // Site names only
        let genericNames = ["tiktok", "tiktok - make your day", "youtube", "instagram", "x", "twitter"]
        if genericNames.contains(t) { return true }

        // Title is just a URL path fragment
        if t.hasPrefix("http") { return true }
        if urlString.lowercased().contains(t) { return true }

        // Very short with a hash/code pattern (e.g. "ZP8bV7Vjr")
        if t.count < 15 && t.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == " " }) {
            let words = t.split(separator: " ")
            if words.count <= 2 && words.allSatisfy({ $0.count < 12 }) { return true }
        }

        return false
    }

    private static func cleanTitle(_ oembedTitle: String, authorName: String?) -> String {
        var title = oembedTitle

        // Remove @mentions at the start (common in TikTok: "@username 's food is amazing")
        if title.hasPrefix("@") {
            if let spaceIndex = title.firstIndex(of: " ") {
                let afterMention = title[title.index(after: spaceIndex)...]
                // Skip possessive "'s " too
                if afterMention.hasPrefix("'s ") {
                    title = String(afterMention.dropFirst(3))
                } else {
                    title = String(afterMention)
                }
            }
        }

        // Remove hashtags from end
        while let hashRange = title.range(of: #"\s*#\w+\s*$"#, options: .regularExpression) {
            title = String(title[..<hashRange.lowerBound])
        }

        title = title.trimmingCharacters(in: .whitespaces)

        // Truncate to reasonable title length
        if title.count > 80 {
            // Try to break at a sentence boundary
            if let periodIndex = title[..<title.index(title.startIndex, offsetBy: min(80, title.count))].lastIndex(of: ".") {
                title = String(title[...periodIndex])
            } else if let spaceIndex = title[..<title.index(title.startIndex, offsetBy: 80)].lastIndex(of: " ") {
                title = String(title[..<spaceIndex])
            } else {
                title = String(title.prefix(80))
            }
        }

        return title.trimmingCharacters(in: .whitespaces)
    }
}
