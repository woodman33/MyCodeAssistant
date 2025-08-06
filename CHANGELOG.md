# Changelog

All notable changes to MyCodeAssistant will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-01-06

### Added
- Initial MVP release with core functionality
- macOS native application with SwiftUI interface
- Xcode Source Editor Extension integration
- Support for OpenAI provider (GPT models)
- Support for OpenRouter provider (multi-model access)
- Chat-based interface for AI code assistance
- Message history and conversation management
- Code formatting and response rendering
- Environment-based API key configuration
- Comprehensive README documentation
- Smoke test suite and results

### Changed
- Limited provider scope to OpenAI and OpenRouter only for MVP
- Simplified UI for minimal viable functionality
- Streamlined build configuration for easier compilation

### Fixed
- Resolved all compilation errors (0 errors in build)
- Fixed provider initialization issues
- Corrected file structure and target dependencies
- Removed sensitive data from git history

### Security
- Implemented secure API key management via .env files
- Added .gitignore rules for sensitive files
- Cleaned git history to remove accidentally committed secrets

### Known Issues
- Extension functionality is placeholder only (menu registration works)
- No persistence of chat history between app restarts
- Limited to text-based interactions without file context
- Requires manual API key configuration

## [1.0.0] - 2025-01-05

### Added
- Initial project structure
- Basic Xcode project configuration
- Core provider architecture
- Foundation for multiple LLM providers

### Notes
- Pre-release development version
- Not suitable for production use