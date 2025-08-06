# API Key Setup Instructions

## Required API Keys
To test MyCodeAssistant with live API calls, you need valid API keys for:
1. **OpenAI** - For GPT models
2. **OpenRouter** - For multi-model access

## Option 1: Environment File (Recommended for Testing)

### Step 1: Update the .env file
Edit the existing `.env` file in the project root:

```bash
# Replace 'test' with your actual API keys
OPENAI_API_KEY=your_actual_openai_api_key_here
OPENROUTER_API_KEY=your_actual_openrouter_api_key_here
```

**Important**: The `.env` file is already in `.gitignore` so your keys won't be committed.

### Step 2: Restart the application
After updating the keys, rebuild and restart:
```bash
# Clean build
xcodebuild clean build -scheme MyCodeAssistantHost -destination 'platform=macOS'

# Run the app
open ~/Library/Developer/Xcode/DerivedData/MyCodeAssistant-*/Build/Products/Debug/MyCodeAssistantHost.app
```

## Option 2: macOS Keychain (More Secure)

### Step 1: Add to Keychain via Terminal
```bash
# Add OpenAI key
security add-generic-password -a "$USER" -s "OPENAI_API_KEY" -w "your_actual_openai_key"

# Add OpenRouter key  
security add-generic-password -a "$USER" -s "OPENROUTER_API_KEY" -w "your_actual_openrouter_key"
```

### Step 2: Verify keys are stored
```bash
# List keys (won't show actual values)
security find-generic-password -s "OPENAI_API_KEY"
security find-generic-password -s "OPENROUTER_API_KEY"
```

## Getting API Keys

### OpenAI
1. Sign up at https://platform.openai.com
2. Navigate to API Keys section
3. Create a new secret key
4. Copy the key (starts with 'sk-')

### OpenRouter
1. Sign up at https://openrouter.ai
2. Go to Settings → API Keys
3. Create a new API key
4. Copy the key

## Testing Your Keys

### Quick Test Commands
```bash
# Test OpenAI
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"

# Test OpenRouter
curl https://openrouter.ai/api/v1/models \
  -H "Authorization: Bearer $OPENROUTER_API_KEY"
```

## Troubleshooting

### Common Issues
1. **"Invalid API Key"** - Double-check the key is copied correctly
2. **"Rate limit exceeded"** - Wait a few minutes or check your account limits
3. **"No response"** - Verify internet connection and API endpoint status

### Debugging in App
Check Console.app for error messages:
1. Open Console.app
2. Filter by "MyCodeAssistant"
3. Look for API-related errors

## Security Notes
- Never commit real API keys to version control
- Rotate keys regularly
- Use separate keys for development and production
- Monitor usage to detect any unauthorized access

---

Once you've added your API keys, we can proceed with runtime verification testing.