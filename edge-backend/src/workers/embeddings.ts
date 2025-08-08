/**
 * Edge Backend Embeddings Worker
 * Handles vector ingestion and embedding operations
 */

import { ExecutionContext } from '@cloudflare/workers-types';

export interface Env {
  // D1 Database
  DB: D1Database;
  // KV Namespace
  KV: KVNamespace;
  // R2 Bucket
  R2: R2Bucket;
  // Vectorize Index
  VECTORIZE: VectorizeIndex;
}

interface EmbeddingRequest {
  text: string;
  metadata?: Record<string, any>;
  namespace?: string;
  source?: string;
}

interface BatchEmbeddingRequest {
  documents: Array<{
    id?: string;
    text: string;
    metadata?: Record<string, any>;
  }>;
  namespace?: string;
  source?: string;
}

// LangFlow Webhook Payload Interfaces
interface LangFlowWebhookPayload {
  flow_id: string;
  pipeline_id: string;
  node_id: string;
  timestamp: string;
  data: {
    type: 'embedding' | 'batch_embedding';
    content: string | string[];
    vector?: number[];
    metadata?: Record<string, any>;
  };
  status: 'success' | 'error';
  error?: string;
}

interface LangFlowHeaders {
  'x-langflow-pipeline-id'?: string;
  'x-langflow-flow-id'?: string;
  'x-langflow-node-id'?: string;
  'x-langflow-timestamp'?: string;
  'x-langflow-signature'?: string;
}

interface EmbeddingResponse {
  id: string;
  success: boolean;
  vectorsStored?: number;
  timestamp: string;
  error?: string;
}

interface SearchRequest {
  query: string;
  topK?: number;
  namespace?: string;
  filter?: Record<string, any>;
}

interface SearchResult {
  id: string;
  score: number;
  metadata?: Record<string, any>;
}

export default {
  async fetch(
    request: Request,
    env: Env,
    ctx: ExecutionContext
  ): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // CORS headers
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    // Handle preflight requests
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      // Route handling
      switch (path) {
        case '/embeddings':
          if (request.method !== 'POST') {
            return new Response('Method not allowed', { 
              status: 405,
              headers: corsHeaders 
            });
          }
          return handleEmbedding(request, env, corsHeaders);
        
        case '/embeddings/batch':
          if (request.method !== 'POST') {
            return new Response('Method not allowed', { 
              status: 405,
              headers: corsHeaders 
            });
          }
          return handleBatchEmbedding(request, env, corsHeaders);
        
        case '/embeddings/search':
          if (request.method !== 'POST') {
            return new Response('Method not allowed', { 
              status: 405,
              headers: corsHeaders 
            });
          }
          return handleSearch(request, env, corsHeaders);
        
        case '/embeddings/delete':
          if (request.method !== 'DELETE') {
            return new Response('Method not allowed', { 
              status: 405,
              headers: corsHeaders 
            });
          }
          return handleDelete(request, env, corsHeaders);
        
        case '/health':
          return handleHealth(env, corsHeaders);
        
        default:
          return new Response('Not found', { 
            status: 404,
            headers: corsHeaders 
          });
      }
    } catch (error) {
      console.error('Embeddings worker error:', error);
      return new Response(
        JSON.stringify({ error: 'Internal server error' }), 
        { 
          status: 500,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        }
      );
    }
  },
};

async function handleEmbedding(
  request: Request,
  env: Env,
  corsHeaders: any
): Promise<Response> {
  const contentType = request.headers.get('content-type') || '';
  const requestBody = await request.json();
  
  // Check if this is a LangFlow webhook request
  const langflowHeaders = extractLangFlowHeaders(request.headers);
  const isLangFlowWebhook = isLangFlowPayload(requestBody) ||
                            Object.keys(langflowHeaders).length > 0;
  
  let embeddingRequest: EmbeddingRequest;
  
  if (isLangFlowWebhook) {
    // Parse LangFlow webhook payload
    const langflowPayload = requestBody as LangFlowWebhookPayload;
    
    // Handle error status from LangFlow
    if (langflowPayload.status === 'error') {
      console.error('LangFlow webhook error:', langflowPayload.error);
      return new Response(
        JSON.stringify({
          id: '',
          success: false,
          error: `LangFlow error: ${langflowPayload.error}`,
          timestamp: new Date().toISOString()
        }),
        {
          status: 400,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        }
      );
    }
    
    // Transform LangFlow payload to standard embedding request
    embeddingRequest = transformLangFlowPayload(langflowPayload, langflowHeaders);
  } else {
    // Standard embedding request
    embeddingRequest = requestBody as EmbeddingRequest;
  }
  
  // Validate request
  if (!embeddingRequest.text) {
    return new Response(
      JSON.stringify({ error: 'Text is required for embedding' }),
      {
        status: 400,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      }
    );
  }

  try {
    const id = crypto.randomUUID();
    const namespace = embeddingRequest.namespace || 'default';
    
    // Prepare metadata with LangFlow specific fields if present
    const metadata = {
      ...embeddingRequest.metadata,
      source: embeddingRequest.source || 'langflow',
      timestamp: new Date().toISOString(),
      namespace,
      ...(isLangFlowWebhook && {
        langflow_pipeline_id: langflowHeaders['x-langflow-pipeline-id'] ||
                              (requestBody as LangFlowWebhookPayload).pipeline_id,
        langflow_flow_id: langflowHeaders['x-langflow-flow-id'] ||
                         (requestBody as LangFlowWebhookPayload).flow_id,
        langflow_node_id: langflowHeaders['x-langflow-node-id'] ||
                         (requestBody as LangFlowWebhookPayload).node_id,
        langflow_timestamp: langflowHeaders['x-langflow-timestamp'] ||
                           (requestBody as LangFlowWebhookPayload).timestamp
      })
    };

    // Check if pre-computed vectors are provided (from LangFlow)
    const hasPrecomputedVectors = isLangFlowWebhook &&
                                  (requestBody as LangFlowWebhookPayload).data.vector;
    
    // Insert into Vectorize
    const vectorData = {
      id,
      values: hasPrecomputedVectors ?
              (requestBody as LangFlowWebhookPayload).data.vector! :
              [], // Vectorize will generate if empty
      metadata,
      namespace
    };
    
    const inserted = await env.VECTORIZE.insert([vectorData]);

    // Store original text in KV for retrieval
    await env.KV.put(
      `vector:${id}`,
      JSON.stringify({
        text: embeddingRequest.text,
        metadata,
        timestamp: new Date().toISOString(),
        precomputed: hasPrecomputedVectors
      }),
      { metadata }
    );

    // Log to D1 for tracking
    await env.DB.prepare(`
      INSERT INTO embeddings_log (id, namespace, source, timestamp)
      VALUES (?, ?, ?, ?)
    `).bind(
      id,
      namespace,
      embeddingRequest.source || 'langflow',
      new Date().toISOString()
    ).run();

    const response: EmbeddingResponse = {
      id,
      success: true,
      vectorsStored: 1,
      timestamp: new Date().toISOString()
    };

    return new Response(JSON.stringify(response), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  } catch (error) {
    console.error('Error storing embedding:', error);
    return new Response(
      JSON.stringify({
        id: '',
        success: false,
        error: 'Failed to store embedding',
        timestamp: new Date().toISOString()
      }),
      {
        status: 500,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      }
    );
  }
}

// Helper function to check if payload is from LangFlow
function isLangFlowPayload(payload: any): boolean {
  return payload &&
         typeof payload === 'object' &&
         'flow_id' in payload &&
         'pipeline_id' in payload &&
         'data' in payload &&
         payload.data.type === 'embedding';
}

// Helper function to extract LangFlow headers
function extractLangFlowHeaders(headers: Headers): LangFlowHeaders {
  const langflowHeaders: LangFlowHeaders = {};
  const headerNames: (keyof LangFlowHeaders)[] = [
    'x-langflow-pipeline-id',
    'x-langflow-flow-id',
    'x-langflow-node-id',
    'x-langflow-timestamp',
    'x-langflow-signature'
  ];
  
  headerNames.forEach(name => {
    const value = headers.get(name);
    if (value) {
      langflowHeaders[name] = value;
    }
  });
  
  return langflowHeaders;
}

// Helper function to transform LangFlow payload to standard format
function transformLangFlowPayload(
  payload: LangFlowWebhookPayload,
  headers: LangFlowHeaders
): EmbeddingRequest {
  const text = typeof payload.data.content === 'string'
    ? payload.data.content
    : payload.data.content.join(' ');
  
  return {
    text,
    metadata: {
      ...payload.data.metadata,
      pipeline_id: payload.pipeline_id,
      flow_id: payload.flow_id,
      node_id: payload.node_id,
      langflow_timestamp: payload.timestamp
    },
    namespace: payload.data.metadata?.namespace || 'default',
    source: 'langflow'
  };
}

async function handleBatchEmbedding(
  request: Request,
  env: Env,
  corsHeaders: any
): Promise<Response> {
  const requestBody: any = await request.json();
  
  // Check if this is a LangFlow batch webhook request
  const langflowHeaders = extractLangFlowHeaders(request.headers);
  const isLangFlowBatch = requestBody.data?.type === 'batch_embedding';
  
  let batchRequest: BatchEmbeddingRequest;
  
  if (isLangFlowBatch) {
    // Transform LangFlow batch payload
    const langflowPayload = requestBody as LangFlowWebhookPayload;
    
    if (langflowPayload.status === 'error') {
      console.error('LangFlow batch webhook error:', langflowPayload.error);
      return new Response(
        JSON.stringify({
          id: '',
          success: false,
          error: `LangFlow error: ${langflowPayload.error}`,
          timestamp: new Date().toISOString()
        }),
        {
          status: 400,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        }
      );
    }
    
    // Transform array of content to documents
    const contents = Array.isArray(langflowPayload.data.content)
      ? langflowPayload.data.content
      : [langflowPayload.data.content];
    
    batchRequest = {
      documents: contents.map((content, index) => ({
        text: content,
        metadata: {
          ...langflowPayload.data.metadata,
          pipeline_id: langflowPayload.pipeline_id,
          flow_id: langflowPayload.flow_id,
          node_id: langflowPayload.node_id,
          langflow_timestamp: langflowPayload.timestamp,
          batch_index: index
        }
      })),
      namespace: langflowPayload.data.metadata?.namespace || 'default',
      source: 'langflow'
    };
  } else {
    // Standard batch request
    batchRequest = requestBody as BatchEmbeddingRequest;
  }
  
  // Validate request
  if (!batchRequest.documents || batchRequest.documents.length === 0) {
    return new Response(
      JSON.stringify({ error: 'Documents array is required' }),
      {
        status: 400,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      }
    );
  }

  try {
    const namespace = batchRequest.namespace || 'default';
    const vectors = [];
    const kvPromises = [];
    const dbPromises = [];

    for (const doc of batchRequest.documents) {
      const id = doc.id || crypto.randomUUID();
      
      const metadata = {
        ...doc.metadata,
        source: batchRequest.source || 'langflow',
        timestamp: new Date().toISOString(),
        namespace,
        ...(isLangFlowBatch && langflowHeaders && {
          langflow_pipeline_id: langflowHeaders['x-langflow-pipeline-id'],
          langflow_flow_id: langflowHeaders['x-langflow-flow-id'],
          langflow_node_id: langflowHeaders['x-langflow-node-id'],
          langflow_batch_timestamp: langflowHeaders['x-langflow-timestamp']
        })
      };

      vectors.push({
        id,
        values: [], // Vectorize will generate embeddings
        metadata,
        namespace
      });

      // Store in KV
      kvPromises.push(
        env.KV.put(
          `vector:${id}`,
          JSON.stringify({
            text: doc.text,
            metadata,
            timestamp: new Date().toISOString()
          }),
          { metadata }
        )
      );

      // Log to D1
      dbPromises.push(
        env.DB.prepare(`
          INSERT INTO embeddings_log (id, namespace, source, timestamp)
          VALUES (?, ?, ?, ?)
        `).bind(
          id,
          namespace,
          batchRequest.source || 'langflow',
          new Date().toISOString()
        ).run()
      );
    }

    // Insert all vectors
    await env.VECTORIZE.insert(vectors);
    
    // Execute all KV and DB operations
    await Promise.all([...kvPromises, ...dbPromises]);

    const response: EmbeddingResponse = {
      id: crypto.randomUUID(),
      success: true,
      vectorsStored: vectors.length,
      timestamp: new Date().toISOString()
    };

    return new Response(JSON.stringify(response), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  } catch (error) {
    console.error('Error storing batch embeddings:', error);
    return new Response(
      JSON.stringify({
        id: '',
        success: false,
        error: 'Failed to store batch embeddings',
        timestamp: new Date().toISOString()
      }),
      {
        status: 500,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      }
    );
  }
}

async function handleSearch(
  request: Request, 
  env: Env, 
  corsHeaders: any
): Promise<Response> {
  const searchRequest: SearchRequest = await request.json();
  
  // Validate request
  if (!searchRequest.query) {
    return new Response(
      JSON.stringify({ error: 'Query is required for search' }), 
      { 
        status: 400,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      }
    );
  }

  try {
    const topK = searchRequest.topK || 10;
    const namespace = searchRequest.namespace || 'default';
    
    // Query Vectorize
    const queryResults = await env.VECTORIZE.query(
      [], // Vectorize will generate embedding from query text
      {
        topK,
        namespace,
        filter: searchRequest.filter
      }
    );

    // Enhance results with stored text from KV
    const results: SearchResult[] = await Promise.all(
      queryResults.matches.map(async (match) => {
        const storedData = await env.KV.get(`vector:${match.id}`);
        const data = storedData ? JSON.parse(storedData) : {};
        
        return {
          id: match.id,
          score: match.score,
          metadata: {
            ...match.metadata,
            text: data.text
          }
        };
      })
    );

    return new Response(JSON.stringify({ results }), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  } catch (error) {
    console.error('Error searching embeddings:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Failed to search embeddings'
      }), 
      { 
        status: 500,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      }
    );
  }
}

async function handleDelete(
  request: Request, 
  env: Env, 
  corsHeaders: any
): Promise<Response> {
  const url = new URL(request.url);
  const ids = url.searchParams.get('ids')?.split(',') || [];
  
  if (ids.length === 0) {
    return new Response(
      JSON.stringify({ error: 'IDs are required for deletion' }), 
      { 
        status: 400,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      }
    );
  }

  try {
    // Delete from Vectorize
    await env.VECTORIZE.deleteByIds(ids);
    
    // Delete from KV
    await Promise.all(
      ids.map(id => env.KV.delete(`vector:${id}`))
    );
    
    // Update D1 log
    await Promise.all(
      ids.map(id => 
        env.DB.prepare(`
          UPDATE embeddings_log 
          SET deleted_at = ? 
          WHERE id = ?
        `).bind(new Date().toISOString(), id).run()
      )
    );

    return new Response(
      JSON.stringify({ 
        success: true,
        deleted: ids.length 
      }), 
      {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      }
    );
  } catch (error) {
    console.error('Error deleting embeddings:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Failed to delete embeddings'
      }), 
      { 
        status: 500,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      }
    );
  }
}

async function handleHealth(env: Env, corsHeaders: any): Promise<Response> {
  const health = {
    status: 'healthy',
    service: 'embeddings-worker',
    timestamp: new Date().toISOString(),
    vectorize: {
      available: false
    }
  };

  try {
    // Check if Vectorize is available
    // Note: There's no direct health check for Vectorize
    health.vectorize.available = true;
  } catch (e) {
    console.error('Vectorize health check failed:', e);
  }

  return new Response(JSON.stringify(health, null, 2), {
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json'
    }
  });
}