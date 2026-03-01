import Foundation
import NaturalLanguage

/// On-device NLP using the NaturalLanguage framework.
/// Works on any Mac — no Apple Intelligence required.
struct NLPipeline {

    // MARK: - Public API

    /// Suggest tags for a bookmark using a three-stage approach:
    /// 1. **Semantic category matching** via NL embeddings — "what IS this?"
    ///    (e.g. "bookmarks", "note-taking", "developer-tools")
    /// 2. **Named entity recognition** — "WHO specifically?"
    ///    (e.g. "Claude Code", "Devin AI")
    /// 3. **URL path extraction** — meaningful identifiers from the URL
    ///    (e.g. channel names like "@wubby", repo owners, usernames)
    /// Returns up to 4 tags. Categories first, then entities + URL tokens.
    static func suggestTags(title: String, host: String, notes: String, urlString: String = "") -> [String] {
        let titleNotesText = [title, notes]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        guard !titleNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        // Include host in embedding text — the domain name carries strong signal
        let embeddingText = [title, host, notes]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")

        let hostExclusions = hostDerivedWords(from: host)

        // Stage 0: Host keyword matching — fast direct check against taxonomy
        let hostCategoryTags = matchHostKeywords(host: host)

        // Stage 1: Semantic category matching — understand what this page IS
        let semanticTags = matchCategoryTags(text: embeddingText)

        // Merge host keywords (high confidence) + semantic, deduped, cap at 2
        let hostSet = Set(hostCategoryTags)
        let categoryTags = Array(
            (hostCategoryTags + semanticTags.filter { !hostSet.contains($0) }).prefix(2)
        )

        // Stage 2: Named entities — specific proper nouns (people, orgs, places)
        let categorySet = Set(categoryTags)
        let entityTags = extractEntities(from: titleNotesText)
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { token in
                (token.count > 3 || (token.count == 3 && token == token.uppercased()))
                && !stopwords.contains(token)
                && !hostExclusions.contains(token)
                && !categorySet.contains(token)
            }

        // Stage 3: URL path tokens — channel names, usernames, org names
        let urlTokens = extractURLPathTokens(from: urlString, host: host)
            .filter { token in
                !categorySet.contains(token)
                && !entityTags.contains(token)
            }

        // Categories first (better for organization), then entities, then URL tokens
        let combined = categoryTags + entityTags + urlTokens
        return Array(combined.prefix(4))
    }

    // MARK: - Semantic Category Matching

    /// Match bookmark text against a curated taxonomy using NL embeddings.
    /// Tries sentence embedding first (compares full phrases), falls back to
    /// word embedding (compares individual nouns against category keywords).
    private static func matchCategoryTags(text: String) -> [String] {
        // Sentence embedding: compare full bookmark text against category descriptors
        if let model = NLEmbedding.sentenceEmbedding(for: .english) {
            let results = matchViaSentenceEmbedding(text: text, model: model)
            if !results.isEmpty { return results }
        }
        // Word embedding fallback: compare extracted nouns against category keywords
        if let model = NLEmbedding.wordEmbedding(for: .english) {
            return matchViaWordEmbedding(text: text, model: model)
        }
        return []
    }

    private static func matchViaSentenceEmbedding(
        text: String,
        model: NLEmbedding
    ) -> [String] {
        var scored: [(tag: String, distance: Double)] = []
        for entry in taxonomy {
            let dist = model.distance(between: text, and: entry.descriptor)
            // Cosine distance: 0 = identical, 2 = opposite. < 0.85 ≈ related.
            if dist < 0.85 && dist < Double.greatestFiniteMagnitude {
                scored.append((entry.tag, dist))
            }
        }
        // Return best 2 category matches (leave room for 1 entity tag)
        return scored.sorted { $0.distance < $1.distance }
            .prefix(2)
            .map(\.tag)
    }

    private static func matchViaWordEmbedding(
        text: String,
        model: NLEmbedding
    ) -> [String] {
        let textNouns = extractKeywords(from: text, maxCount: 8)
        guard !textNouns.isEmpty else { return [] }

        var scored: [(tag: String, distance: Double)] = []
        for entry in taxonomy {
            var best = Double.greatestFiniteMagnitude
            for noun in textNouns {
                for keyword in entry.keywords {
                    let dist = model.distance(between: noun, and: keyword)
                    if dist < best { best = dist }
                }
            }
            // Word-level distances are tighter; 0.6 ≈ semantically related words
            if best < 0.6 {
                scored.append((entry.tag, best))
            }
        }
        return scored.sorted { $0.distance < $1.distance }
            .prefix(2)
            .map(\.tag)
    }

    // MARK: - Named Entity Recognition

    /// Extract people, organizations, places via NER.
    static func extractEntities(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var results: [String] = []
        let range = text.startIndex..<text.endIndex
        tagger.enumerateTags(
            in: range, unit: .word, scheme: .nameType,
            options: [.omitWhitespace, .joinNames]
        ) { tag, tokenRange in
            if let tag, [.personalName, .organizationName, .placeName].contains(tag) {
                let token = String(text[tokenRange])
                if token.count > 3 || (token.count == 3 && token == token.uppercased()) {
                    results.append(token)
                }
            }
            return true
        }
        return Array(Set(results))
    }

    /// Keyword extraction using lexical class tagging — picks the most frequent nouns.
    /// Used internally for word embedding fallback.
    static func extractKeywords(from text: String, maxCount: Int = 8) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var nouns: [String] = []
        let range = text.startIndex..<text.endIndex
        tagger.enumerateTags(
            in: range, unit: .word, scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            if tag == .noun {
                let word = String(text[tokenRange])
                if word.count > 3 { nouns.append(word) }
            }
            return true
        }
        let freq = Dictionary(nouns.map { ($0.lowercased(), 1) }, uniquingKeysWith: +)
        return freq.sorted { $0.value > $1.value }.prefix(maxCount).map(\.key)
    }

    // MARK: - Embedding (Public)

    /// Compute a sentence-level embedding vector for the given text.
    /// Returns nil if no embedding model is available.
    static func embedding(for text: String) -> [Double]? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let model = NLEmbedding.sentenceEmbedding(for: .english)
               ?? NLEmbedding.wordEmbedding(for: .english)
        guard let model else { return nil }
        return model.vector(for: text)
    }

    /// Detect the dominant language of a text snippet.
    static func detectLanguage(of text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }

    // MARK: - Taxonomy

    /// Curated categories for semantic bookmark classification.
    /// `descriptor`: natural-language phrase for sentence embedding matching.
    /// `keywords`: single words for word embedding fallback.
    private struct CategoryEntry {
        let tag: String
        let descriptor: String
        let keywords: [String]
    }

    private static let taxonomy: [CategoryEntry] = [
        // Software categories
        CategoryEntry(tag: "bookmarks",
                      descriptor: "bookmark manager web clipper for saving and organizing links",
                      keywords: ["bookmark", "bookmarks", "clipper", "links", "saved"]),
        CategoryEntry(tag: "note-taking",
                      descriptor: "note taking application for writing and organizing personal notes",
                      keywords: ["notes", "notebook", "writing", "notetaker", "markdown"]),
        CategoryEntry(tag: "productivity",
                      descriptor: "productivity tool for task management and daily organization",
                      keywords: ["productivity", "tasks", "workflow", "planner", "organize"]),
        CategoryEntry(tag: "developer-tools",
                      descriptor: "software development programming tools and code editors",
                      keywords: ["developer", "programming", "code", "engineering", "compiler"]),
        CategoryEntry(tag: "design",
                      descriptor: "design tool for user interface graphics and prototyping",
                      keywords: ["design", "graphics", "prototype", "figma", "interface"]),
        CategoryEntry(tag: "ai",
                      descriptor: "artificial intelligence machine learning and AI assistant tools",
                      keywords: ["intelligence", "machine", "neural", "model", "llm"]),
        CategoryEntry(tag: "reading",
                      descriptor: "read later app article saver and long-form reading tool",
                      keywords: ["reading", "reader", "articles", "digest", "instapaper"]),
        CategoryEntry(tag: "collaboration",
                      descriptor: "team collaboration workspace and project communication tools",
                      keywords: ["collaboration", "workspace", "slack", "teamwork"]),

        // Content categories
        CategoryEntry(tag: "reference",
                      descriptor: "technical documentation API reference and knowledge base",
                      keywords: ["documentation", "reference", "manual", "wiki", "docs"]),
        CategoryEntry(tag: "tutorial",
                      descriptor: "educational tutorial how-to guide and step-by-step instructions",
                      keywords: ["tutorial", "guide", "howto", "walkthrough", "lesson"]),
        CategoryEntry(tag: "news",
                      descriptor: "news journalism and current events reporting website",
                      keywords: ["news", "journalism", "reporting", "headlines"]),
        CategoryEntry(tag: "research",
                      descriptor: "academic research scientific papers and scholarly analysis",
                      keywords: ["research", "academic", "science", "paper", "journal"]),

        // Domain categories
        CategoryEntry(tag: "finance",
                      descriptor: "finance investing stock market trading and banking tools",
                      keywords: ["finance", "investing", "banking", "stocks", "trading"]),
        CategoryEntry(tag: "social-media",
                      descriptor: "social media network online community and discussion forum",
                      keywords: ["social", "community", "forum", "network", "reddit"]),
        CategoryEntry(tag: "video",
                      descriptor: "video streaming platform media player and video hosting",
                      keywords: ["video", "streaming", "youtube", "player", "media"]),
        CategoryEntry(tag: "music",
                      descriptor: "music streaming audio player and podcast listening platform",
                      keywords: ["music", "audio", "podcast", "spotify", "playlist"]),
        CategoryEntry(tag: "education",
                      descriptor: "online education courses and e-learning platform",
                      keywords: ["education", "courses", "training", "elearning"]),
        CategoryEntry(tag: "shopping",
                      descriptor: "online shopping ecommerce marketplace and price comparison",
                      keywords: ["shopping", "ecommerce", "store", "marketplace", "retail"]),
        CategoryEntry(tag: "health",
                      descriptor: "health fitness wellness tracking and medical information",
                      keywords: ["health", "fitness", "wellness", "medical", "exercise"]),
        CategoryEntry(tag: "gaming",
                      descriptor: "video games gaming platform esports and game reviews",
                      keywords: ["gaming", "games", "esports", "console", "steam"]),
        CategoryEntry(tag: "email",
                      descriptor: "email client inbox management and messaging communication",
                      keywords: ["email", "inbox", "messaging", "mail", "smtp"]),
        CategoryEntry(tag: "calendar",
                      descriptor: "calendar scheduling events and appointment management",
                      keywords: ["calendar", "scheduling", "events", "planner", "agenda"]),
        CategoryEntry(tag: "cloud-storage",
                      descriptor: "cloud storage file sharing backup and sync service",
                      keywords: ["storage", "cloud", "backup", "files", "sync"]),
        CategoryEntry(tag: "browser",
                      descriptor: "web browser browser extensions and tab management tools",
                      keywords: ["browser", "extension", "tabs", "browsing", "chrome"]),
        CategoryEntry(tag: "security",
                      descriptor: "cybersecurity privacy VPN password manager and encryption",
                      keywords: ["security", "privacy", "password", "encryption", "vpn"]),
        CategoryEntry(tag: "automation",
                      descriptor: "workflow automation scripting and integration platform",
                      keywords: ["automation", "scripts", "integration", "zapier", "automate"]),
        CategoryEntry(tag: "writing",
                      descriptor: "writing tool text editor and long-form document creation",
                      keywords: ["writing", "editor", "documents", "prose", "authoring"]),
        CategoryEntry(tag: "database",
                      descriptor: "database management SQL data tools and query platform",
                      keywords: ["database", "sql", "query", "tables", "schema"]),
        CategoryEntry(tag: "analytics",
                      descriptor: "analytics data visualization dashboards and metrics tracking",
                      keywords: ["analytics", "dashboard", "metrics", "visualization", "charts"]),
        CategoryEntry(tag: "hosting",
                      descriptor: "web hosting server deployment and cloud infrastructure",
                      keywords: ["hosting", "deployment", "server", "infrastructure", "devops"]),
        CategoryEntry(tag: "open-source",
                      descriptor: "open source software community projects and code repositories",
                      keywords: ["opensource", "repository", "contribute", "libre", "foss"]),

        // Additional domain categories
        CategoryEntry(tag: "cooking",
                      descriptor: "cooking recipes meal planning and food preparation",
                      keywords: ["cooking", "recipe", "recipes", "meal", "food", "ingredients"]),
        CategoryEntry(tag: "travel",
                      descriptor: "travel planning destinations hotels flights and vacation",
                      keywords: ["travel", "vacation", "flights", "hotels", "destinations", "booking", "airbnb", "tripadvisor"]),
        CategoryEntry(tag: "photography",
                      descriptor: "photography camera editing and photo sharing platform",
                      keywords: ["photography", "camera", "photos", "lightroom", "editing"]),
        CategoryEntry(tag: "sports",
                      descriptor: "sports scores teams athletes and live game coverage",
                      keywords: ["sports", "football", "basketball", "baseball", "soccer", "mlb", "nfl", "nba", "nhl", "espn"]),
        CategoryEntry(tag: "entertainment",
                      descriptor: "movies television shows streaming entertainment and media",
                      keywords: ["movies", "television", "shows", "streaming", "entertainment", "imdb", "netflix", "hulu"]),
        CategoryEntry(tag: "business",
                      descriptor: "business startup entrepreneurship and company management",
                      keywords: ["business", "startup", "entrepreneur", "company", "revenue"]),
        CategoryEntry(tag: "real-estate",
                      descriptor: "real estate property listings housing market and rentals",
                      keywords: ["realestate", "property", "housing", "rental", "mortgage"]),
        CategoryEntry(tag: "government",
                      descriptor: "government services public policy laws and civic resources",
                      keywords: ["government", "policy", "legal", "civic", "regulation"]),
        CategoryEntry(tag: "cryptocurrency",
                      descriptor: "cryptocurrency blockchain bitcoin ethereum and web3",
                      keywords: ["crypto", "bitcoin", "ethereum", "blockchain", "web3"]),
    ]

    // MARK: - URL Path Extraction

    /// Extract meaningful identifiers from URL paths.
    /// Handles patterns like:
    /// - YouTube channels: `/@PaymoneyWubby` → "paymoneyWubby"
    /// - GitHub repos: `/user/repo` → "user"
    /// - Subreddits: `/r/programming` → "programming"
    /// - Twitter/X profiles: `/@username` → "username"
    private static func extractURLPathTokens(from urlString: String, host: String) -> [String] {
        guard let url = URL(string: urlString) else { return [] }
        let hostLower = host.lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard !pathComponents.isEmpty else { return [] }

        var tokens: [String] = []

        // YouTube: /@ChannelName or /c/ChannelName or /channel/... (skip ID-style)
        if hostLower.contains("youtube") || hostLower.contains("youtu.be") {
            for component in pathComponents {
                if component.hasPrefix("@") {
                    let name = String(component.dropFirst())
                        .lowercased()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if name.count > 2 { tokens.append(name) }
                }
            }
            if tokens.isEmpty, pathComponents.first == "c" || pathComponents.first == "user",
               pathComponents.count >= 2 {
                let name = pathComponents[1].lowercased()
                if name.count > 2 { tokens.append(name) }
            }
        }

        // GitHub: /owner/repo → extract owner
        if hostLower.contains("github") {
            if pathComponents.count >= 1 {
                let owner = pathComponents[0].lowercased()
                if owner.count > 2 && !urlPathStopwords.contains(owner) {
                    tokens.append(owner)
                }
            }
        }

        // Reddit: /r/subreddit → extract subreddit name
        if hostLower.contains("reddit") {
            if pathComponents.count >= 2 && pathComponents[0] == "r" {
                let sub = pathComponents[1].lowercased()
                if sub.count > 2 { tokens.append(sub) }
            }
        }

        // Generic: @username in first path component (Twitter/X, Mastodon, etc.)
        if tokens.isEmpty {
            for component in pathComponents.prefix(2) {
                if component.hasPrefix("@") {
                    let name = String(component.dropFirst())
                        .lowercased()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if name.count > 2 && !urlPathStopwords.contains(name) {
                        tokens.append(name)
                    }
                }
            }
        }

        return tokens
    }

    /// URL path segments that shouldn't become tags.
    private static let urlPathStopwords: Set<String> = [
        "watch", "video", "videos", "channel", "playlist",
        "issues", "pulls", "actions", "settings", "releases",
        "wiki", "blob", "tree", "commit", "commits",
        "explore", "trending", "topics", "search",
        "comments", "submit", "about",
        "status", "blog", "posts", "tags", "categories",
        "archive", "page", "pages",
    ]

    // MARK: - Host Keyword Matching

    /// Fast direct check: does the hostname contain any taxonomy keyword?
    /// Catches cases like "allrecipes.com" → "recipes" → cooking,
    /// "booking.com" → "booking" → travel, "espn.com" → "espn" → sports.
    private static func matchHostKeywords(host: String) -> [String] {
        let hostLower = host.lowercased()
        var matches: [String] = []
        for entry in taxonomy {
            for keyword in entry.keywords where keyword.count >= 3 {
                if hostLower.contains(keyword) {
                    matches.append(entry.tag)
                    break
                }
            }
        }
        return matches
    }

    // MARK: - Host Exclusion

    /// Extract words from a host string to exclude from tags.
    /// "github.com" → {"github", "com"}
    /// "www.raindrop.io" → {"www", "raindrop", "io"}
    private static func hostDerivedWords(from host: String) -> Set<String> {
        let cleaned = host.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.components(separatedBy: CharacterSet(charactersIn: ".-"))
            .filter { !$0.isEmpty }
        return Set(parts)
    }

    // MARK: - Stopwords

    /// Words that make terrible tags — too generic, too common, or meaningless.
    private static let stopwords: Set<String> = [
        // Common English words that NL tags as nouns/entities
        "nothing", "anything", "something", "everything", "everyone", "someone",
        "thing", "things", "stuff", "none", "many", "some", "other", "others",
        "much", "more", "most", "less", "better", "best", "worst", "first",
        "last", "next", "every", "each", "only", "also",

        // Generic web/app marketing copy words
        "home", "page", "site", "about", "help", "download", "free", "open",
        "click", "here", "link", "view", "full", "read", "more", "learn",
        "start", "started", "getting", "welcome", "intro", "overview",
        "tool", "tools", "platform", "solution", "solutions", "product",
        "products", "service", "services", "feature", "features",
        "world", "life", "heart", "place", "time", "times", "year", "years",
        "today", "tomorrow", "future", "together",

        // Generic app/tech marketing terms
        "simple", "easy", "fast", "powerful", "beautiful", "modern", "smart",
        "ultimate", "minimal", "instant", "instantly", "forever", "never",

        // Common web structure words
        "blog", "post", "posts", "article", "articles", "content", "contents",
        "docs", "documentation", "guide", "guides", "tutorial", "tutorials",
        "sign", "login", "signup", "account", "profile",
        "cookie", "cookies", "privacy", "terms", "policy",

        // TLDs and web fragments
        "http", "https", "html", "json",

        // Release/version noise
        "beta", "alpha", "release", "version", "update", "latest",

        // Generic filler words
        "powered", "built", "using", "just", "good", "great", "really",
        "want", "need", "way", "ways",

        // Overly broad words that create meaningless tags
        "apps", "data", "info", "information", "type", "types",
        "work", "works", "working", "make", "makes", "making",
        "part", "parts", "form", "forms", "list", "lists",
        "note", "notes", "task", "tasks", "item", "items",
        "user", "users", "team", "teams", "project", "projects",
    ]
}
