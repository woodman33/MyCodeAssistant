import Foundation

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [Message]
    struct Message: Codable { let role: String; let content: String }
}

struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        let message: Message
    }
    struct Message: Codable {
        let role: String
        let content: String
    }
    let choices: [Choice]
}

func fetchGPT5Response(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
    let cfg = UISettingsManager.shared.settings
    guard let url = URL(string: cfg.gpt5ApiUrl) else {
        completion(.failure(NSError(domain: "GPT5Service", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])))
        return
    }

    // For auth, check env keys in this priority:
    // 1) GPT5_API_KEY
    // 2) OPENAI_API_KEY
    // 3) OPENROUTER_API_KEY
    let apiKey = ProcessInfo.processInfo.environment["GPT5_API_KEY"] ??
                 ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ??
                 ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]

    guard let finalApiKey = apiKey, !finalApiKey.isEmpty else {
        completion(.failure(NSError(domain: "GPT5Service", code: 2, userInfo: [NSLocalizedDescriptionKey: "API key not found. Please set GPT5_API_KEY, OPENAI_API_KEY, or OPENROUTER_API_KEY."])))
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = cfg.requestTimeout
    request.addValue("Bearer \(finalApiKey)", forHTTPHeaderField: "Authorization")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    let body = ChatCompletionRequest(model: cfg.gpt5Model,
                                     messages: [.init(role: "user", content: prompt)])
    request.httpBody = try? JSONEncoder().encode(body)

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            completion(.failure(error))
            return
        }
        guard let data = data else {
            completion(.failure(NSError(domain: "GPT5Service", code: 3, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
            return
        }
        do {
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            if let reply = decoded.choices.first?.message.content {
                completion(.success(reply))
            } else {
                completion(.failure(NSError(domain: "GPT5Service", code: 4, userInfo: [NSLocalizedDescriptionKey: "No content in response"])))
            }
        } catch {
            completion(.failure(error))
        }
    }.resume()
}