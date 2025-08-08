# MyCodeAssistant Edge Backend Setup Guide

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Database Configuration](#database-configuration)
4. [Secrets Management](#secrets-management)
5. [Local Development](#local-development)
6. [Deployment](#deployment)
7. [Troubleshooting](#troubleshooting)
8. [Architecture Overview](#architecture-overview)

## Prerequisites

### Required Tools

- **Node.js**: Version 18.0.0 or higher
- **npm**: Version 10.0.0 or higher
- **Wrangler CLI**: Install with `npm install -g wrangler`
- **Git**: For version control

### Cloudflare Account Setup

1. Create a Cloudflare account at [dash.cloudflare.com](https://dash.cloudflare.com)
2. Note your Account ID: `091c9e59ca0fc3bea9f9d432fa12a3b1`
3. Enable the following services:
   - Workers & Pages
   - D1 Database
   - R2 Storage
   - KV Storage
   - Vectorize (Beta)

### Authentication

```bash
# Login to Cloudflare via Wrangler
wrangler login

# Verify authentication
wrangler whoami
```

## Initial Setup

### 1. Clone Repository and Install Dependencies

```bash
# Navigate to edge-backend directory
cd edge-backend

# Install dependencies
npm install

# Verify TypeScript compilation
npm run typecheck
```

### 2. Create Local Configuration Files

```bash
# Copy environment example file
cp .env.example .env

# Create dev.vars file for local Wrangler development
cat > dev.vars << 'EOF'
OPENAI_API_KEY=your_openai_key_here
OPENROUTER_API_KEY=your_openrouter_key_here
R2_ACCESS_KEY_ID=your_r2_access_key_here
R2_SECRET_ACCESS_KEY=your_r2_secret_here
GITHUB_TOKEN=your_github_token_here
LANGFLOW_WEBHOOK_SECRET=your_webhook_secret_here
EOF
```

**Important**: Add `dev.vars` to `.gitignore` to prevent committing secrets.

## Database Configuration

### 1. Create D1 Database

```bash
# Create the database
wrangler d1 create mca-db

# Output will show:
# ✅ Successfully created DB 'mca-db' in region REGION
# [[d1_databases]]
# binding = "DB"
# database_name = "mca-db"
# database_id = "xxxx-xxxx-xxxx-xxxx"
```

### 2. Update wrangler.toml

Update the `database_id` in `wrangler.toml` with the ID from the previous step:

```toml
[[d1_databases]]
binding = "DB"
database_name = "mca-db"
database_id = "YOUR_ACTUAL_DATABASE_ID_HERE"
migrations_dir = "./migrations"
```

### 3. Run Database Migrations

```bash
# Apply initial schema migration
wrangler d1 migrations apply mca-db

# List applied migrations
wrangler d1 migrations list mca-db

# Execute SQL directly (for testing)
wrangler d1 execute mca-db --command "SELECT name FROM sqlite_master WHERE type='table';"
```

## Secrets Management

### Automated Setup

```bash
# Make the setup script executable
chmod +x setup-secrets.sh

# Run the secrets setup script
./setup-secrets.sh
```

### Manual Setup

Set each secret individually:

```bash
# Required secrets
wrangler secret put OPENAI_API_KEY
wrangler secret put OPENROUTER_API_KEY
wrangler secret put R2_ACCESS_KEY_ID
wrangler secret put R2_SECRET_ACCESS_KEY
wrangler secret put GITHUB_TOKEN

# Optional secrets
wrangler secret put LANGFLOW_WEBHOOK_SECRET
wrangler secret put CLOUDFLARE_API_TOKEN

# List all secrets
wrangler secret list
```

### Environment-Specific Secrets

For staging/production environments:

```bash
# Production secrets
wrangler secret put OPENAI_API_KEY --env production

# Staging secrets
wrangler secret put OPENAI_API_KEY --env staging
```

## Local Development

### 1. Start Development Server

```bash
# Start the main API worker
npm run dev

# Or start specific workers
npm run dev:api         # API worker on port 8787
npm run dev:embeddings  # Embeddings worker
```

### 2. Testing Endpoints

```bash
# Test health check
curl http://localhost:8787/health

# Test embeddings endpoint
curl -X POST http://localhost:8787/embeddings \
  -H "Content-Type: application/json" \
  -d '{"text": "Test embedding", "metadata": {"source": "test"}}'

# Test LangFlow webhook
curl -X POST http://localhost:8787/embeddings \
  -H "Content-Type: application/json" \
  -H "X-LangFlow-Pipeline-ID: test-pipeline" \
  -d '{"text": "LangFlow test", "metadata": {"pipeline_id": "test"}}'
```

### 3. View Logs

```bash
# Tail logs for deployed workers
npm run tail

# Tail specific worker logs
npm run tail:api
npm run tail:embeddings
```

## Deployment

### 1. Pre-deployment Checks

```bash
# Run TypeScript checks
npm run typecheck

# Format code
npm run format

# Lint code
npm run lint

# Run tests
npm run test

# Dry run deployment
npm run build
```

### 2. Deploy Workers

```bash
# Deploy all workers
npm run deploy

# Deploy specific workers
npm run deploy:api
npm run deploy:embeddings

# Deploy to specific environment
wrangler deploy --env production
wrangler deploy --env staging
```

### 3. Verify Deployment

```bash
# Get worker information
wrangler deployments list

# Test production endpoints
curl https://mca-edge-worker.your-subdomain.workers.dev/health

# View real-time logs
wrangler tail mca-edge-worker
```

## Troubleshooting

### Common Issues

#### 1. Database Connection Issues

```bash
# Check database status
wrangler d1 info mca-db

# Re-run migrations
wrangler d1 migrations apply mca-db --dry-run
wrangler d1 migrations apply mca-db
```

#### 2. Secret Access Issues

```bash
# Verify secrets are set
wrangler secret list

# Re-set a specific secret
wrangler secret delete SECRET_NAME
wrangler secret put SECRET_NAME
```

#### 3. Build/Deployment Failures

```bash
# Clean and rebuild
rm -rf node_modules dist
npm install
npm run build

# Check wrangler version
wrangler --version

# Update wrangler
npm update wrangler
```

#### 4. R2 Bucket Issues

```bash
# Create R2 bucket if not exists
wrangler r2 bucket create mca-assets

# List R2 buckets
wrangler r2 bucket list
```

#### 5. KV Namespace Issues

```bash
# Create KV namespace
wrangler kv:namespace create FLAGS

# List KV namespaces
wrangler kv:namespace list
```

### Debug Mode

Enable debug logging:

```javascript
// In dev.vars
DEBUG=true
LOG_LEVEL=debug
```

## Architecture Overview

### Project Structure

```
edge-backend/
├── migrations/              # D1 database migrations
│   ├── 001_initial_schema.sql
│   └── 002_indexes.sql
├── src/
│   ├── workers/            # Worker entry points
│   │   ├── api.ts         # Main API worker
│   │   └── embeddings.ts  # Embeddings worker
│   └── utils/             # Shared utilities
│       ├── langflow-integration.ts
│       └── pgvector-fallback.ts
├── .env.example           # Environment template
├── dev.vars              # Local dev secrets (gitignored)
├── package.json          # Dependencies and scripts
├── setup-secrets.sh      # Secrets setup script
├── SETUP.md             # This file
├── tsconfig.json        # TypeScript config
└── wrangler.toml        # Cloudflare Workers config
```

### Service Bindings

- **D1 Database**: `DB` - SQLite-compatible database
- **R2 Storage**: `ASSETS` - Object storage for files
- **KV Storage**: `FLAGS` - Key-value store for feature flags
- **Vectorize**: `EMBEDDINGS` - Vector database for embeddings

### API Endpoints

#### Main API Worker
- `GET /health` - Health check
- `POST /conversations` - Create conversation
- `GET /conversations/:id` - Get conversation
- `POST /messages` - Add message
- `GET /messages/:conversationId` - Get messages

#### Embeddings Worker
- `POST /embeddings` - Create single embedding
- `POST /embeddings/batch` - Batch embedding creation
- `GET /embeddings/search` - Vector similarity search

### Environment Variables

See `.env.example` for complete list. Critical variables:

- `OPENAI_API_KEY` - OpenAI API access
- `OPENROUTER_API_KEY` - OpenRouter multi-model access
- `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` - R2 storage
- `GITHUB_TOKEN` - GitHub integration
- `LANGFLOW_WEBHOOK_SECRET` - Webhook validation

## Next Steps

1. **Set up monitoring**: Configure Cloudflare Analytics
2. **Custom domain**: Add custom domain routing
3. **CI/CD Pipeline**: Set up GitHub Actions for automated deployment
4. **Rate limiting**: Configure rate limits in wrangler.toml
5. **Backup strategy**: Implement D1 database backups

## Support

For issues or questions:

1. Check the [Cloudflare Workers documentation](https://developers.cloudflare.com/workers/)
2. Review [D1 documentation](https://developers.cloudflare.com/d1/)
3. Consult [Vectorize documentation](https://developers.cloudflare.com/vectorize/)
4. Open an issue in the GitHub repository

---

**Version**: 1.0.0  
**Last Updated**: December 2024  
**Maintained by**: MyCodeAssistant Team