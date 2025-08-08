-- ===============================================================================
-- MyCodeAssistant Edge Backend - Initial Schema Migration
-- ===============================================================================
-- Description: Creates the base tables for the edge backend system
-- Database: Cloudflare D1 (SQLite-compatible)
-- Version: 001
-- Date: 2024-12-01
-- ===============================================================================

-- Enable foreign key constraints (D1 supports this)
PRAGMA foreign_keys = ON;

-- ===============================================================================
-- Conversations Table
-- ===============================================================================
-- Stores conversation sessions between users and the AI assistant
CREATE TABLE IF NOT EXISTS conversations (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    user_id TEXT NOT NULL,
    title TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    metadata TEXT, -- JSON string for flexible metadata storage
    is_archived BOOLEAN DEFAULT 0,
    
    -- Indexes for common queries
    INDEX idx_conversations_user_id (user_id),
    INDEX idx_conversations_created_at (created_at),
    INDEX idx_conversations_updated_at (updated_at)
);

-- ===============================================================================
-- Messages Table
-- ===============================================================================
-- Stores individual messages within conversations
CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    conversation_id TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system', 'function')),
    content TEXT NOT NULL,
    model TEXT, -- Track which model was used for assistant messages
    tokens_used INTEGER, -- Token count for the message
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    metadata TEXT, -- JSON string for additional message metadata
    parent_message_id TEXT, -- For branching conversations
    is_deleted BOOLEAN DEFAULT 0,
    
    -- Foreign key constraint
    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
    FOREIGN KEY (parent_message_id) REFERENCES messages(id) ON DELETE SET NULL,
    
    -- Indexes for performance
    INDEX idx_messages_conversation_id (conversation_id),
    INDEX idx_messages_created_at (created_at),
    INDEX idx_messages_role (role)
);

-- ===============================================================================
-- Embeddings Metadata Table
-- ===============================================================================
-- Tracks embeddings stored in Vectorize with their metadata
CREATE TABLE IF NOT EXISTS embeddings_metadata (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    vector_id TEXT UNIQUE NOT NULL, -- ID in Vectorize index
    conversation_id TEXT, -- Optional link to conversation
    message_id TEXT, -- Optional link to specific message
    source TEXT NOT NULL, -- Source of the embedding (e.g., 'langflow', 'api', 'system')
    pipeline_id TEXT, -- LangFlow pipeline ID if applicable
    content_hash TEXT, -- SHA-256 hash of the original content
    content_preview TEXT, -- First 200 chars of original content
    dimensions INTEGER DEFAULT 1536, -- Vector dimensions
    model TEXT, -- Embedding model used
    namespace TEXT, -- Vectorize namespace
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    metadata TEXT, -- JSON string for flexible metadata
    
    -- Foreign key constraints
    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE SET NULL,
    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE SET NULL,
    
    -- Indexes
    INDEX idx_embeddings_vector_id (vector_id),
    INDEX idx_embeddings_conversation_id (conversation_id),
    INDEX idx_embeddings_source (source),
    INDEX idx_embeddings_pipeline_id (pipeline_id),
    INDEX idx_embeddings_created_at (created_at)
);

-- ===============================================================================
-- API Keys Table (Optional - for API key management)
-- ===============================================================================
-- Manages API keys for accessing the edge backend
CREATE TABLE IF NOT EXISTS api_keys (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    key_hash TEXT UNIQUE NOT NULL, -- SHA-256 hash of the API key
    name TEXT NOT NULL,
    user_id TEXT,
    permissions TEXT, -- JSON array of permissions
    rate_limit INTEGER DEFAULT 100, -- Requests per minute
    expires_at DATETIME,
    last_used_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT 1,
    
    -- Indexes
    INDEX idx_api_keys_key_hash (key_hash),
    INDEX idx_api_keys_user_id (user_id),
    INDEX idx_api_keys_expires_at (expires_at)
);

-- ===============================================================================
-- Usage Tracking Table
-- ===============================================================================
-- Tracks API usage for monitoring and billing
CREATE TABLE IF NOT EXISTS usage_tracking (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    user_id TEXT,
    api_key_id TEXT,
    endpoint TEXT NOT NULL,
    method TEXT NOT NULL,
    status_code INTEGER,
    tokens_used INTEGER,
    response_time_ms INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    metadata TEXT, -- JSON for additional tracking data
    
    -- Foreign key
    FOREIGN KEY (api_key_id) REFERENCES api_keys(id) ON DELETE SET NULL,
    
    -- Indexes
    INDEX idx_usage_user_id (user_id),
    INDEX idx_usage_api_key_id (api_key_id),
    INDEX idx_usage_created_at (created_at),
    INDEX idx_usage_endpoint (endpoint)
);

-- ===============================================================================
-- Pipeline Configurations Table
-- ===============================================================================
-- Stores LangFlow pipeline configurations and mappings
CREATE TABLE IF NOT EXISTS pipeline_configs (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    pipeline_id TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    webhook_url TEXT,
    webhook_secret_hash TEXT, -- Hash of webhook secret for validation
    config TEXT NOT NULL, -- JSON configuration
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    
    -- Indexes
    INDEX idx_pipeline_configs_pipeline_id (pipeline_id),
    INDEX idx_pipeline_configs_is_active (is_active)
);

-- ===============================================================================
-- Create update triggers for updated_at columns
-- ===============================================================================
-- Note: D1 supports triggers but syntax might vary

CREATE TRIGGER IF NOT EXISTS update_conversations_updated_at
AFTER UPDATE ON conversations
FOR EACH ROW
BEGIN
    UPDATE conversations SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS update_pipeline_configs_updated_at
AFTER UPDATE ON pipeline_configs
FOR EACH ROW
BEGIN
    UPDATE pipeline_configs SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- ===============================================================================
-- Initial seed data (optional)
-- ===============================================================================

-- Insert system pipeline configuration
INSERT OR IGNORE INTO pipeline_configs (
    pipeline_id,
    name,
    description,
    config,
    is_active
) VALUES (
    'system-default',
    'System Default Pipeline',
    'Default pipeline configuration for system operations',
    '{"type": "system", "version": "1.0.0"}',
    1
);

-- ===============================================================================
-- Migration completion marker
-- ===============================================================================
INSERT INTO _migrations (version, name, applied_at) 
VALUES (1, '001_initial_schema', CURRENT_TIMESTAMP);