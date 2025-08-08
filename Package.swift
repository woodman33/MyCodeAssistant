// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyCodeAssistant",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MyCodeAssistantCore", targets: ["MyCodeAssistantCore"]),
    ],
    dependencies: [
        // Add any external dependencies here
    ],
    targets: [
        .target(
            name: "MyCodeAssistantCore",
            dependencies: [],
            path: "MyCodeAssistantHost",
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
                "Core/Providers/EdgeProvider.swift",
                "Core/Providers/OpenAIProvider.swift",
                "Core/Providers/OpenRouterProvider.swift",
                "Core/Services/APIKeyManager.swift",
                "Core/Services/AuthStateStore.swift",
                "Core/Services/ConversationManager.swift",
                "Core/Services/GuardrailService.swift",
                "Core/Services/ProviderFactory.swift",
                "Core/Services/SharedServices.swift",
                "Core/Utilities/ErrorHandling.swift",
                "Core/Utilities/NetworkUtilities.swift"
            ]
        ),
        .testTarget(
            name: "MyCodeAssistantTests",
            dependencies: ["MyCodeAssistantCore"],
            path: "MyCodeAssistantTests",
            sources: [
                "GuardrailServiceTests.swift",
                "SettingsViewTests.swift",
                "AuthStateStoreTests.swift"
            ]
        )
    ]
)