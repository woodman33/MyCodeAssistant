/**
 * LangFlow Integration Utilities
 * Helper functions for integrating LangFlow with the Edge Backend
 */

import { ExecutionContext } from '@cloudflare/workers-types';

// Type definitions for LangFlow integration
export interface LangFlowConfig {
  url: string;
  apiKey?: string;
  webhookSecret?: string;
  timeout?: number;
  retryAttempts?: number;
  validateSignatures?: boolean;
}

export interface LangFlowEmbedding {
  text: string;
  vector?: number[];
  metadata?: Record<string, any>;
  model?: string;
  dimensions?: number;
}

export interface LangFlowError {
  code: string;
  message: string;
  details?: any;
  timestamp: string;
}

export interface VectorizeFormat {
  id: string;
  values: number[];
  metadata: Record<string, any>;
  namespace: string;
}

export interface LangFlowWebhookPayload {
  flow_id: string;
  pipeline_id: string;
  node_id: string;
  timestamp: string;
  data: {
    type: 'embedding' | 'batch_embedding' | 'document' | 'chunk';
    content: string | string[];
    vector?: number[];
    metadata?: Record<string, any>;
  };
  status: 'success' | 'error';
  error?: string;
}

export interface LangFlowValidationResult {
  isValid: boolean;
  errors: string[];
  warnings: string[];
}

/**
 * Validates LangFlow configuration
 */
export function validateLangFlowConfig(config: Partial<LangFlowConfig>): LangFlowValidationResult {
  const errors: string[] = [];
  const warnings: string[] = [];
  
  // Validate URL
  if (!config.url) {
    errors.push('LangFlow URL is required');
  } else {
    try {
      const url = new URL(config.url);
      if (!url.protocol.match(/^https?:$/)) {
        errors.push('LangFlow URL must use HTTP or HTTPS protocol');
      }
    } catch (e) {
      errors.push('Invalid LangFlow URL format');
    }
  }
  
  // Validate timeout
  if (config.timeout !== undefined) {
    if (config.timeout <= 0) {
      errors.push('Timeout must be a positive number');
    } else if (config.timeout > 300000) { // 5 minutes
      warnings.push('Timeout is very high (> 5 minutes)');
    }
  }
  
  // Validate retry attempts
  if (config.retryAttempts !== undefined) {
    if (config.retryAttempts < 0) {
      errors.push('Retry attempts must be non-negative');
    } else if (config.retryAttempts > 10) {
      warnings.push('High number of retry attempts may cause delays');
    }
  }
  
  // Validate webhook secret
  if (config.validateSignatures && !config.webhookSecret) {
    errors.push('Webhook secret is required when signature validation is enabled');
  }
  
  return {
    isValid: errors.length === 0,
    errors,
    warnings
  };
}

/**
 * Parses and validates LangFlow webhook payload
 */
export function parseLangFlowPayload(
  payload: any
): { valid: boolean; data?: LangFlowWebhookPayload; error?: string } {
  try {
    // Basic structure validation
    if (!payload || typeof payload !== 'object') {
      return { valid: false, error: 'Invalid payload structure' };
    }
    
    // Required fields
    const requiredFields = ['flow_id', 'pipeline_id', 'node_id', 'timestamp', 'data', 'status'];
    const missingFields = requiredFields.filter(field => !(field in payload));
    
    if (missingFields.length > 0) {
      return { 
        valid: false, 
        error: `Missing required fields: ${missingFields.join(', ')}` 
      };
    }
    
    // Validate data structure
    if (!payload.data || typeof payload.data !== 'object') {
      return { valid: false, error: 'Invalid data field structure' };
    }
    
    if (!payload.data.type || !['embedding', 'batch_embedding', 'document', 'chunk'].includes(payload.data.type)) {
      return { valid: false, error: 'Invalid or missing data type' };
    }
    
    if (!payload.data.content) {
      return { valid: false, error: 'Missing content in data' };
    }
    
    // Validate status
    if (!['success', 'error'].includes(payload.status)) {
      return { valid: false, error: 'Invalid status value' };
    }
    
    // If status is error, ensure error message exists
    if (payload.status === 'error' && !payload.error) {
      return { valid: false, error: 'Error message required when status is error' };
    }
    
    // Validate vector if present
    if (payload.data.vector && !Array.isArray(payload.data.vector)) {
      return { valid: false, error: 'Vector must be an array of numbers' };
    }
    
    if (payload.data.vector && !payload.data.vector.every((v: any) => typeof v === 'number')) {
      return { valid: false, error: 'Vector must contain only numbers' };
    }
    
    return { valid: true, data: payload as LangFlowWebhookPayload };
  } catch (error) {
    return { 
      valid: false, 
      error: `Payload parsing error: ${error instanceof Error ? error.message : 'Unknown error'}` 
    };
  }
}

/**
 * Transforms LangFlow embeddings to Vectorize format
 */
export function transformToVectorizeFormat(
  embedding: LangFlowEmbedding,
  id?: string,
  namespace?: string
): VectorizeFormat {
  const vectorId = id || crypto.randomUUID();
  const vectorNamespace = namespace || 'default';
  
  // Prepare metadata
  const metadata: Record<string, any> = {
    ...embedding.metadata,
    source: 'langflow',
    timestamp: new Date().toISOString()
  };
  
  if (embedding.model) {
    metadata.embedding_model = embedding.model;
  }
  
  if (embedding.dimensions) {
    metadata.dimensions = embedding.dimensions;
  }
  
  if (embedding.text) {
    metadata.original_text_preview = embedding.text.substring(0, 200);
  }
  
  return {
    id: vectorId,
    values: embedding.vector || [],
    metadata,
    namespace: vectorNamespace
  };
}

/**
 * Maps LangFlow errors to API error responses
 */
export function mapLangFlowError(error: any): LangFlowError {
  const timestamp = new Date().toISOString();
  
  // Connection errors
  if (error instanceof TypeError && error.message.includes('fetch')) {
    return {
      code: 'LANGFLOW_CONNECTION_ERROR',
      message: 'Failed to connect to LangFlow service',
      details: { originalError: error.message },
      timestamp
    };
  }
  
  // Timeout errors
  if (error.name === 'AbortError' || error.message?.includes('timeout')) {
    return {
      code: 'LANGFLOW_TIMEOUT',
      message: 'LangFlow request timed out',
      details: { timeout: true },
      timestamp
    };
  }
  
  // HTTP errors
  if (error.status) {
    const statusMessages: Record<number, string> = {
      400: 'Invalid request to LangFlow',
      401: 'Authentication failed with LangFlow',
      403: 'Access denied to LangFlow resource',
      404: 'LangFlow endpoint not found',
      429: 'Rate limit exceeded for LangFlow',
      500: 'LangFlow internal server error',
      502: 'LangFlow gateway error',
      503: 'LangFlow service unavailable'
    };
    
    return {
      code: `LANGFLOW_HTTP_${error.status}`,
      message: statusMessages[error.status] || `LangFlow HTTP error ${error.status}`,
      details: { status: error.status, statusText: error.statusText },
      timestamp
    };
  }
  
  // LangFlow specific errors
  if (error.flow_error) {
    return {
      code: 'LANGFLOW_FLOW_ERROR',
      message: `LangFlow flow execution error: ${error.flow_error}`,
      details: { flowId: error.flow_id, nodeId: error.node_id },
      timestamp
    };
  }
  
  // Default error
  return {
    code: 'LANGFLOW_UNKNOWN_ERROR',
    message: error.message || 'Unknown LangFlow error occurred',
    details: error,
    timestamp
  };
}

/**
 * Validates webhook signature for security
 */
export async function validateWebhookSignature(
  payload: string,
  signature: string,
  secret: string
): Promise<boolean> {
  try {
    const encoder = new TextEncoder();
    const data = encoder.encode(payload);
    const key = await crypto.subtle.importKey(
      'raw',
      encoder.encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign']
    );
    
    const signatureBuffer = await crypto.subtle.sign('HMAC', key, data);
    const signatureArray = new Uint8Array(signatureBuffer);
    const computedSignature = Array.from(signatureArray)
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');
    
    return computedSignature === signature;
  } catch (error) {
    console.error('Signature validation error:', error);
    return false;
  }
}

/**
 * Batch transforms multiple LangFlow embeddings
 */
export function batchTransformToVectorize(
  embeddings: LangFlowEmbedding[],
  namespace?: string
): VectorizeFormat[] {
  return embeddings.map(embedding => 
    transformToVectorizeFormat(embedding, undefined, namespace)
  );
}

/**
 * Extracts text content from various LangFlow data types
 */
export function extractTextContent(data: any): string | string[] {
  if (typeof data === 'string') {
    return data;
  }
  
  if (Array.isArray(data)) {
    return data.map(item => extractTextContent(item)).flat();
  }
  
  if (data && typeof data === 'object') {
    // Check for common text fields
    if (data.text) return data.text;
    if (data.content) return extractTextContent(data.content);
    if (data.document) return data.document;
    if (data.chunk) return data.chunk;
    if (data.message) return data.message;
    
    // For embedded documents
    if (data.documents) {
      return extractTextContent(data.documents);
    }
  }
  
  return '';
}

/**
 * Builds error response for LangFlow integration failures
 */
export function buildErrorResponse(
  error: LangFlowError,
  corsHeaders: Record<string, string>
): Response {
  const statusCode = error.code.includes('CONNECTION') ? 503 :
                    error.code.includes('TIMEOUT') ? 504 :
                    error.code.includes('HTTP_4') ? 400 :
                    error.code.includes('HTTP_5') ? 502 :
                    500;
  
  return new Response(
    JSON.stringify({
      success: false,
      error: error.message,
      code: error.code,
      timestamp: error.timestamp,
      details: error.details
    }),
    {
      status: statusCode,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    }
  );
}

/**
 * Sanitizes and validates embedding dimensions
 */
export function validateEmbeddingDimensions(
  vector: number[],
  expectedDimensions?: number
): { valid: boolean; error?: string } {
  if (!Array.isArray(vector)) {
    return { valid: false, error: 'Vector must be an array' };
  }
  
  if (vector.length === 0) {
    return { valid: false, error: 'Vector cannot be empty' };
  }
  
  if (!vector.every(v => typeof v === 'number' && !isNaN(v))) {
    return { valid: false, error: 'Vector must contain only valid numbers' };
  }
  
  if (expectedDimensions && vector.length !== expectedDimensions) {
    return { 
      valid: false, 
      error: `Vector dimensions mismatch. Expected ${expectedDimensions}, got ${vector.length}` 
    };
  }
  
  // Check for reasonable dimensions (common embedding models)
  const commonDimensions = [128, 256, 384, 512, 768, 1024, 1536, 2048, 3072, 4096];
  if (!commonDimensions.includes(vector.length)) {
    console.warn(`Unusual vector dimensions: ${vector.length}`);
  }
  
  return { valid: true };
}

/**
 * Creates a retry mechanism for LangFlow requests
 */
export async function retryLangFlowRequest<T>(
  requestFn: () => Promise<T>,
  maxAttempts: number = 3,
  delayMs: number = 1000
): Promise<T> {
  let lastError: any;
  
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await requestFn();
    } catch (error) {
      lastError = error;
      
      // Don't retry on client errors (4xx)
      if (error instanceof Response && error.status >= 400 && error.status < 500) {
        throw error;
      }
      
      // Wait before retrying (with exponential backoff)
      if (attempt < maxAttempts) {
        await new Promise(resolve => setTimeout(resolve, delayMs * Math.pow(2, attempt - 1)));
      }
    }
  }
  
  throw lastError;
}

/**
 * Normalizes text for consistent embedding
 */
export function normalizeTextForEmbedding(text: string): string {
  return text
    .trim()
    .replace(/\s+/g, ' ')           // Normalize whitespace
    .replace(/[\u0000-\u001F]/g, '') // Remove control characters
    .substring(0, 8192);             // Limit length for most embedding models
}

/**
 * Export all utilities as a namespace for convenience
 */
export const LangFlowIntegration = {
  validateConfig: validateLangFlowConfig,
  parsePayload: parseLangFlowPayload,
  transformToVectorize: transformToVectorizeFormat,
  batchTransform: batchTransformToVectorize,
  mapError: mapLangFlowError,
  validateSignature: validateWebhookSignature,
  extractText: extractTextContent,
  buildError: buildErrorResponse,
  validateDimensions: validateEmbeddingDimensions,
  retry: retryLangFlowRequest,
  normalizeText: normalizeTextForEmbedding
};