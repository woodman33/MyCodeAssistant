-- ===============================================================================
-- MyCodeAssistant Edge Backend - Performance Indexes Migration
-- ===============================================================================
-- Description: Creates additional indexes for query performance optimization
-- Database: Cloudflare D1 (SQLite-compatible)
-- Version: 002
-- Date: 2024-12-01
-- ===============================================================================

-- ===============================================================================
-- Composite Indexes for Common Query Patterns
-- ===============================================================================

-- Conversations: User's recent conversations
CREATE INDEX IF NOT EXISTS idx_conversations_user_recent 
ON conversations(user_id, updated_at DESC) 
WHERE is_archived = 0;

-- Messages: Recent messages in a conversation
CREATE INDEX IF NOT EXISTS idx_messages_conversation_recent 
ON messages(conversation_id, created_at DESC) 
WHERE is_deleted = 0;

-- Messages: Full-text search preparation (if FTS is needed later)
CREATE INDEX IF NOT EXISTS idx_messages_content_search 
ON messages(conversation_id, content) 
WHERE is_deleted = 0;

-- ===============================================================================
-- Embeddings Performance Indexes
-- ===============================================================================

-- Embeddings: Quick lookup by source and timestamp
CREATE INDEX IF NOT EXISTS idx_embeddings_source_time 
ON embeddings_metadata(source, created_at DESC);

-- Embeddings: Pipeline-specific queries
CREATE INDEX IF NOT EXISTS idx_embeddings_pipeline_time 
ON embeddings_metadata(pipeline_id, created_at DESC) 
WHERE pipeline_id IS NOT NULL;

-- Embeddings: Content hash for duplicate detection
CREATE INDEX IF NOT EXISTS idx_embeddings_content_hash 
ON embeddings_metadata(content_hash);

-- Embeddings: Namespace grouping
CREATE INDEX IF NOT EXISTS idx_embeddings_namespace 
ON embeddings_metadata(namespace, created_at DESC) 
WHERE namespace IS NOT NULL;

-- ===============================================================================
-- API Keys and Usage Tracking Indexes
-- ===============================================================================

-- API Keys: Active keys lookup
CREATE INDEX IF NOT EXISTS idx_api_keys_active 
ON api_keys(is_active, expires_at) 
WHERE is_active = 1;

-- Usage Tracking: Daily aggregation queries
CREATE INDEX IF NOT EXISTS idx_usage_daily 
ON usage_tracking(user_id, date(created_at), endpoint);

-- Usage Tracking: API key usage patterns
CREATE INDEX IF NOT EXISTS idx_usage_api_pattern 
ON usage_tracking(api_key_id, endpoint, created_at DESC) 
WHERE api_key_id IS NOT NULL;

-- Usage Tracking: Error monitoring
CREATE INDEX IF NOT EXISTS idx_usage_errors 
ON usage_tracking(status_code, created_at DESC) 
WHERE status_code >= 400;

-- ===============================================================================
-- Pipeline Configuration Indexes
-- ===============================================================================

-- Active pipelines quick lookup
CREATE INDEX IF NOT EXISTS idx_pipelines_active 
ON pipeline_configs(is_active, pipeline_id) 
WHERE is_active = 1;

-- ===============================================================================
-- Statistics and Monitoring Support
-- ===============================================================================

-- Messages: Token usage statistics
CREATE INDEX IF NOT EXISTS idx_messages_tokens 
ON messages(conversation_id, tokens_used) 
WHERE tokens_used IS NOT NULL;

-- Messages: Model usage tracking
CREATE INDEX IF NOT EXISTS idx_messages_model 
ON messages(model, created_at DESC) 
WHERE model IS NOT NULL;

-- Usage: Response time monitoring
CREATE INDEX IF NOT EXISTS idx_usage_performance 
ON usage_tracking(endpoint, response_time_ms) 
WHERE response_time_ms IS NOT NULL;

-- ===============================================================================
-- Partial Indexes for Special Queries
-- ===============================================================================

-- Conversations: Non-archived with activity
CREATE INDEX IF NOT EXISTS idx_conversations_active 
ON conversations(updated_at DESC) 
WHERE is_archived = 0;

-- Messages: System messages only
CREATE INDEX IF NOT EXISTS idx_messages_system 
ON messages(conversation_id, created_at) 
WHERE role = 'system';

-- Messages: Function calls tracking
CREATE INDEX IF NOT EXISTS idx_messages_functions 
ON messages(conversation_id, created_at) 
WHERE role = 'function';

-- API Keys: Expiring soon (for cleanup jobs)
CREATE INDEX IF NOT EXISTS idx_api_keys_expiring 
ON api_keys(expires_at) 
WHERE is_active = 1 AND expires_at IS NOT NULL;

-- ===============================================================================
-- Virtual Columns and Generated Indexes (if D1 supports)
-- ===============================================================================

-- Note: These may need adjustment based on D1's SQLite version
-- Uncomment if supported:

-- ALTER TABLE usage_tracking 
-- ADD COLUMN day_bucket TEXT GENERATED ALWAYS AS (date(created_at)) VIRTUAL;
-- 
-- CREATE INDEX IF NOT EXISTS idx_usage_day_bucket 
-- ON usage_tracking(day_bucket, user_id);

-- ===============================================================================
-- Analyze tables for query optimization
-- ===============================================================================

-- Update statistics for query planner
ANALYZE conversations;
ANALYZE messages;
ANALYZE embeddings_metadata;
ANALYZE api_keys;
ANALYZE usage_tracking;
ANALYZE pipeline_configs;

-- ===============================================================================
-- Migration completion marker
-- ===============================================================================
INSERT INTO _migrations (version, name, applied_at) 
VALUES (2, '002_indexes', CURRENT_TIMESTAMP);