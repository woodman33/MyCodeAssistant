# MyCodeAssistant

A macOS application with an Xcode Source Editor Extension for AI-powered code assistance.

## Version

**v1.1.0** - MVP Release

## Features

### Current Scope (v1.1.0)
- ✅ macOS native application with SwiftUI interface
- ✅ Xcode Source Editor Extension integration
- ✅ Support for two AI providers:
  - OpenAI (GPT models)
  - OpenRouter (access to multiple models)
- ✅ Chat-based interface for code assistance
- ✅ Message history and conversation management
- ✅ Code formatting and response rendering

### Known Limitations
- Extension functionality is currently placeholder (menu registration only)
- No persistence of chat history between app restarts
- Limited to text-based interactions (no file context yet)
- API keys must be manually configured via .env file

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later (for extension support)
- Valid API keys for OpenAI and/or OpenRouter

## Build Instructions

### Prerequisites
1. Clone the repository:
   ```bash
   git clone https://github.com/woodman33/MyCodeAssistant.git
   cd MyCodeAssistant
   ```

2. Create a `.env` file in the project root with your API keys:
   ```bash
   cp .env.example .env
   ```
   
   Edit `.env` and add your keys:
   ```
   OPENAI_API_KEY=your_openai_api_key_here
   OPENROUTER_API_KEY=your_openrouter_api_key_here
   ```

### Building from Source

#### Using Xcode GUI
1. Open `MyCodeAssistant.xcodeproj` in Xcode
2. Select the "MyCodeAssistantHost" scheme
3. Press ⌘+B to build or ⌘+R to build and run

#### Using Command Line
```bash
# Build the project
xcodebuild -scheme MyCodeAssistantHost -destination 'platform=macOS' build

# Run the built application
open ~/Library/Developer/Xcode/DerivedData/MyCodeAssistant-*/Build/Products/Debug/MyCodeAssistantHost.app
```

## Installation

### Installing the Xcode Extension
1. Build and run MyCodeAssistantHost.app at least once
2. Open System Settings → Privacy & Security → Extensions → Xcode Source Editor
3. Enable "MyCodeAssistantExtension"
4. Restart Xcode
5. The extension will appear under Xcode's Editor menu

### Running the Host Application
The host application must be running for the extension to function:
```bash
open /Applications/MyCodeAssistantHost.app
```

## Usage

### Host Application
1. Launch MyCodeAssistantHost.app
2. Select your preferred AI provider (OpenAI or OpenRouter)
3. Enter your prompt in the text editor
4. Click "Send" to get AI assistance
5. View responses in the message list

### Xcode Extension
1. Ensure MyCodeAssistantHost.app is running
2. In Xcode, select code you want assistance with
3. Go to Editor → MyCodeAssistant → [Command]
4. Results will be processed through the host application

## Environment Configuration

### Required Environment Variables
- `OPENAI_API_KEY`: Your OpenAI API key
- `OPENROUTER_API_KEY`: Your OpenRouter API key

### Optional Configuration
Additional settings can be configured in the app's Settings view:
- Model selection
- Temperature and other parameters
- Response formatting options

## Development

### Project Structure
```
MyCodeAssistant/
├── MyCodeAssistantHost/       # Main macOS application
│   ├── Core/                  # Business logic and providers
│   │   ├── Providers/         # AI provider implementations
│   │   ├── Services/          # Core services
│   │   └── Models/           # Data models
│   └── SwiftUI/              # User interface
├── MyCodeAssistantExtension/  # Xcode Source Editor Extension
└── MyCodeAssistant.xcodeproj/ # Xcode project file
```

### Adding New Providers
New AI providers can be added by:
1. Implementing the `LLMProviderProtocol`
2. Adding the provider to `ProviderFactory`
3. Updating the UI to include the new option

## Troubleshooting

### Extension Not Appearing in Xcode
1. Ensure the host app has been run at least once
2. Check System Settings → Extensions → Xcode Source Editor
3. Restart Xcode after enabling the extension
4. Try running: `pluginkit -mAvvv -p com.apple.dt.Xcode.extension.source-editor`

### API Key Issues
- Verify your .env file is in the project root
- Ensure keys are correctly formatted without quotes
- Check API key validity with the provider's dashboard

### Build Errors
- Clean build folder: ⌘+Shift+K in Xcode
- Delete DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData/MyCodeAssistant-*`
- Ensure you're using Xcode 15.0 or later

## Security & Signing

### Code Signing (TODO)
The application requires proper code signing for distribution:
- Developer ID Application certificate for the host app
- Developer ID Application certificate for the extension
- Notarization for macOS Gatekeeper approval

*Note: Current builds use ad-hoc signing for development only*

### Distribution Build Process (Placeholder)
To create a signed and notarized release:

```bash
# TODO: Once Developer ID certificates are available:

# 1. Archive the app with proper signing
xcodebuild archive \
  -scheme MyCodeAssistantHost \
  -archivePath ./build/MyCodeAssistant.xcarchive \
  CODE_SIGN_IDENTITY="Developer ID Application: YOUR_NAME" \
  DEVELOPMENT_TEAM="YOUR_TEAM_ID"

# 2. Export the archive for distribution
xcodebuild -exportArchive \
  -archivePath ./build/MyCodeAssistant.xcarchive \
  -exportPath ./build/Release \
  -exportOptionsPlist ExportOptions.plist

# 3. Notarize the app
xcrun notarytool submit ./build/Release/MyCodeAssistantHost.app \
  --apple-id "your-apple-id@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "app-specific-password" \
  --wait

# 4. Staple the notarization ticket
xcrun stapler staple ./build/Release/MyCodeAssistantHost.app

# 5. Create DMG for distribution (optional)
hdiutil create -volname "MyCodeAssistant" \
  -srcfolder ./build/Release/MyCodeAssistantHost.app \
  -ov -format UDZO MyCodeAssistant-v1.1.0.dmg
```

### Required for Distribution
- [ ] Apple Developer Program membership
- [ ] Developer ID Application certificate
- [ ] App-specific password for notarization
- [ ] ExportOptions.plist configured for Developer ID distribution

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

[License information to be added]

## Support

For issues and questions:
- Open an issue on [GitHub](https://github.com/woodman33/MyCodeAssistant/issues)
- Check existing issues for similar problems

## Roadmap

### Future Enhancements
- [ ] Additional AI providers (Anthropic, Google, etc.)
- [ ] File context awareness in extension
- [ ] Persistent chat history
- [ ] Custom prompt templates
- [ ] Multi-file refactoring support
- [ ] Code analysis and suggestions
- [ ] Integration with version control