// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyCodeAssistant",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MyCodeAssistant", targets: ["MyCodeAssistant"]),
    ],
    dependencies: [
        // Add any external dependencies here
    ],
    targets: [
        .executableTarget(
            name: "MyCodeAssistant",
            dependencies: [],
            path: ".",
            sources: [
                "SwiftUI/App.swift",
                "SwiftUI/ContentView.swift",
                "SwiftUI/ChatViewModel.swift",
                "SwiftUI/InputBar.swift",
                "SwiftUI/MessageCard.swift",
                "SwiftUI/ResponseFormatter.swift",
                "SwiftUI/SettingsView.swift",
                "Core/Models/AppSettings.swift",
                "Core/Models/ChatMessage.swift",
                "Core/Models/UnifiedRequest.swift",
                "Core/Enums/LLMProvider.swift",
                "Core/Protocols/LLMProviderProtocol.swift",
                "Core/Providers/BaseProvider.swift",
                "Core/Providers/OpenAIProvider.swift",
                "Core/Providers/AnthropicProvider.swift",
                "Core/Providers/GeminiProvider.swift",
                "Core/Providers/AbacusAIProvider.swift",
                "Core/Providers/GrokProvider.swift",
                "Core/Providers/HuggingFaceProvider.swift",
                "Core/Providers/MistralProvider.swift",
                "Core/Providers/MoonshotProvider.swift",
                "Core/Providers/NovitaProvider.swift",
                "Core/Providers/OpenRouterProvider.swift",
                "Core/Providers/PortkeyProvider.swift",
                "Core/Providers/TogetherProvider.swift",
                "Core/Services/APIKeyManager.swift",
                "Core/Services/ConversationManager.swift",
                "Core/Services/ProviderFactory.swift",
                "Core/Services/SharedServices.swift",
                "Core/Utilities/ErrorHandling.swift",
                "Core/Utilities/NetworkUtilities.swift"
            ]
        ),
        .target(
            name: "AICommand",
            dependencies: [],
            path: "AICommand",
            sources: [
                "SourceEditorCommand.swift"
            ]
        )
    ]
)