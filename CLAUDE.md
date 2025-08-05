# MyCodeAssistant — Claude Code Main Instructions

## Purpose
Enhance the Xcode Source Editor Extension ("MyCodeAssistant") to support multiple LLM providers, response formatting, beautiful SwiftUI-based chat UI, provider settings, and readiness for deployment.

## Commands & Build
- Open Xcode and build the extension target "AICommand".
- Use SwiftUI preview or run in Xcode Editor to test.
- macOS version supported: Ventura / Sonoma.
- Settings stored via `UserDefaults`.
- UI: SwiftUI chat window + provider selector dropdown.

## Tooling
- Use Apple's `swift build`, Xcode CLI for testing.
- Use git for commit and push.
- No external package manager (CocoaPods or SPM) unless needed.

## UX Goals
- Elegant dark mode SwiftUI chat UI with bubbles, prompt input, and provider selector.
- Nice message history, scrollable, keyboard-first.

## Subagent-use Guidelines
- PlannerAgent: high-level plan,
- CoderAgent: make file edits,
- UIAgent: build SwiftUI UI,
- FormatterAgent: parse and insert responses,
- QAAgent: run build, catch errors, fix,
- ReviewerAgent: review for UX and code style.

## Deployment
Project ready to push to GitHub with tags and release version. Add README with usage instructions, how to run extension, API configuration.

## Constraints
- Single unified codebase.
- Clean incremental commits.
- No secrets in code—env/API keys in `UserDefaults` or config file.