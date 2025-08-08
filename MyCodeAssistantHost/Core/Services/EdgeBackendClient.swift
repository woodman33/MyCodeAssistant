import Foundation

public struct EdgeBackendClient {
    public let baseURL: URL

    public init(envURL: String? = ProcessInfo.processInfo.environment["WORKER_URL"]) {
        let fallback = "https://mca-edge-worker.wmeldman33.workers.dev"
        self.baseURL = URL(string: envURL ?? fallback)!
    }

    public func chat(_ message: String) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["message": message]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw NSError(domain: "MCA", code: -1) }
        guard (200..<300).contains(http.statusCode) else { throw NSError(domain: "MCA", code: http.statusCode) }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let reply = obj["reply"] as? String {
            return reply
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
