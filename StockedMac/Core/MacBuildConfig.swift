// MacBuildConfig.swift — build constants and configuration for the Mac app.
//
// Deliberately its own file rather than a copy of the iOS BuildConfig: this app has its
// own version lineage, its own bundle identifier, and needs none of the recipe-source API
// keys the phone carries. What it DOES share is the Worker contract — same base URL, same
// `X-Stocked-Key` header name — because both apps talk to the same server and join the
// same household.
//
// ── Security ────────────────────────────────────────────────────────────────────
// No key is hardcoded here. `StockedWorkerKey` is injected at build time from
// Secrets.xcconfig (STOCKED_WORKER_KEY) into Info.plist, exactly as on iOS. There is no
// AI vendor key in this app at all — every AI request goes through the Worker, which
// holds the Anthropic key server-side. Do not add one.
// ────────────────────────────────────────────────────────────────────────────────

import Foundation

nonisolated enum MacBuildConfig {

    // MARK: - Identity
    static let appName = "Stocked"
    static let company = "Sowens Studios"

    /// A separate product from the iOS app — separate project, separate bundle
    /// identifier — but the version line tracks the shared build history (the project file
    /// carries the real numbers; these are only the fallback if Info.plist is unreadable).
    private static let fallbackVersion     = "4.31"
    private static let fallbackBuildNumber = 91

    /// When the shared model layer was last checked against the phone's copy. Models.swift
    /// and KitchenMetrics.swift are byte-for-byte identical to the iOS tree as of this
    /// check; re-run the diff and update this string whenever either side moves, so the
    /// provenance stays honest rather than decorative.
    static let sharedModelLineage = "Shared models verified identical to iOS — Build 91, August 2026"

    static var buildNumber: Int {
        Int(bundleString("CFBundleVersion") ?? "") ?? fallbackBuildNumber
    }
    static var version: String {
        let v = bundleString("CFBundleShortVersionString") ?? ""
        return v.isEmpty ? fallbackVersion : v
    }
    static var displayLabel: String { "Version \(version) (\(buildNumber))" }

    static let buildDate = "August 2026"
    static let buildName = """
        Browsing has its own room now. A new Browse section sits under Household with \
        the full import pipeline in one place: a dropdown of a hundred recipe sites \u{2014} \
        the top fifty American and the top fifty worldwide \u{2014} grouped, searchable, and \
        guaranteed to load because the catalog now ships inside the app as well as \
        beside it. One Pause button parks everything mid-flight and Resume picks the \
        run back up; the queue can be bulk-verified so category pages never become \
        half-parsed drafts; images are validated, retried, and required before a \
        recipe may reach the kitchen, so the phone never shows a grey square. Approved \
        recipes and their pictures can sync to the Stocked Worker's new harvest cache, \
        past browse sessions can be restored with one click, and Auto-rotate walks as \
        many sources as you ask it to. Harvest keeps the reviewing \u{2014} with thumbnails, \
        bulk approve, and a filter for anything still missing its photo.
        """

    // MARK: - Environment
    nonisolated enum Environment: Sendable { case debug, release }
    static var environment: Environment {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }

    // MARK: - Worker
    /// The Stocked Cloudflare Worker. Same endpoint the iOS app uses — that is the whole
    /// point: this app is another member device on the same household, not a second system.
    static let receiptWorkerURL = "https://api.sowensstudios.com"

    /// Shared secret sent as `X-Stocked-Key` so the public endpoint rejects drive-by
    /// callers. Injected via Secrets.xcconfig STOCKED_WORKER_KEY → Info.plist
    /// StockedWorkerKey. Must match the Worker's STOCKED_SHARED_KEY. Never hardcode.
    static var stockedWorkerKey: String { bundleString("StockedWorkerKey") ?? "" }

    /// Applies the Worker auth header when a key is configured. One place so every caller
    /// spells the header the same way.
    static func authorizeWorkerRequest(_ request: inout URLRequest) {
        let key = stockedWorkerKey
        if !key.isEmpty { request.setValue(key, forHTTPHeaderField: "X-Stocked-Key") }
    }

    /// False when Secrets.xcconfig was never filled in. The UI uses this to explain why
    /// AI features and sync are unavailable instead of failing with a bare network error.
    static var isWorkerConfigured: Bool {
        !stockedWorkerKey.isEmpty && URL(string: receiptWorkerURL) != nil
    }

    static var networkTimeout: Double { Double(bundleString("NetworkTimeout") ?? "12") ?? 12 }

    // MARK: - Brand links
    static let websiteURL     = "https://sowensstudios.com"
    static let supportEmail   = "support@sowensstudios.com"
    static let privacyURL     = "https://sowensstudios.com/privacy"
    static let termsURL       = "https://sowensstudios.com/terms"
    static let supportPageURL = "https://sowensstudios.com/support"

    // MARK: - Helpers
    private static func bundleString(_ key: String) -> String? {
        guard let raw = Bundle.main.infoDictionary?[key] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Errors

/// The one error type the Mac app's service layer throws. Every case carries a message
/// that is safe and useful to show the user directly — no "Error Domain=…" leaking into
/// the UI.
nonisolated enum MacServiceError: LocalizedError, Sendable {
    case notConfigured(String)
    case offline
    case invalidRequest(String)
    case httpStatus(Int, String?)
    case rateLimited(retryAfter: TimeInterval?)
    case quotaExhausted(String)
    case malformedResponse(String)
    case truncatedResponse
    case transport(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConfigured(let what):
            return "\(what) isn't set up yet."
        case .offline:
            return "You're offline. Stocked will try again when the connection is back."
        case .invalidRequest(let detail):
            return "That request couldn't be sent. \(detail)"
        case .httpStatus(let code, let detail):
            return detail ?? "The server returned an error (\(code))."
        case .rateLimited(let retry):
            if let retry, retry > 0 {
                return "Too many requests. Try again in about \(Int(retry.rounded())) seconds."
            }
            return "Too many requests right now. Try again in a moment."
        case .quotaExhausted(let detail):
            return detail
        case .malformedResponse(let detail):
            return "The response couldn't be read. \(detail)"
        case .truncatedResponse:
            return "The response was cut off before it finished. Try a shorter request."
        case .transport(let detail):
            return detail
        case .cancelled:
            return "Cancelled."
        }
    }
}
