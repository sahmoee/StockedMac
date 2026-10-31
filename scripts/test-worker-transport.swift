import Foundation

@main struct WorkerTransportChecks {
    static func main() async throws {
        for raw in ["NaN", "inf", "-1", "bogus", ""] {
            precondition(MacWorkerClient.retryAfter(raw) == nil)
        }
        precondition(MacWorkerClient.retryAfter(" 90 ") == 90)
        precondition(MacWorkerClient.retryAfter("Thu, 01 Jan 1970 02:00:00 GMT", now: Date(timeIntervalSince1970:0)) == 7200)
        precondition(MacWorkerClient.retryAfter("Thu, 01 Jan 1970 00:00:00 GMT") == 0)
        let response = try MacWorkerClient.decodeText(from: Data("{\"content\":[{\"type\":\"text\",\"text\":\"Ready\"}]}".utf8))
        precondition(response.text == "Ready")
        do {
            _ = try MacWorkerClient.decodeText(from: Data("{\"content\":[],\"stop_reason\":\"max_tokens\"}".utf8))
            preconditionFailure("Empty response accepted")
        } catch {}
        print("Worker transport policy: 10 checks passed; no network requests")
    }
}
