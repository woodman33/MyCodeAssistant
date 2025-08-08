#!/bin/bash

# ===============================================================================
# MyCodeAssistant Edge Backend - Secrets Setup Script
# ===============================================================================
# This script contains all the wrangler commands needed to set up secrets
# for the Cloudflare Workers deployment.
#
# IMPORTANT: Run this script from the edge-backend directory
# Prerequisites: wrangler CLI must be installed and authenticated
# ===============================================================================

set -e  # Exit on error

echo "========================================="
echo "MyCodeAssistant Edge Backend Secrets Setup"
echo "========================================="
echo ""
echo "This script will guide you through setting up all required secrets"
echo "for your Cloudflare Workers deployment."
echo ""
echo "Prerequisites:"
echo "  - wrangler CLI installed (npm install -g wrangler)"
echo "  - Authenticated with Cloudflare (wrangler login)"
echo "  - Account ID: 091c9e59ca0fc3bea9f9d432fa12a3b1"
echo ""
echo "Press Enter to continue or Ctrl+C to cancel..."
read

# ===============================================================================
# Required Secrets
# ===============================================================================

echo ""
echo "Setting up required secrets..."
echo "You will be prompted to enter each secret value."
echo ""

# OpenAI API Key (for AI/LLM operations)
echo "1. Setting OPENAI_API_KEY..."
echo "   Purpose: Used for OpenAI GPT model interactions"
echo "   Format: sk-..."
wrangler secret put OPENAI_API_KEY

# OpenRouter API Key (for multi-model routing)
echo ""
echo "2. Setting OPENROUTER_API_KEY..."
echo "   Purpose: Used for OpenRouter multi-model access"
echo "   Format: sk-or-v1-..."
wrangler secret put OPENROUTER_API_KEY

# R2 Storage Access Keys
echo ""
echo "3. Setting R2_ACCESS_KEY_ID..."
echo "   Purpose: R2 bucket access authentication"
echo "   From: Cloudflare R2 API Tokens page"
wrangler secret put R2_ACCESS_KEY_ID

echo ""
echo "4. Setting R2_SECRET_ACCESS_KEY..."
echo "   Purpose: R2 bucket secret for authentication"
echo "   From: Cloudflare R2 API Tokens page"
wrangler secret put R2_SECRET_ACCESS_KEY

# GitHub Token (for repository operations)
echo ""
echo "5. Setting GITHUB_TOKEN..."
echo "   Purpose: GitHub API access for code operations"
echo "   Format: ghp_... or github_pat_..."
echo "   Scopes needed: repo, read:user"
wrangler secret put GITHUB_TOKEN

# ===============================================================================
# Optional Secrets
# ===============================================================================

echo ""
echo "========================================="
echo "Optional Secrets"
echo "========================================="
echo ""
echo "The following secrets are optional but recommended for enhanced functionality."
echo "Press Enter to skip any optional secret, or type 'yes' to set it."
echo ""

# LangFlow Webhook Secret (for webhook validation)
echo "6. LANGFLOW_WEBHOOK_SECRET (Optional)"
echo "   Purpose: Validates incoming webhooks from LangFlow pipelines"
echo "   Used for: HMAC-SHA256 signature validation"
echo "   Set this secret? (yes/skip): "
read set_langflow_secret
if [ "$set_langflow_secret" = "yes" ]; then
    wrangler secret put LANGFLOW_WEBHOOK_SECRET
fi

# Additional Cloudflare-specific secrets if needed
echo ""
echo "7. CLOUDFLARE_API_TOKEN (Optional)"
echo "   Purpose: Cloudflare API operations (if needed)"
echo "   Set this secret? (yes/skip): "
read set_cf_token
if [ "$set_cf_token" = "yes" ]; then
    wrangler secret put CLOUDFLARE_API_TOKEN
fi

# ===============================================================================
# Verification
# ===============================================================================

echo ""
echo "========================================="
echo "Secret Setup Complete!"
echo "========================================="
echo ""
echo "To verify your secrets have been set, run:"
echo "  wrangler secret list"
echo ""
echo "To update a secret, run:"
echo "  wrangler secret put SECRET_NAME"
echo ""
echo "To delete a secret, run:"
echo "  wrangler secret delete SECRET_NAME"
echo ""

# ===============================================================================
# Environment-specific Secrets
# ===============================================================================

echo "For environment-specific deployments:"
echo ""
echo "Production secrets:"
echo "  wrangler secret put OPENAI_API_KEY --env production"
echo "  wrangler secret put OPENROUTER_API_KEY --env production"
echo "  # ... repeat for other secrets"
echo ""
echo "Staging secrets:"
echo "  wrangler secret put OPENAI_API_KEY --env staging"
echo "  wrangler secret put OPENROUTER_API_KEY --env staging"
echo "  # ... repeat for other secrets"
echo ""

# ===============================================================================
# Notes
# ===============================================================================

echo "========================================="
echo "Important Notes:"
echo "========================================="
echo ""
echo "1. Secrets are encrypted and stored securely by Cloudflare"
echo "2. They are not visible in wrangler.toml or source code"
echo "3. Access secrets in your Worker code using: env.SECRET_NAME"
echo "4. Never commit actual secret values to version control"
echo "5. Use dev.vars file for local development (git-ignored)"
echo ""
echo "For local development, ensure your dev.vars file contains:"
echo "  OPENAI_API_KEY=your_key_here"
echo "  OPENROUTER_API_KEY=your_key_here"
echo "  R2_ACCESS_KEY_ID=your_key_here"
echo "  R2_SECRET_ACCESS_KEY=your_key_here"
echo "  GITHUB_TOKEN=your_token_here"
echo "  LANGFLOW_WEBHOOK_SECRET=your_secret_here"
echo ""
echo "Setup complete! You can now deploy your Workers with:"
echo "  npm run deploy"
echo ""