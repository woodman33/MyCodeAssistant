import Foundation

public struct UISettings: Codable, Equatable {
    public var gpt5ApiUrl: String
    public var gpt5Model: String
    public var requestTimeout: TimeInterval
    public var temperature: Double
}

public final class UISettingsManager {
    public static let shared = UISettingsManager()
    private let defaultsKey = "com.mycodeassistant.uiSettings"
    private let queue = DispatchQueue(label: "ui.settings.manager", qos: .userInitiated)
    public private(set) var settings: UISettings

    private init() {
        // Prefer persisted settings; fall back to environment; then hard defaults.
        let env = ProcessInfo.processInfo.environment
        let envUrl   = env["GPT5_API_URL"] ?? ""
        let envModel = env["GPT5_MODEL"]   ?? ""

        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(UISettings.self, from: data) {
            self.settings = saved
        } else {
            self.settings = UISettings(
                gpt5ApiUrl: envUrl.isEmpty ? "https://api.openai.com/v1/chat/completions" : envUrl,
                gpt5Model:  envModel.isEmpty ? "gpt-5-turbo" : envModel,
                requestTimeout: 60,
                temperature: 0.2
            )
            persist()
        }
    }

    public func update(_ mutate: (inout UISettings) -> Void) {
        queue.sync {
            var next = settings
            mutate(&next)
            settings = next
            persist()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}