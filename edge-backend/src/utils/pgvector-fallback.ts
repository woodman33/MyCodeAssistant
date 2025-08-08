/**
 * PGVector Fallback Utility
 * Provides Neon pgvector integration as a fallback when Vectorize is unavailable
 */

import { Pool } from '@neondatabase/serverless';

export interface VectorDocument {
  id: string;
  embedding: number[];
  metadata: Record<string, any>;
  text: string;
  created_at?: Date;
}

export interface SearchOptions {
  topK?: number;
  filter?: Record<string, any>;
  threshold?: number;
}

export class PGVectorFallback {
  private pool: Pool;
  private tableName: string;
  private dimension: number;

  constructor(
    connectionString: string,
    tableName: string = 'embeddings',
    dimension: number = 1536
  ) {
    this.pool = new Pool({ connectionString });
    this.tableName = tableName;
    this.dimension = dimension;
  }

  /**
   * Initialize the pgvector extension and create necessary tables
   */
  async initialize(): Promise<void> {
    const client = await this.pool.connect();
    
    try {
      // Enable pgvector extension
      await client.query('CREATE EXTENSION IF NOT EXISTS vector');
      
      // Create embeddings table
      await client.query(`
        CREATE TABLE IF NOT EXISTS ${this.tableName} (
          id TEXT PRIMARY KEY,
          embedding vector(${this.dimension}),
          metadata JSONB,
          text TEXT,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);
      
      // Create indexes for better performance
      await client.query(`
        CREATE INDEX IF NOT EXISTS ${this.tableName}_embedding_idx 
        ON ${this.tableName} 
        USING ivfflat (embedding vector_cosine_ops)
        WITH (lists = 100)
      `);
      
      await client.query(`
        CREATE INDEX IF NOT EXISTS ${this.tableName}_metadata_idx 
        ON ${this.tableName} 
        USING gin (metadata)
      `);
      
      await client.query(`
        CREATE INDEX IF NOT EXISTS ${this.tableName}_created_at_idx 
        ON ${this.tableName} (created_at DESC)
      `);
      
      console.log('PGVector tables and indexes initialized successfully');
    } catch (error) {
      console.error('Error initializing PGVector:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Store a single vector document
   */
  async storeVector(document: VectorDocument): Promise<void> {
    const client = await this.pool.connect();
    
    try {
      const query = `
        INSERT INTO ${this.tableName} (id, embedding, metadata, text)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (id) 
        DO UPDATE SET 
          embedding = EXCLUDED.embedding,
          metadata = EXCLUDED.metadata,
          text = EXCLUDED.text,
          updated_at = CURRENT_TIMESTAMP
      `;
      
      await client.query(query, [
        document.id,
        JSON.stringify(document.embedding),
        document.metadata,
        document.text
      ]);
      
      console.log(`Vector stored successfully: ${document.id}`);
    } catch (error) {
      console.error('Error storing vector:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Store multiple vector documents in batch
   */
  async storeBatch(documents: VectorDocument[]): Promise<void> {
    const client = await this.pool.connect();
    
    try {
      await client.query('BEGIN');
      
      const query = `
        INSERT INTO ${this.tableName} (id, embedding, metadata, text)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (id) 
        DO UPDATE SET 
          embedding = EXCLUDED.embedding,
          metadata = EXCLUDED.metadata,
          text = EXCLUDED.text,
          updated_at = CURRENT_TIMESTAMP
      `;
      
      for (const doc of documents) {
        await client.query(query, [
          doc.id,
          JSON.stringify(doc.embedding),
          doc.metadata,
          doc.text
        ]);
      }
      
      await client.query('COMMIT');
      console.log(`Batch of ${documents.length} vectors stored successfully`);
    } catch (error) {
      await client.query('ROLLBACK');
      console.error('Error storing batch vectors:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Search for similar vectors using cosine similarity
   */
  async search(
    queryEmbedding: number[],
    options: SearchOptions = {}
  ): Promise<Array<VectorDocument & { similarity: number }>> {
    const client = await this.pool.connect();
    
    try {
      const topK = options.topK || 10;
      const threshold = options.threshold || 0.0;
      
      let whereClause = `1 - (embedding <=> $1::vector) >= ${threshold}`;
      const params: any[] = [JSON.stringify(queryEmbedding)];
      
      // Add metadata filters if provided
      if (options.filter && Object.keys(options.filter).length > 0) {
        const filterConditions = Object.entries(options.filter).map(
          ([key, value], index) => {
            params.push(value);
            return `metadata->>'${key}' = $${params.length}`;
          }
        );
        whereClause += ` AND ${filterConditions.join(' AND ')}`;
      }
      
      const query = `
        SELECT 
          id,
          embedding,
          metadata,
          text,
          created_at,
          1 - (embedding <=> $1::vector) as similarity
        FROM ${this.tableName}
        WHERE ${whereClause}
        ORDER BY embedding <=> $1::vector
        LIMIT ${topK}
      `;
      
      const result = await client.query(query, params);
      
      return result.rows.map(row => ({
        id: row.id,
        embedding: row.embedding,
        metadata: row.metadata,
        text: row.text,
        created_at: row.created_at,
        similarity: row.similarity
      }));
    } catch (error) {
      console.error('Error searching vectors:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Retrieve a vector by ID
   */
  async getVector(id: string): Promise<VectorDocument | null> {
    const client = await this.pool.connect();
    
    try {
      const query = `
        SELECT id, embedding, metadata, text, created_at
        FROM ${this.tableName}
        WHERE id = $1
      `;
      
      const result = await client.query(query, [id]);
      
      if (result.rows.length === 0) {
        return null;
      }
      
      const row = result.rows[0];
      return {
        id: row.id,
        embedding: row.embedding,
        metadata: row.metadata,
        text: row.text,
        created_at: row.created_at
      };
    } catch (error) {
      console.error('Error retrieving vector:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Delete vectors by IDs
   */
  async deleteVectors(ids: string[]): Promise<number> {
    const client = await this.pool.connect();
    
    try {
      const query = `
        DELETE FROM ${this.tableName}
        WHERE id = ANY($1::text[])
      `;
      
      const result = await client.query(query, [ids]);
      console.log(`Deleted ${result.rowCount} vectors`);
      return result.rowCount || 0;
    } catch (error) {
      console.error('Error deleting vectors:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Update vector metadata
   */
  async updateMetadata(
    id: string,
    metadata: Record<string, any>
  ): Promise<void> {
    const client = await this.pool.connect();
    
    try {
      const query = `
        UPDATE ${this.tableName}
        SET 
          metadata = metadata || $2::jsonb,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = $1
      `;
      
      await client.query(query, [id, metadata]);
      console.log(`Metadata updated for vector: ${id}`);
    } catch (error) {
      console.error('Error updating metadata:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Get statistics about the vector store
   */
  async getStats(): Promise<{
    totalVectors: number;
    tableSizeBytes: number;
    indexSizeBytes: number;
    oldestVector: Date | null;
    newestVector: Date | null;
  }> {
    const client = await this.pool.connect();
    
    try {
      // Get total count
      const countResult = await client.query(
        `SELECT COUNT(*) as count FROM ${this.tableName}`
      );
      
      // Get date range
      const dateResult = await client.query(`
        SELECT 
          MIN(created_at) as oldest,
          MAX(created_at) as newest
        FROM ${this.tableName}
      `);
      
      // Get table size
      const sizeResult = await client.query(`
        SELECT 
          pg_total_relation_size('${this.tableName}') as total_size,
          pg_relation_size('${this.tableName}') as table_size,
          pg_indexes_size('${this.tableName}') as index_size
      `);
      
      return {
        totalVectors: parseInt(countResult.rows[0].count),
        tableSizeBytes: parseInt(sizeResult.rows[0].table_size),
        indexSizeBytes: parseInt(sizeResult.rows[0].index_size),
        oldestVector: dateResult.rows[0].oldest,
        newestVector: dateResult.rows[0].newest
      };
    } catch (error) {
      console.error('Error getting stats:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Clean up old vectors based on age
   */
  async cleanupOldVectors(daysOld: number): Promise<number> {
    const client = await this.pool.connect();
    
    try {
      const query = `
        DELETE FROM ${this.tableName}
        WHERE created_at < NOW() - INTERVAL '${daysOld} days'
      `;
      
      const result = await client.query(query);
      console.log(`Cleaned up ${result.rowCount} old vectors`);
      return result.rowCount || 0;
    } catch (error) {
      console.error('Error cleaning up old vectors:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Close the connection pool
   */
  async close(): Promise<void> {
    await this.pool.end();
  }
}

/**
 * Factory function to create a PGVectorFallback instance with environment configuration
 */
export function createPGVectorFallback(
  connectionString?: string,
  tableName?: string,
  dimension?: number
): PGVectorFallback {
  const connString = connectionString || process.env.NEON_DATABASE_URL;
  
  if (!connString) {
    throw new Error(
      'Neon connection string is required. Please provide it or set NEON_DATABASE_URL environment variable.'
    );
  }
  
  return new PGVectorFallback(
    connString,
    tableName || 'embeddings',
    dimension || 1536
  );
}

/**
 * Helper function to generate embeddings using an external API
 * This is a placeholder - implement with actual embedding service
 */
export async function generateEmbedding(
  text: string,
  apiKey?: string
): Promise<number[]> {
  // TODO: Implement actual embedding generation
  // This could use OpenAI, Cohere, or another embedding API
  console.warn('generateEmbedding is a placeholder - implement with actual service');
  
  // Return a mock embedding for now
  return Array(1536).fill(0).map(() => Math.random());
}

/**
 * Utility to check if pgvector is available
 */
export async function checkPGVectorAvailability(
  connectionString: string
): Promise<boolean> {
  const pool = new Pool({ connectionString });
  const client = await pool.connect();
  
  try {
    const result = await client.query(`
      SELECT EXISTS (
        SELECT 1 
        FROM pg_extension 
        WHERE extname = 'vector'
      ) as vector_available
    `);
    
    return result.rows[0].vector_available;
  } catch (error) {
    console.error('Error checking pgvector availability:', error);
    return false;
  } finally {
    client.release();
    await pool.end();
  }
}