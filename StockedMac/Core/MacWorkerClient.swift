// MacWorkerClient.swift — transport for the Stocked Cloudflare Worker.
//
// The iOS app's StockedWorkerClient is entangled with QA process tracking, a remote kill
// switch, an on-disk AI result cache, a session-token actor and a connectivity monitor —
// five subsystems that exist for reasons specific to a phone app that ships to testers.
// None of that belongs in a fresh Mac app, so this is a lean re-implementation of the same
// wire contract rather than a port.
//
// What is preserved exactly, because the Worker keys off it:
//   • route rawValues            — the Worker switches on `route`
//   • schemaVersion per route    — the Worker validates its response shape against this
//   • cacheRevision per route    — participates in the Worker's own cache key
//   • the `X-Stocked-Key` header — how the endpoint authenticates the caller
//   • `clientVersion` enrichment — so server logs can tell Mac traffic from phone traffic
//
// Keep these in step with Stocked/StockedWorkerClient.swift on iOS. If a route's schema
// changes there and not here, the Mac starts getting schemaMismatch errors.

import Foundation
import os

/// Authenticated utility requests must never forward a Worker key through a redirect.
nonisolated final class MacWorkerRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

nonisolated enum MacWorkerRoute: String, Sendable {
    case receiptText
    case receiptImage
    case barcode
    case recipeImport
    case recipeGeneration
    case inventoryIntent
    case inventoryScan

    /// Response-shape version. Must match the iOS table exactly.
    var schemaVersion: Int {
        switch self {
        case .receiptText, .receiptImage:       return 2
        case .barcode:                          return 1
        case .recipeImport, .recipeGeneration:  return 2
        case .inventoryIntent:                  return 2
        case .inventoryScan:                    return 2
        }
    }

    /// Bumped when prompt semantics change without a schema change. Must match iOS.
    var cacheRevision: Int {
        switch self {
        case .receiptText, .receiptImage:       return 2
        case .barcode:                          return 2
        case .recipeImport, .recipeGeneration:  return 3
        case .inventoryIntent:                  return 3
        case .inventoryScan:                    return 3
        }
    }
}

// MARK: - Decoded response

nonisolated struct MacAITextResponse: Sendable, Equatable {
    let text: String
    let stopReason: String?
    let model: String?
    let schemaVersion: Int?

    var wasTruncated: Bool { stopReason == "max_tokens" }
}

// MARK: - Client

nonisolated enum MacWorkerClient {

    static func retryAfter(_ raw: String?, now: Date = Date()) -> TimeInterval? {
        guard let raw else { return nil }
        if let seconds = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return seconds.isFinite && seconds >= 0 ? seconds : nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: raw).map { max(0, $0.timeIntervalSince(now)) }
    }

    private static func boundedData(for original: URLRequest) async throws -> (Data, URLResponse) {
        guard !Task.isCancelled else { throw MacServiceError.cancelled }
        guard let url = original.url, url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else {
            throw MacServiceError.invalidRequest("A secure Worker URL is required.")
        }
        let limit = 16 * 1024 * 1024
        guard (original.httpBody?.count ?? 0) <= limit else {
            throw MacServiceError.invalidRequest("The request is too large. Use a smaller batch.")
        }
        var request = original
        request.timeoutInterval = request.timeoutInterval.isFinite ? min(120, max(5, request.timeoutInterval)) : 30
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = request.timeoutInterval
        let session = URLSession(configuration: configuration, delegate: MacWorkerRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard response.expectedContentLength <= limit else {
                throw MacServiceError.malformedResponse("The service response is too large.")
            }
            var data = Data()
            for try await byte in bytes {
                if data.count % 16384 == 0 { try Task.checkCancellation() }
                guard data.count < limit else { throw MacServiceError.malformedResponse("The service response is too large.") }
                data.append(byte)
            }
            try Task.checkCancellation()
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                guard !data.isEmpty else { throw MacServiceError.malformedResponse("The service returned an empty response.") }
                guard !(http.mimeType?.lowercased().contains("text/html") ?? false) else {
                    throw MacServiceError.malformedResponse("The service returned a web page instead of data.")
                }
            }
            return (data, response)
        } catch is CancellationError { throw MacServiceError.cancelled }
        catch let error as URLError where error.code == .cancelled { throw MacServiceError.cancelled }
    }

    private static let log = Logger(subsystem: "com.sowens.StockedMac", category: "worker")

    static var endpoint: URL? { URL(string: MacBuildConfig.receiptWorkerURL) }
    static var isConfigured: Bool { MacBuildConfig.isWorkerConfigured }

    /// Typed utility routes (retail catalogs, configuration, health) use GET and return
    /// direct JSON rather than an Anthropic envelope. Credentials and error handling stay
    /// centralized here so feature clients never invent their own auth transport.
    static func getData(path: String,
                        query: [String: String] = [:],
                        timeout: TimeInterval = 20) async throws -> Data {
        guard let base = endpoint, MacBuildConfig.isWorkerConfigured else {
            throw MacServiceError.notConfigured("The Stocked Worker key")
        }
        let relative = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(url: base.appendingPathComponent(relative), resolvingAgainstBaseURL: false)
        components?.queryItems = query.sorted { $0.key < $1.key }.map(URLQueryItem.init)
        guard let url = components?.url else { throw MacServiceError.invalidRequest("The Worker URL is invalid.") }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        MacBuildConfig.authorizeWorkerRequest(&request)
        request.timeoutInterval = timeout
        do {
            let (data, response) = try await boundedData(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw MacServiceError.malformedResponse("The Worker returned no HTTP response.")
            }
            if http.statusCode == 429 {
                throw MacServiceError.rateLimited(
                    retryAfter: retryAfter(http.value(forHTTPHeaderField: "Retry-After")))
            }
            guard 200..<300 ~= http.statusCode else {
                throw MacServiceError.httpStatus(http.statusCode, nil)
            }
            return data
        } catch let error as MacServiceError { throw error }
        catch is CancellationError { throw MacServiceError.cancelled }
        catch { throw MacServiceError.transport(error.localizedDescription) }
    }

    static func postData(path: String, body: Data, timeout: TimeInterval = 30) async throws -> Data {
        guard let base = endpoint, MacBuildConfig.isWorkerConfigured else {
            throw MacServiceError.notConfigured("The Stocked Worker key")
        }
        let relative = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = base.appendingPathComponent(relative)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        MacBuildConfig.authorizeWorkerRequest(&request)
        request.timeoutInterval = timeout
        let (data, response) = try await boundedData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MacServiceError.malformedResponse("The Worker returned no HTTP response.")
        }
        if http.statusCode == 429 {
            throw MacServiceError.rateLimited(retryAfter: retryAfter(http.value(forHTTPHeaderField: "Retry-After")))
        }
        guard 200..<300 ~= http.statusCode else {
            throw MacServiceError.httpStatus(http.statusCode, nil)
        }
        return data
    }

    /// POST a payload to a route and return the raw response body.
    ///
    /// The payload stays a JSON-compatible dictionary at the call site (matching iOS) but is
    /// serialised here, so nothing untyped crosses a concurrency boundary.
    static func requestData(route: MacWorkerRoute,
                            payload: [String: Any],
                            timeout: TimeInterval = 30) async throws -> Data {
        guard let endpoint else { throw MacServiceError.notConfigured("Stocked AI") }
        guard MacBuildConfig.isWorkerConfigured else {
            throw MacServiceError.notConfigured("The Stocked Worker key")
        }

        var enriched = payload
        enriched["route"]         = route.rawValue
        enriched["schemaVersion"] = route.schemaVersion
        enriched["clientVersion"] = "mac-\(MacBuildConfig.version)"
        enriched["cacheRevision"] = route.cacheRevision

        guard JSONSerialization.isValidJSONObject(enriched) else {
            throw MacServiceError.invalidRequest("The request contains unsupported values.")
        }
        let body: Data
        do { body = try JSONSerialization.data(withJSONObject: enriched, options: [.sortedKeys]) }
        catch { throw MacServiceError.invalidRequest(error.localizedDescription) }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        MacBuildConfig.authorizeWorkerRequest(&request)
        request.httpBody = body
        request.timeoutInterval = timeout

        do {
            let (data, response) = try await boundedData(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw MacServiceError.malformedResponse("The Worker returned no HTTP response.")
            }
            if http.statusCode == 429 {
                let retry = retryAfter(http.value(forHTTPHeaderField: "Retry-After"))
                throw MacServiceError.rateLimited(retryAfter: retry)
            }
            guard (200..<300).contains(http.statusCode) else {
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let detail = object?["error"] as? String
                if (object?["code"] as? String) == "kvQuota" {
                    throw MacServiceError.quotaExhausted(
                        detail ?? "Household sync storage is temporarily unavailable.")
                }
                throw MacServiceError.httpStatus(http.statusCode, detail)
            }
            // Validate the envelope here so a truncated or empty body fails loudly at the
            // transport layer rather than as a confusing parse error three frames up.
            _ = try decodeText(from: data)
            return data
        } catch let error as MacServiceError {
            throw error
        } catch is CancellationError {
            throw MacServiceError.cancelled
        } catch {
            throw MacServiceError.transport(error.localizedDescription)
        }
    }

    /// POST and return the assistant's text, with the schema version checked.
    static func completion(route: MacWorkerRoute,
                           payload: [String: Any],
                           timeout: TimeInterval = 30) async throws -> MacAITextResponse {
        let data = try await requestData(route: route, payload: payload, timeout: timeout)
        let response = try decodeText(from: data)
        if let actual = response.schemaVersion, actual != route.schemaVersion {
            throw MacServiceError.malformedResponse(
                "This version of Stocked for Mac expects response format \(route.schemaVersion) "
                + "but the server sent \(actual). Update the app.")
        }
        return response
    }

    /// Convenience: POST and decode the assistant's text as a JSON object.
    static func completionObject(route: MacWorkerRoute,
                                 payload: [String: Any],
                                 timeout: TimeInterval = 30) async throws -> [String: Any] {
        let response = try await completion(route: route, payload: payload, timeout: timeout)
        return try jsonObject(from: response.text)
    }

    // MARK: - Envelope decoding
    //
    // Mirrors AIResponseDecoder on iOS. The Worker may answer in an Anthropic-shaped
    // envelope (a `content` array of blocks) or as a typed object it built itself; both
    // are handled, and an `error` key wins over either.

    static func decodeText(from data: Data) throws -> MacAITextResponse {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? String {
                let upstream = object["upstreamStatus"] as? Int
                throw MacServiceError.httpStatus(upstream ?? 500, error)
            }

            if let content = object["content"] as? [[String: Any]] {
                let text = content.compactMap { block -> String? in
                    guard (block["type"] as? String ?? "text") == "text" else { return nil }
                    return block["text"] as? String
                }.joined(separator: "\n")
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MacServiceError.malformedResponse("The assistant returned no text.")
                }
                let response = MacAITextResponse(text: text,
                                                 stopReason: object["stop_reason"] as? String,
                                                 model: object["model"] as? String,
                                                 schemaVersion: object["schemaVersion"] as? Int)
                if response.wasTruncated { throw MacServiceError.truncatedResponse }
                return response
            }

            // Typed Worker response returned directly rather than wrapped.
            if let direct = try? JSONSerialization.data(withJSONObject: object),
               let text = String(data: direct, encoding: .utf8) {
                return MacAITextResponse(text: text, stopReason: nil, model: nil,
                                         schemaVersion: object["schemaVersion"] as? Int)
            }
        }

        guard let raw = String(data: data, encoding: .utf8), !raw.isEmpty else {
            throw MacServiceError.malformedResponse("The service returned unreadable data.")
        }
        return MacAITextResponse(text: raw, stopReason: nil, model: nil, schemaVersion: nil)
    }

    /// Pull a JSON object out of model text that may be fenced or have prose around it.
    static func jsonObject(from text: String) throws -> [String: Any] {
        let stripped = stripCodeFences(text)

        if let data = stripped.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        if let slice = balancedSlice(in: stripped, opening: "{", closing: "}"),
           let data = slice.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        // Models occasionally leave a trailing comma before a closing bracket. Repair only
        // that narrow syntax error — never invent fields or reshape data.
        let repaired = stripped.replacingOccurrences(of: #",\s*([}\]])"#, with: "$1",
                                                     options: .regularExpression)
        if let slice = balancedSlice(in: repaired, opening: "{", closing: "}"),
           let data = slice.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        throw MacServiceError.malformedResponse("No usable JSON was found in the response.")
    }

    static func stripCodeFences(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            if let firstNewline = value.firstIndex(of: "\n") {
                value = String(value[value.index(after: firstNewline)...])
            }
            if let closing = value.range(of: "```", options: .backwards) {
                value.removeSubrange(closing.lowerBound..<value.endIndex)
            }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first balanced `{ … }` (or `[ … ]`) run, ignoring braces inside string literals.
    private static func balancedSlice(in text: String,
                                      opening: Character,
                                      closing: Character) -> String? {
        guard let start = text.firstIndex(of: opening) else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == opening { depth += 1 }
                else if character == closing {
                    depth -= 1
                    if depth == 0 { return String(text[start...index]) }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
