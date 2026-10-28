import Foundation

/// Asks Claude to sort senders into keep / promotional / spam. Only sender names,
/// addresses and subject lines are sent, never email bodies.
enum ClaudeClassifier {
    enum Choice: String { case keep, promotional, spam }

    struct Result {
        var choice: Choice
        var reason: String
    }

    private static let system = """
    You help one person clean up their email inbox. Their goal is to only receive email that matters to them.
    For each sender, decide:
    - "keep": a real person, or mail they need: receipts, bills, bank or security alerts, sign-in codes, shipping, \
    appointments, school, work, government, healthcare.
    - "promotional": marketing, newsletters, sales, digests, social notifications or other bulk mail they could unsubscribe from.
    - "spam": unsolicited junk, scams or phishing they almost certainly never signed up for.
    When unsure between keep and promotional, choose keep. Write the reason as one short, plain sentence \
    the person will read when deciding (for example "Weekly sale emails from a clothing store").
    """

    static func classify(_ groups: [(id: String, group: SenderGroup)], apiKey: String, model: String) async throws -> [String: Result] {
        var out: [String: Result] = [:]
        for chunk in groups.chunked(60) {
            let items: [[String: Any]] = chunk.map { item in
                [
                    "id": item.id,
                    "from_name": item.group.name,
                    "from_address": item.group.email,
                    "emails_recently": item.group.messages.count,
                    "has_unsubscribe_header": item.group.isBulk,
                    "recent_subjects": Array(item.group.messages.prefix(5).map(\.subject)),
                ]
            }
            let payload = String(data: try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys]), encoding: .utf8) ?? "[]"
            let results = try await request(payload: payload, apiKey: apiKey, model: model)
            out.merge(results) { _, new in new }
        }
        return out
    }

    private static func request(payload: String, apiKey: String, model: String) async throws -> [String: Result] {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "results": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string"],
                            "verdict": ["type": "string", "enum": ["keep", "promotional", "spam"]],
                            "reason": ["type": "string"],
                        ],
                        "required": ["id", "verdict", "reason"],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "required": ["results"],
            "additionalProperties": false,
        ]
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            "messages": [["role": "user", "content": "Classify these senders:\n\(payload)"]],
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if model == ClaudeModel.opus.rawValue {
            // If a safety classifier declines, let the API retry on a suitable model instead of failing.
            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
            throw NSError(domain: "Claude", code: status, userInfo: [NSLocalizedDescriptionKey: "Claude API: \(msg)"])
        }
        if json["stop_reason"] as? String == "refusal" { return [:] }

        let text = (json["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let results = parsed["results"] as? [[String: Any]] else { return [:] }

        var out: [String: Result] = [:]
        for r in results {
            guard let id = r["id"] as? String, let v = (r["verdict"] as? String).flatMap(Choice.init(rawValue:)) else { continue }
            out[id] = Result(choice: v, reason: r["reason"] as? String ?? "")
        }
        return out
    }
}
