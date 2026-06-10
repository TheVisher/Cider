import Foundation

struct SecondBrainBookmarkGraphCandidateExtractionResult: Equatable {
    var outputs: [SecondBrainEnrichmentOutput]

    var count: Int { outputs.count }
    var ids: [String] { outputs.map(\.id) }
}

struct SecondBrainBookmarkGraphCandidateExtractor {
    func extract(
        sourceOwner: SecondBrainOwnerRef,
        urlString: String,
        title: String? = nil
    ) -> SecondBrainBookmarkGraphCandidateExtractionResult {
        guard let components = URLComponents(string: urlString),
              let rawHost = components.host else {
            return SecondBrainBookmarkGraphCandidateExtractionResult(outputs: [])
        }

        let host = normalizedHost(rawHost)
        let path = components.percentEncodedPath.removingPercentEncoding ?? components.path
        guard let classification = classify(host: host, path: path) else {
            return SecondBrainBookmarkGraphCandidateExtractionResult(outputs: [])
        }

        let mention = mentionText(
            title: title,
            host: host,
            path: path,
            classification: classification
        )
        guard let mention else {
            return SecondBrainBookmarkGraphCandidateExtractionResult(outputs: [])
        }

        let sourceQuote = sourceQuote(title: title, urlString: urlString)
        guard let output = makeCandidate(
            sourceOwner: sourceOwner,
            mentionText: mention,
            sourceQuote: sourceQuote,
            classification: classification,
            urlString: urlString,
            host: host,
            path: path
        ) else {
            return SecondBrainBookmarkGraphCandidateExtractionResult(outputs: [])
        }

        return SecondBrainBookmarkGraphCandidateExtractionResult(outputs: [output])
    }

    private struct Classification {
        var objectTypes: [SecondBrainGraphCandidateContract.ObjectType]
        var relations: [SecondBrainGraphCandidateContract.RelationType]
        var actions: [String]
        var confidence: Double
        var confidenceReason: String
        var fallbackPrefix: String
        var siteLabel: String
    }

    private func classify(host: String, path: String) -> Classification? {
        let lowerPath = path.lowercased()

        if host == "imdb.com" || host.hasSuffix(".imdb.com"),
           lowerPath.hasPrefix("/title/tt") {
            return Classification(
                objectTypes: [.movie, .media],
                relations: [.represents, .sourceFor],
                actions: ["resolve_media_object", "link_bookmark_source"],
                confidence: 0.86,
                confidenceReason: "IMDb title URLs usually represent a specific movie or media item.",
                fallbackPrefix: "IMDb title",
                siteLabel: "IMDb"
            )
        }

        if host == "letterboxd.com" || host.hasSuffix(".letterboxd.com"),
           lowerPath.hasPrefix("/film/") {
            return Classification(
                objectTypes: [.movie, .media],
                relations: [.represents, .sourceFor],
                actions: ["resolve_media_object", "link_bookmark_source"],
                confidence: 0.84,
                confidenceReason: "Letterboxd film URLs usually represent a specific movie.",
                fallbackPrefix: "Letterboxd film",
                siteLabel: "Letterboxd"
            )
        }

        if host == "themoviedb.org" || host.hasSuffix(".themoviedb.org") {
            if lowerPath.hasPrefix("/movie/") {
                return Classification(
                    objectTypes: [.movie, .media],
                    relations: [.represents, .sourceFor],
                    actions: ["resolve_media_object", "link_bookmark_source"],
                    confidence: 0.84,
                    confidenceReason: "TMDb movie URLs usually represent a specific movie.",
                    fallbackPrefix: "TMDb movie",
                    siteLabel: "TMDb"
                )
            }
            if lowerPath.hasPrefix("/tv/") {
                return Classification(
                    objectTypes: [.show, .media],
                    relations: [.represents, .sourceFor],
                    actions: ["resolve_media_object", "link_bookmark_source"],
                    confidence: 0.84,
                    confidenceReason: "TMDb TV URLs usually represent a specific show.",
                    fallbackPrefix: "TMDb show",
                    siteLabel: "TMDb"
                )
            }
        }

        if host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be" {
            return Classification(
                objectTypes: [.video, .media],
                relations: [.represents, .sourceFor],
                actions: ["resolve_video_object", "link_bookmark_source"],
                confidence: 0.78,
                confidenceReason: "YouTube URLs usually represent a specific video or media source.",
                fallbackPrefix: "YouTube video",
                siteLabel: "YouTube"
            )
        }

        if host == "github.com" || host.hasSuffix(".github.com"),
           githubRepositoryName(from: path) != nil {
            return Classification(
                objectTypes: [.project],
                relations: [.represents, .sourceFor],
                actions: ["resolve_project_object", "link_bookmark_source"],
                confidence: 0.82,
                confidenceReason: "GitHub repository URLs usually represent a project.",
                fallbackPrefix: "GitHub repository",
                siteLabel: "GitHub"
            )
        }

        if isRecipeHost(host) || lowerPath.contains("/recipe") || lowerPath.contains("/recipes/") {
            return Classification(
                objectTypes: [.recipe, .food],
                relations: [.represents, .sourceFor],
                actions: ["resolve_recipe_object", "link_bookmark_source"],
                confidence: 0.76,
                confidenceReason: "Recipe-site URLs usually represent a recipe or food item.",
                fallbackPrefix: "Recipe",
                siteLabel: host
            )
        }

        if isProductHost(host) || lowerPath.contains("/dp/") || lowerPath.contains("/product/") || lowerPath.contains("/listing/") {
            return Classification(
                objectTypes: [.product],
                relations: [.represents, .sourceFor],
                actions: ["resolve_product_object", "link_bookmark_source"],
                confidence: 0.74,
                confidenceReason: "Product-commerce URLs usually represent a product.",
                fallbackPrefix: "Product",
                siteLabel: host
            )
        }

        if isPlaceHost(host) || lowerPath.contains("/restaurant") || lowerPath.contains("/biz/") {
            return Classification(
                objectTypes: [.restaurant, .place],
                relations: [.represents, .sourceFor],
                actions: ["resolve_place_object", "link_bookmark_source"],
                confidence: 0.72,
                confidenceReason: "Place and restaurant URLs usually represent a location or venue.",
                fallbackPrefix: "Place",
                siteLabel: host
            )
        }

        return nil
    }

    private func makeCandidate(
        sourceOwner: SecondBrainOwnerRef,
        mentionText: String,
        sourceQuote: String,
        classification: Classification,
        urlString: String,
        host: String,
        path: String
    ) -> SecondBrainEnrichmentOutput? {
        guard var output = try? SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: sourceOwner,
            candidateKind: .objectRelation,
            mentionText: mentionText,
            sourceQuote: sourceQuote,
            sourceKind: "bookmark",
            objectTypeGuesses: classification.objectTypes,
            relationGuesses: classification.relations,
            actionGuesses: classification.actions,
            safeActions: [.inspectSource, .linkExisting, .createObject, .createRelation, .correct, .reject, .delegateEnrichment],
            confidence: classification.confidence,
            confidenceReason: classification.confidenceReason,
            source: "graph_candidate.bookmark_capture"
        ) else {
            return nil
        }

        output.metadata["url"] = urlString
        output.metadata["url_host"] = host
        output.metadata["url_path"] = path
        output.metadata["url_site_label"] = classification.siteLabel
        output.metadata["resolution_state"] = "unresolved"
        return output
    }

    private func mentionText(
        title: String?,
        host: String,
        path: String,
        classification: Classification
    ) -> String? {
        if host == "github.com" || host.hasSuffix(".github.com"),
           let repo = githubRepositoryName(from: path) {
            return repo
        }

        if let title = cleanTitle(title, siteLabel: classification.siteLabel) {
            return title
        }

        if let slug = pathSlug(path) {
            return "\(classification.fallbackPrefix): \(slug)"
        }

        return classification.fallbackPrefix
    }

    private func cleanTitle(_ title: String?, siteLabel: String) -> String? {
        guard var title = normalizedWhitespace(title), !title.isEmpty else { return nil }
        let suffixes = [
            " - \(siteLabel)",
            " | \(siteLabel)",
            " on \(siteLabel)",
            " - IMDb",
            " | IMDb",
            " - YouTube",
            " | YouTube",
            " - GitHub",
            " | GitHub",
        ]
        for suffix in suffixes where title.lowercased().hasSuffix(suffix.lowercased()) {
            title.removeLast(suffix.count)
            title = normalizedWhitespace(title) ?? ""
        }
        return title.isEmpty ? nil : title
    }

    private func sourceQuote(title: String?, urlString: String) -> String {
        if let title = normalizedWhitespace(title), !title.isEmpty {
            return "\(title) - \(urlString)"
        }
        return urlString
    }

    private func githubRepositoryName(from path: String) -> String? {
        let parts = path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        let repo = parts[1].replacingOccurrences(of: ".git", with: "")
        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        return "\(owner)/\(repo)"
    }

    private func pathSlug(_ path: String) -> String? {
        let parts = path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let raw = parts.last else { return nil }
        let withoutIDPrefix = raw.replacingOccurrences(
            of: #"^\d+[-_]"#,
            with: "",
            options: .regularExpression
        )
        let cleaned = withoutIDPrefix
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        guard let normalized = normalizedWhitespace(cleaned), !normalized.isEmpty else { return nil }
        return normalized.capitalized
    }

    private func normalizedHost(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }

    private func isRecipeHost(_ host: String) -> Bool {
        [
            "allrecipes.com",
            "seriouseats.com",
            "smittenkitchen.com",
            "foodnetwork.com",
            "nytcooking.com",
            "epicurious.com",
            "kingarthurbaking.com",
        ].contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private func isProductHost(_ host: String) -> Bool {
        [
            "amazon.com",
            "target.com",
            "bestbuy.com",
            "etsy.com",
            "walmart.com",
            "bhphotovideo.com",
            "homedepot.com",
            "lowes.com",
        ].contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private func isPlaceHost(_ host: String) -> Bool {
        [
            "yelp.com",
            "opentable.com",
            "tripadvisor.com",
            "maps.google.com",
            "google.com",
            "resy.com",
            "theinfatuation.com",
            "eater.com",
        ].contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private func normalizedWhitespace(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
