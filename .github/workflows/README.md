# GitHub Actions CI/CD Pipeline Documentation

## Overview

This repository uses GitHub Actions for continuous integration and deployment to Cloudflare Workers. The pipeline includes automated testing, linting, staging deployments for pull requests, and production deployments for the main branch.

## Workflow Files

### 1. `deploy.yml` - Production Deployment
- **Trigger**: Push to `main` branch or manual workflow dispatch
- **Purpose**: Deploy to production environment after passing all tests
- **Jobs**: Lint & Test → Deploy to Production → Smoke Tests

### 2. `staging.yml` - Staging Deployment
- **Trigger**: Pull request events (opened, synchronize, reopened)
- **Purpose**: Deploy PR changes to staging environment for testing
- **Jobs**: Test → Deploy to Staging → Comment URL on PR

### 3. `test.yml` - Testing and Quality Checks
- **Trigger**: All pushes and pull requests
- **Purpose**: Run comprehensive tests and quality checks
- **Jobs**: Lint → Type Check → Unit Tests → Build Verification → Security Scan

## Required GitHub Secrets

Configure these secrets in your GitHub repository settings under **Settings → Secrets and variables → Actions**:

### Cloudflare Secrets (Required)
| Secret Name | Description | Where to Find |
|-------------|-------------|---------------|
| `CLOUDFLARE_API_TOKEN` | API token for Cloudflare Workers deployment | [Cloudflare Dashboard → My Profile → API Tokens](https://dash.cloudflare.com/profile/api-tokens) |
| `CLOUDFLARE_ACCOUNT_ID` | Your Cloudflare account ID | [Cloudflare Dashboard → Right sidebar](https://dash.cloudflare.com) |

### Application Secrets (Required)
| Secret Name | Description | Example/Format |
|-------------|-------------|----------------|
| `OPENAI_API_KEY` | OpenAI API key for AI services | `sk-...` |
| `ANTHROPIC_API_KEY` | Anthropic Claude API key | `sk-ant-...` |
| `SUPABASE_URL` | Supabase project URL | `https://[project-id].supabase.co` |
| `SUPABASE_ANON_KEY` | Supabase anonymous/public key | `eyJ...` |
| `SUPABASE_SERVICE_KEY` | Supabase service role key | `eyJ...` |
| `LANGFLOW_BASE_URL` | LangFlow API base URL | `https://api.langflow.example.com` |
| `LANGFLOW_API_KEY` | LangFlow API authentication key | `lf_...` |
| `LANGFLOW_FLOW_ID` | LangFlow flow identifier | UUID format |
| `WEBHOOK_SECRET` | Secret for webhook authentication | Random string (min 32 chars) |
| `MCP_CONFIG` | Model Context Protocol configuration | JSON string |

### Integration Secrets (Optional)
| Secret Name | Description | Required For |
|-------------|-------------|--------------|
| `AIRTABLE_API_KEY` | Airtable API key | Airtable integration |
| `AIRTABLE_BASE_ID` | Airtable base identifier | Airtable integration |
| `AIRTABLE_TABLE_NAME` | Airtable table name | Airtable integration |

## Setup Instructions

### 1. Create Cloudflare API Token

1. Go to [Cloudflare Dashboard → API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Click "Create Token"
3. Use the "Edit Cloudflare Workers" template or create custom token with:
   - **Permissions**: 
     - Account: `Cloudflare Workers Scripts:Edit`
     - Zone: `Workers Routes:Edit` (if using custom domains)
   - **Account Resources**: Include your account
   - **Zone Resources**: Include specific zones or all zones
4. Copy the generated token and save as `CLOUDFLARE_API_TOKEN`

### 2. Configure GitHub Environments

Create environments in **Settings → Environments**:

#### Production Environment
- **Name**: `production`
- **Protection rules**:
  - Required reviewers: 1-2 reviewers
  - Restrict to `main` branch only
- **Secrets**: Add production-specific overrides if needed

#### Staging Environment
- **Name**: `staging`
- **Protection rules**: None (allow PR deployments)
- **Secrets**: Add staging-specific values if different from production

### 3. Branch Protection Rules

Configure branch protection for `main` in **Settings → Branches**:

1. **Add rule** for `main` branch
2. Enable these protections:
   - ✅ Require a pull request before merging
   - ✅ Require status checks to pass before merging
   - ✅ Require branches to be up to date before merging
   - ✅ Require conversation resolution before merging
   
3. **Required status checks**:
   - `Lint Code`
   - `TypeScript Type Checking`
   - `Unit Tests`
   - `Build Verification`
   - `cloudflare/staging` (for PR deployments)

### 4. Enable GitHub Actions

1. Go to **Settings → Actions → General**
2. Under "Actions permissions", select:
   - "Allow all actions and reusable workflows" OR
   - "Allow select actions" and add:
     - `actions/*`
     - `cloudflare/wrangler-action@v3`

3. Under "Workflow permissions":
   - ✅ Read and write permissions
   - ✅ Allow GitHub Actions to create and approve pull requests

## Local Development Setup

### Prerequisites
```bash
# Install Node.js 20+
node --version  # Should be >= 20.0.0

# Install dependencies
cd edge-backend
npm install
```

### Environment Variables
Create `edge-backend/.dev.vars` for local development:
```env
OPENAI_API_KEY=your_key_here
ANTHROPIC_API_KEY=your_key_here
SUPABASE_URL=your_url_here
SUPABASE_ANON_KEY=your_key_here
# ... other variables
```

### Running Tests Locally
```bash
# Type checking
npm run type-check

# Linting
npm run lint

# Unit tests
npm run test

# Build verification
npm run build
```

## Deployment Process

### Automatic Deployments

1. **Pull Request** → Automatically deploys to staging
2. **Merge to main** → Automatically deploys to production
3. **Manual deployment** → Use "Actions" tab → "Deploy to Cloudflare Workers" → "Run workflow"

### Rollback Process

If a deployment fails or causes issues:

1. **Immediate Rollback**:
   ```bash
   # Revert to previous deployment
   wrangler rollback --env production
   ```

2. **Git-based Rollback**:
   - Create a revert PR for the problematic commit
   - Merge to trigger new deployment with reverted code

3. **Manual Override**:
   - Use workflow dispatch with a known-good commit SHA
   - Select environment and run deployment

## Monitoring and Debugging

### View Deployment Logs
```bash
# Production logs
wrangler tail aged-thunder-8631

# Staging logs
wrangler tail aged-thunder-8631 --env staging
```

### Check Deployment Status
- **GitHub Actions**: Actions tab shows all workflow runs
- **Cloudflare Dashboard**: Workers & Pages section shows deployments
- **PR Comments**: Automated comments show staging URLs and status

## Troubleshooting

### Common Issues

1. **"Invalid API Token"**
   - Regenerate Cloudflare API token
   - Ensure token has correct permissions
   - Update `CLOUDFLARE_API_TOKEN` secret

2. **"Environment variable not found"**
   - Check all required secrets are set in GitHub
   - Verify secret names match exactly (case-sensitive)
   - Check environment-specific secrets

3. **"Build failed"**
   - Run `npm run build` locally to reproduce
   - Check TypeScript errors with `npm run type-check`
   - Verify all dependencies are installed

4. **"Deployment succeeded but app doesn't work"**
   - Check runtime logs with `wrangler tail`
   - Verify environment variables are correct
   - Test locally with `npm run dev`

### Getting Help

1. Check workflow run logs in GitHub Actions
2. Review Cloudflare Workers logs
3. Run diagnostics locally
4. Check [Cloudflare Workers Discord](https://discord.gg/cloudflaredev)

## Security Best Practices

1. **Never commit secrets** to the repository
2. **Rotate API keys** regularly (every 90 days)
3. **Use environment-specific secrets** for staging/production
4. **Limit token permissions** to minimum required
5. **Enable 2FA** on GitHub and Cloudflare accounts
6. **Review deployment logs** for sensitive data leaks
7. **Use branch protection** to prevent direct pushes to main

## Additional Resources

- [Cloudflare Workers Documentation](https://developers.cloudflare.com/workers/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Wrangler CLI Documentation](https://developers.cloudflare.com/workers/wrangler/)
- [Cloudflare Wrangler Action](https://github.com/cloudflare/wrangler-action)