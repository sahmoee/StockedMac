import Foundation

/// What Bulk verify learned about one queued URL.
nonisolated enum PageCheck: Sendable {
    case recipe(resolvedURL: String? = nil)
    case listing(mined: [String])
    case other
}

nonisolated struct ImportOutcomeDetail: Sendable {
    var recipe: RecipeDraft
    var wasUpdate: Bool
    var duplicateTitles: [String]
}

actor CrawlCoordinator {
    private let store: RecipeStore
    private let registry: SourceRegistry
    private let fetcher: PolicyFetcher
    private let imageStore: ImageStore
    private let discovery: DiscoveryEngine
    private let nativeParser = NativeRecipeParser()
    private let microdataParser = MicrodataRecipeParser()
    private let heuristicParser = HeuristicRecipeParser()
    private let ingredientParser = IngredientParser()
    private let detector = RecipePageDetector()
    private var pythonParser: PythonWorkerClient
    /// Rendered-HTML cache for the current run, so a retry never renders twice.
    private var renderCache: [String: String] = [:]

    init(
        store: RecipeStore,
        registry: SourceRegistry,
        fetcher: PolicyFetcher,
        imageStore: ImageStore,
        pythonParser: PythonWorkerClient
    ) {
        self.store = store
        self.registry = registry
        self.fetcher = fetcher
        self.imageStore = imageStore
        self.pythonParser = pythonParser
        self.discovery = DiscoveryEngine(fetcher: fetcher)
    }

    // MARK: - Import

    func importRecipe(
        urlString: String,
        settings: AppSettings,
        allowNonRecipePages: Bool = false,
        parserModeOverride: ParserMode? = nil
    ) async throws -> ImportOutcomeDetail {
        try Task.checkCancellation()
        let requestedURL = try URLSafety.validatedRemoteURL(urlString)
        let source = try await registry.profile(for: requestedURL) ?? genericProfile(for: requestedURL)
        guard source.enabled else {
            throw CompanionError.sourceDisabled(source.name)
        }

        var page = try await fetcher.fetch(
            requestedURL,
            source: source,
            settings: settings,
            accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1"
        )

        // Build 95: if the plain fetch got a bot wall or a JS shell, render the page
        // in the invisible WebKit view and work from what a real browser sees.
        var html = page.text
        var usedWebKit = false
        if settings.useWebKitFallback, RecipePageDetector.looksBlocked(html) {
            if let rendered = await renderedHTML(for: page.finalURL, settings: settings) {
                html = rendered
                usedWebKit = true
            }
        }

        // Google/WordPress Web Stories are slide shows, not recipe documents. Their
        // explicit outlink is the publisher's authoritative recipe page; follow it
        // before classification or parsing so every engine receives the real card.
        var followedWebStory: URL?
        if let destination = Self.webStoryRecipeURL(in: html, pageURL: page.finalURL),
           URLSafety.normalized(destination) != URLSafety.normalized(page.finalURL) {
            followedWebStory = page.finalURL
            page = try await fetcher.fetch(
                destination,
                source: source,
                settings: settings,
                accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1"
            )
            html = page.text
            if settings.useWebKitFallback, RecipePageDetector.looksBlocked(html),
               let rendered = await renderedHTML(for: page.finalURL, settings: settings) {
                html = rendered
                usedWebKit = true
            }
        }

        // Challenge pages often repeat the requested `/recipe/` URL in JavaScript.
        // Counting those links first mislabels a bot wall as a category and queues
        // the same unusable URL repeatedly. WebKit already had its retry above.
        if RecipePageDetector.looksBlocked(html) {
            throw CompanionError.parseFailed(
                "The site is blocking automated access to this page (bot wall). Open it in the built-in browser, or choose another source."
            )
        }

        // Refuse category and roundup pages up front rather than emitting a
        // half-parsed record that a reviewer then has to delete — after handing
        // their recipe links back so the caller can queue them.
        let verdict = detector.inspect(html: html, url: page.finalURL, source: source)
        if !allowNonRecipePages, verdict.kind == .listing {
            try refuseListing(html: html, page: page, source: source,
                              evidence: verdict.evidence.first)
        }

        let configuredMode = source.parserMode == .nativeFirst ? settings.parserMode : source.parserMode
        let mode = parserModeOverride ?? configuredMode
        var parsed: ParserResult
        do {
            parsed = try await parse(html: html, url: page.finalURL, mode: mode, settings: settings)
        } catch {
            // One rendered retry when the plain HTML would not parse — many sites only
            // hydrate their recipe data client-side.
            guard settings.useWebKitFallback, !usedWebKit else {
                throw Self.friendlyParseError(error, html: html)
            }
            guard let rendered = await renderedHTML(for: page.finalURL, settings: settings) else {
                throw Self.friendlyParseError(error, html: html)
            }
            usedWebKit = true
            html = rendered
            // Build 97: many roundups only reveal their nature after hydration — the
            // raw HTML is a JS shell. Re-run the page detector on the RENDERED DOM
            // and mine it as a listing before concluding "no recipe here".
            let renderedVerdict = detector.inspect(html: rendered, url: page.finalURL, source: source)
            if !allowNonRecipePages, renderedVerdict.kind == .listing {
                try refuseListing(html: rendered, page: page, source: source,
                                  evidence: renderedVerdict.evidence.first)
            }
            do {
                parsed = try await parse(html: rendered, url: page.finalURL, mode: mode, settings: settings)
            } catch {
                throw Self.friendlyParseError(error, html: rendered)
            }
        }

        var warnings = parsed.warnings
        if usedWebKit {
            warnings.append("Loaded with the built-in browser (the site blocks direct fetches).")
        }
        if followedWebStory != nil {
            warnings.append("Followed the Web Story's publisher-provided recipe link.")
        }
        if verdict.kind == .listing {
            warnings.insert("This page also lists other recipes; check the extraction.", at: 0)
        }

        // ---- Image ---------------------------------------------------------
        // Resolve against the page URL FIRST, before deciding whether to download.
        // Many sites emit `/img/hero.jpg`; storing that relative string is useless to
        // the phone, which has no idea what page it came from. The absolute form is what
        // gets recorded whether or not the bytes are fetched here.
        let resolvedImageURL = parsed.imageURL
            .flatMap { URL(string: $0, relativeTo: page.finalURL)?.absoluteURL }
            .map(\.absoluteString)

        var image: RecipeImage?
        if settings.downloadImages,
           source.imageDownloadEnabled,
           let resolved = resolvedImageURL {
            do {
                image = try await imageStore.download(
                    urlString: resolved,
                    settings: settings,
                    referer: page.finalURL.absoluteString
                )
            } catch {
                warnings.append("The recipe image could not be downloaded: \(error.localizedDescription)")
            }
        }
        if image == nil, let resolved = resolvedImageURL {
            image = RecipeImage(originalURL: resolved)
        }

        // ---- Ingredients ---------------------------------------------------
        let ingredientSections = settings.parseIngredientStructure
            ? ingredientParser.parseSections(parsed.ingredientSections)
            : parsed.ingredientSections

        // ---- Assemble ------------------------------------------------------
        let canonical = parsed.canonicalURL
            .flatMap { URL(string: $0, relativeTo: page.finalURL)?.absoluteURL }
            .map { URLSafety.normalized($0).absoluteString }
        let identityURL = canonical ?? URLSafety.normalized(page.finalURL).absoluteString
        let host = page.finalURL.host?.lowercased() ?? source.domains.first ?? "unknown"

        var draft = RecipeDraft(
            title: parsed.title,
            summary: parsed.summary,
            source: HarvestSource(
                url: URLSafety.normalized(page.finalURL).absoluteString,
                canonicalURL: canonical,
                host: host,
                author: parsed.author,
                // Build 93: never a generic or internal handle. The site's real name,
                // the author, or the plain host — decided in one place.
                attribution: SourceAttribution.displayName(
                    host: host, sourceName: source.name, author: parsed.author
                )
            ),
            image: image,
            ingredientSections: ingredientSections,
            instructionSections: parsed.instructionSections,
            yield: parsed.yield,
            servings: parsed.servings ?? nativeParser.servings(from: parsed.yield),
            times: parsed.times.normalized(),
            nutrition: parsed.nutrition,
            cuisines: parsed.cuisines,
            categories: parsed.categories,
            keywords: parsed.keywords,
            diets: parsed.diets,
            confidence: parsed.confidence,
            warnings: warnings.cleanedUnique(),
            parser: parsed.parser,
            reviewState: .needsReview,
            sourceFingerprint: Hashing.sha256(identityURL),
            discoveryNote: followedWebStory.map {
                "Resolved from Web Story \($0.absoluteString)"
            } ?? (page.fromCache ? "Imported from the local cache" : nil)
        )
        draft.refreshFingerprint()

        let existed = try await store.contains(sourceFingerprint: draft.sourceFingerprint)
        let saved = try await store.upsert(draft)
        let duplicates = try await store.duplicates(for: saved)
        return ImportOutcomeDetail(
            recipe: saved,
            wasUpdate: existed,
            duplicateTitles: duplicates.map(\.title)
        )
    }

    // MARK: - Discovery

    func discoverRecipeURLs(
        source: SourceProfile,
        settings: AppSettings,
        manual: Bool = false,
        progress: @Sendable @escaping (DiscoveryProgress) async -> Void
    ) async throws -> DiscoveryOutcome {
        let known = settings.skipAlreadyImported
            ? try await store.knownSourceURLs()
            : []
        return try await discovery.discover(
            source: source,
            settings: settings,
            manual: manual,
            knownSourceURLs: known,
            progress: progress
        )
    }

    /// Checks a single URL without importing it. Used by the "Test link" action.
    func inspect(
        urlString: String,
        settings: AppSettings
    ) async throws -> RecipePageVerdict {
        let url = try URLSafety.validatedRemoteURL(urlString)
        let source = try await registry.profile(for: url) ?? genericProfile(for: url)
        let page = try await fetcher.fetch(
            url,
            source: source,
            settings: settings,
            accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1"
        )
        var html = page.text
        if settings.useWebKitFallback, RecipePageDetector.looksBlocked(html),
           let rendered = await renderedHTML(for: page.finalURL, settings: settings) {
            html = rendered
        }
        if RecipePageDetector.looksBlocked(html) {
            return RecipePageVerdict(kind: .other, evidence: ["Site access challenge detected"])
        }
        return detector.inspect(html: html, url: page.finalURL, source: source)
    }

    /// Rendered HTML via the invisible browser, cached per URL for this run.
    private func renderedHTML(for url: URL, settings: AppSettings) async -> String? {
        let key = url.absoluteString
        if let cached = renderCache[key] { return cached }
        guard let html = try? await WebKitRenderer.shared.renderedHTML(
            for: url, userAgent: settings.userAgent
        ) else { return nil }
        if renderCache.count > 40 { renderCache.removeAll() }
        renderCache[key] = html
        return html
    }

    /// Refuses a listing page — after handing its recipe links back when it has any.
    private func refuseListing(html: String, page: PolicyFetcher.FetchedPage,
                               source: SourceProfile, evidence: String?) throws -> Never {
        let mined = DiscoveryEngine.extractLinks(from: html, base: page.finalURL)
            .filter { DiscoveryEngine.classify($0, source: source) == .recipe }
        if !mined.isEmpty {
            throw CompanionError.listingPage(page.finalURL.absoluteString, Array(mined.prefix(60)))
        }
        throw CompanionError.notARecipe(
            "\(page.finalURL.absoluteString) — \(evidence ?? "it links to other recipes")"
        )
    }

    /// Bulk verify's engine: judges one queued URL, and when it is a category page,
    /// mines its recipe links — INCLUDING one bounded level of sub-pages (up to 5
    /// sub-listings, 80 links total), so "breakfast" yields dishes, not a deletion.
    func verifyOrMine(urlString: String, settings: AppSettings) async throws -> PageCheck {
        let url = try URLSafety.validatedRemoteURL(urlString)
        let source = try await registry.profile(for: url) ?? genericProfile(for: url)
        let page = try await fetcher.fetch(
            url, source: source, settings: settings,
            accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1"
        )
        var html = page.text
        if settings.useWebKitFallback, RecipePageDetector.looksBlocked(html),
           let rendered = await renderedHTML(for: page.finalURL, settings: settings) {
            html = rendered
        }
        if RecipePageDetector.looksBlocked(html) { return .other }
        if let destination = Self.webStoryRecipeURL(in: html, pageURL: page.finalURL) {
            return .recipe(resolvedURL: URLSafety.normalized(destination).absoluteString)
        }
        let verdict = detector.inspect(html: html, url: page.finalURL, source: source)
        switch verdict.kind {
        case .recipe:
            return .recipe()
        case .other:
            return .other
        case .listing:
            let links = DiscoveryEngine.extractLinks(from: html, base: page.finalURL)
            var recipes = links.filter { DiscoveryEngine.classify($0, source: source) == .recipe }
            // One bounded level of sub-pages: a hub's own sub-categories.
            let subListings = links
                .filter { DiscoveryEngine.classify($0, source: source) == .listing }
                .prefix(5)
            for sub in subListings where recipes.count < 80 {
                try Task.checkCancellation()
                guard let subURL = URL(string: sub) else { continue }
                guard let subPage = try? await fetcher.fetch(
                    subURL, source: source, settings: settings,
                    accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1"
                ) else { continue }
                recipes.append(contentsOf: DiscoveryEngine
                    .extractLinks(from: subPage.text, base: subPage.finalURL)
                    .filter { DiscoveryEngine.classify($0, source: source) == .recipe })
            }
            var seen = Set<String>()
            let unique = recipes.filter { seen.insert($0).inserted }
            return .listing(mined: Array(unique.prefix(80)))
        }
    }

    func setPythonParser(_ client: PythonWorkerClient) {
        pythonParser = client
    }

    /// Turns parser-stack noise into one sentence a person can act on.
    private nonisolated static func friendlyParseError(_ error: any Error, html: String) -> any Error {
        if RecipePageDetector.looksBlocked(html) {
            return CompanionError.parseFailed(
                "The site is blocking automated access to this page (bot wall). Try the built-in browser, or a different User-Agent in the Crawler card."
            )
        }
        return error
    }

    // MARK: - Parsing

    private func parse(html: String, url: URL, mode: ParserMode,
                       settings: AppSettings) async throws -> ParserResult {
        var results: [ParserResult] = []
        var errors: [String] = []

        // These attempts return their outcome instead of appending to captured
        // state: an `async` local function that captured `errors` would be
        // `nonisolated`, and passing the captured array into it is a region
        // isolation violation.
        func record(_ attempt: (result: ParserResult?, error: String?)) {
            if let result = attempt.result { results.append(result) }
            if let message = attempt.error { errors.append(message) }
        }

        func isGoodEnough() -> Bool {
            guard let best = results.filter(\.isComplete).max(by: { $0.confidence < $1.confidence })
            else { return false }
            return best.confidence >= 0.9
        }

        switch mode {
        case .nativeOnly:
            record(runNative(html: html, url: url))
        case .pythonOnly:
            record(await runPython(html: html, url: url))
        case .nativeFirst:
            record(runNative(html: html, url: url))
            if pythonParser.isAvailable, !isGoodEnough() {
                record(await runPython(html: html, url: url))
            }
        case .pythonFirst:
            if pythonParser.isAvailable {
                record(await runPython(html: html, url: url))
            }
            if !isGoodEnough() {
                record(runNative(html: html, url: url))
            }
        }

        // Second tier (Build 95): microdata, then heuristic reconstruction. The
        // heuristic's confidence is capped below every auto-approve threshold, so its
        // output is always reviewed by a person.
        if !isGoodEnough() {
            record(runMicrodata(html: html, url: url))
        }
        if results.filter(\.isComplete).isEmpty {
            record(runHeuristic(html: html, url: url))
        }

        // Third tier: the regular Stocked Worker. When the local engines did not produce a
        // confident, complete recipe and the Worker is configured, hand it the page text
        // for one model-backed attempt. This is the engine that works in the sandboxed App
        // Store build, where the bundled Python binary cannot be spawned — and it is the
        // same Worker, key and route the phone's "Bring a recipe in" uses.
        if settings.useWorkerFallback, HarvestWorkerParser.isAvailable, !isGoodEnough() {
            record(await runWorker(html: html, url: url))
        }

        let usable = results.filter(\.isComplete)
        guard let best = usable.max(by: { $0.confidence < $1.confidence }) else {
            throw CompanionError.parseFailed(
                errors.cleanedUnique().joined(separator: " | ").nilIfBlank
                    ?? "No parser could extract a complete recipe."
            )
        }
        // Merge anything the winner is missing from the runner-up.
        return merge(best, with: usable.filter { $0.parser != best.parser })
    }

    private func runNative(html: String, url: URL) -> (result: ParserResult?, error: String?) {
        do {
            return (try nativeParser.parse(html: html, url: url), nil)
        } catch {
            return (nil, "Native parser: \(Self.parserReason(error))")
        }
    }

    private func runMicrodata(html: String, url: URL) -> (result: ParserResult?, error: String?) {
        do {
            return (try microdataParser.parse(html: html, url: url), nil)
        } catch {
            return (nil, "Microdata: \(Self.parserReason(error))")
        }
    }

    private func runHeuristic(html: String, url: URL) -> (result: ParserResult?, error: String?) {
        do {
            return (try heuristicParser.parse(html: html, url: url), nil)
        } catch {
            return (nil, "Heuristic: \(Self.parserReason(error))")
        }
    }

    private func runPython(html: String, url: URL) async -> (result: ParserResult?, error: String?) {
        do {
            return (try await pythonParser.parse(html: html, url: url), nil)
        } catch {
            return (nil, "Python worker: \(Self.parserReason(error))")
        }
    }

    private func runWorker(html: String, url: URL) async -> (result: ParserResult?, error: String?) {
        do {
            return (try await HarvestWorkerParser.parse(html: html, url: url), nil)
        } catch {
            return (nil, "\(error.localizedDescription)")
        }
    }

    private nonisolated static func parserReason(_ error: any Error) -> String {
        if case let CompanionError.parseFailed(reason) = error { return reason }
        return error.localizedDescription
    }

    /// Finds the publisher-controlled destination carried by AMP Web Story outlinks.
    /// Same-host only: a story must never silently redirect an import to an ad network.
    private nonisolated static func webStoryRecipeURL(in html: String, pageURL: URL) -> URL? {
        let lower = html.lowercased()
        guard pageURL.path.lowercased().contains("/web-stories/")
                || lower.contains("<amp-story") else { return nil }
        let patterns = [
            #"<amp-story-page-outlink[\s\S]{0,1600}?<a[^>]+href\s*=\s*["']([^"']+)["']"#,
            #"<amp-story-page-attachment[^>]+href\s*=\s*["']([^"']+)["']"#,
        ]
        let pageHost = pageURL.host?.lowercased().replacingOccurrences(of: "www.", with: "")
        for raw in patterns.flatMap({ html.matches($0, group: 1) }) {
            let decoded = raw.replacingOccurrences(of: "&amp;", with: "&")
            guard let candidate = URL(string: decoded, relativeTo: pageURL)?.absoluteURL,
                  let candidateHost = candidate.host?.lowercased()
                    .replacingOccurrences(of: "www.", with: ""),
                  candidateHost == pageHost,
                  !candidate.path.lowercased().contains("/web-stories/"),
                  !DiscoveryEngine.looksLikeMediaFile(candidate.absoluteString),
                  let safe = try? URLSafety.validatedRemoteURL(candidate.absoluteString) else { continue }
            return safe
        }
        return nil
    }

    /// Fills gaps in `primary` from other successful parses so a site that
    /// publishes, say, nutrition only in microdata still exports it.
    private func merge(_ primary: ParserResult, with others: [ParserResult]) -> ParserResult {
        var result = primary
        for other in others {
            if result.summary == nil { result.summary = other.summary }
            if result.author == nil { result.author = other.author }
            if result.imageURL == nil { result.imageURL = other.imageURL }
            if result.yield == nil { result.yield = other.yield }
            if result.servings == nil { result.servings = other.servings }
            if result.canonicalURL == nil { result.canonicalURL = other.canonicalURL }
            if result.nutrition.isEmpty { result.nutrition = other.nutrition }
            if result.cuisines.isEmpty { result.cuisines = other.cuisines }
            if result.categories.isEmpty { result.categories = other.categories }
            if result.keywords.isEmpty { result.keywords = other.keywords }
            if result.diets.isEmpty { result.diets = other.diets }
            if result.times.prepMinutes == nil { result.times.prepMinutes = other.times.prepMinutes }
            if result.times.cookMinutes == nil { result.times.cookMinutes = other.times.cookMinutes }
            if result.times.totalMinutes == nil { result.times.totalMinutes = other.times.totalMinutes }
        }
        result.times = result.times.normalized()
        return result
    }

    // MARK: - Fallback profile

    private func genericProfile(for url: URL) -> SourceProfile {
        let host = url.host?.lowercased() ?? "unknown"
        return SourceProfile(
            id: "custom-\(Hashing.sha256(host).prefix(12))",
            name: host,
            domains: [host],
            baseURL: "\(url.scheme ?? "https")://\(host)",
            enabled: true,
            discoveryEnabled: false,
            discoveryMode: .directOnly,
            parserMode: .nativeFirst,
            minimumDelaySeconds: 5,
            maximumConcurrency: 1,
            dailyRequestLimit: 50,
            robotsRequired: true,
            imageDownloadEnabled: true,
            sitemapURLs: [],
            recipeURLPatterns: [],
            excludedURLPatterns: SourceProfile.defaultExcludedPatterns,
            tags: ["Custom"],
            notes: "Created automatically for a one-off import.",
            health: .unknown
        )
    }
}
