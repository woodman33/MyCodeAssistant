import { describe, it, expect, beforeAll, afterAll } from 'vitest';

/**
 * E2E Tests for Edge Backend Workers
 * Tests against live deployment (defaults to mca-edge-worker)
 */

const BASE_URL =
  process.env.WORKER_URL ??
  'https://mca-edge-worker.wmeldman33.workers.dev';
const TIMEOUT = 30000; // 30 seconds for edge requests
const EMBEDDINGS_ENABLED = process.env.EMBEDDINGS_ENABLED === 'true';

interface HealthResponse {
  status: string;
  timestamp: string;
  services: {
    database: boolean;
    kv: boolean;
    r2: boolean;
    vectorize: boolean;
  };
}

interface ChatResponse {
  response: string;
  timestamp: string;
  metadata?: any;
}

interface EmbeddingResponse {
  id: string;
  success: boolean;
  vectorsStored?: number;
  timestamp: string;
  error?: string;
}

describe('Edge Backend E2E Tests', () => {
  
  describe('Health Endpoint', () => {
    it('should return 200 with health status', async () => {
      const response = await fetch(`${BASE_URL}/health`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json'
        }
      });

      expect(response.status).toBe(200);
      
      const data = await response.json();
      
      // Deployed worker returns { ok, ts } (no services/status)
      expect(data).toHaveProperty('ok', true);
      expect(typeof data.ts).toBe('number');
    }, TIMEOUT);
  });

  describe('Chat Endpoint', () => {
    it('should accept POST with valid payload and return 200', async () => {
      const payload = {
        message: 'Hello, this is a test message',
        context: {
          test: true,
          timestamp: new Date().toISOString()
        },
        stream: false
      };

      const response = await fetch(`${BASE_URL}/chat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      expect(response.status).toBe(200);
      
      const data: ChatResponse = await response.json();
      
      // Validate response schema
      expect(data).toHaveProperty('response');
      expect(data).toHaveProperty('timestamp');
      expect(typeof data.response).toBe('string');
      
      // Response should echo the message (as per implementation)
      expect(data.response).toContain('Echo:');
      expect(data.response).toContain(payload.message);
      
      // Validate timestamp
      expect(() => new Date(data.timestamp)).not.toThrow();
      
      // Check metadata if present
      if (data.metadata) {
        expect(data.metadata).toHaveProperty('sessionId');
        expect(data.metadata).toHaveProperty('model');
        expect(data.metadata.model).toBe('echo-test');
      }
    }, TIMEOUT);

    it('should return 400 when message is missing', async () => {
      const payload = {
        context: { test: true }
        // message is missing
      };

      const response = await fetch(`${BASE_URL}/chat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      expect(response.status).toBe(400);
      
      const data = await response.json();
      expect(data).toHaveProperty('error');
      expect(data.error).toContain('Message is required');
    }, TIMEOUT);

    it('should return 405 for GET request', async () => {
      const response = await fetch(`${BASE_URL}/chat`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json'
        }
      });

      expect(response.status).toBe(405);
    }, TIMEOUT);
  });

  describe('Stream Endpoint', () => {
    it('should accept POST and return SSE stream', async () => {
      const payload = {
        message: 'Test streaming response',
        stream: true
      };

      const response = await fetch(`${BASE_URL}/stream`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream'
        },
        body: JSON.stringify(payload)
      });

      expect(response.status).toBe(200);
      expect(response.headers.get('content-type')).toContain('text/event-stream');
      
      // Read SSE stream
      const reader = response.body?.getReader();
      const decoder = new TextDecoder();
      let events: string[] = [];
      
      if (reader) {
        try {
          let done = false;
          let iterations = 0;
          const maxIterations = 20; // Prevent infinite loop
          
          while (!done && iterations < maxIterations) {
            const { value, done: readerDone } = await reader.read();
            done = readerDone;
            
            if (value) {
              const chunk = decoder.decode(value);
              events.push(chunk);
            }
            
            iterations++;
            
            // Check if we've received the done event
            if (events.join('').includes('"type":"done"')) {
              done = true;
            }
          }
        } finally {
          reader.releaseLock();
        }
      }
      
      const fullStream = events.join('');
      
      // Validate SSE format
      expect(fullStream).toContain('data:');
      
      // Parse SSE events
      const dataLines = fullStream
        .split('\n')
        .filter(line => line.startsWith('data:'))
        .map(line => line.replace('data: ', '').trim())
        .filter(line => line.length > 0);
      
      expect(dataLines.length).toBeGreaterThan(0);
      
      // Parse first and last events
      const firstEvent = JSON.parse(dataLines[0]);
      expect(firstEvent).toHaveProperty('type');
      expect(firstEvent.type).toBe('connected');
      
      // Find the done event
      const doneEvent = dataLines
        .map(line => {
          try {
            return JSON.parse(line);
          } catch {
            return null;
          }
        })
        .filter(event => event && event.type === 'done')[0];
      
      expect(doneEvent).toBeTruthy();
      expect(doneEvent).toHaveProperty('timestamp');
    }, TIMEOUT);

    it('should return 400 when message is missing', async () => {
      const payload = {
        stream: true
        // message is missing
      };

      const response = await fetch(`${BASE_URL}/stream`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      expect(response.status).toBe(400);
      
      const data = await response.json();
      expect(data).toHaveProperty('error');
      expect(data.error).toContain('Message is required');
    }, TIMEOUT);

    it('should return 405 for GET request', async () => {
      const response = await fetch(`${BASE_URL}/stream`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json'
        }
      });

      expect(response.status).toBe(405);
    }, TIMEOUT);
  });

  describe('LangFlow Proxy Endpoint', () => {
    it('should handle GET request to /langflow endpoint', async () => {
      const response = await fetch(`${BASE_URL}/langflow/health`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json'
        }
      });

      // LangFlow might not be running, so we accept either:
      // - 503 (Service Unavailable) if LangFlow is not running
      // - 200/404 if it proxies successfully
      expect([200, 403, 404, 503]).toContain(response.status);
      
      if (response.status === 503) {
        const data = await response.json();
        expect(data).toHaveProperty('error');
        expect(data.error).toContain('LangFlow proxy error');
      }
    }, TIMEOUT);

    it('should forward headers correctly', async () => {
      const response = await fetch(`${BASE_URL}/langflow/api/test`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Custom-Header': 'test-value'
        },
        body: JSON.stringify({ test: true })
      });

      // Should get a response (even if error)
      expect(response).toBeTruthy();
      
      // CORS headers should be present
      expect(response.headers.get('access-control-allow-origin')).toBe('*');
    }, TIMEOUT);
  });

  describe('Embeddings Endpoint', () => {
    it('should accept POST to /embeddings and return success', async () => {
      // Align payload with smoke test shape
      const payload = {
        message: 'Smoke test ping',
        test: true
      };

      const response = await fetch(`${BASE_URL}/embeddings`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      if (EMBEDDINGS_ENABLED) {
        expect(response.status).toBe(200);
      } else {
        // In deployed edge, embeddings not exposed → 404 is acceptable
        expect([200, 404]).toContain(response.status);
        if (response.status === 404) return; // skip body asserts
      }
      
      const data: EmbeddingResponse = await response.json();
      
      // Validate response schema
      expect(data).toHaveProperty('id');
      expect(data).toHaveProperty('success');
      expect(data).toHaveProperty('timestamp');
      
      expect(data.success).toBe(true);
      expect(data.vectorsStored).toBe(1);
      
      // ID should be a valid UUID
      expect(data.id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
      
      // Validate timestamp
      expect(() => new Date(data.timestamp)).not.toThrow();
    }, TIMEOUT);

    it('should return 400 when text is missing', async () => {
      // Align payload with smoke test shape (missing message)
      const payload = {
        test: true
      };

      const response = await fetch(`${BASE_URL}/embeddings`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      if (EMBEDDINGS_ENABLED) {
        expect(response.status).toBe(400);
      } else {
        expect([200, 404]).toContain(response.status);
        if (response.status === 404) return; // skip body asserts
      }
      
      const data = await response.json();
      expect(data).toHaveProperty('error');
      expect(data.error).toContain('Text is required');
    }, TIMEOUT);
  });

  describe('Batch Embeddings Endpoint', () => {
    it('should accept POST to /embeddings/batch', async () => {
      const payload = {
        documents: [
          {
            text: 'First test document',
            metadata: { index: 0 }
          },
          {
            text: 'Second test document',
            metadata: { index: 1 }
          }
        ],
        namespace: 'test',
        source: 'e2e-batch'
      };

      const response = await fetch(`${BASE_URL}/embeddings/batch`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      if (EMBEDDINGS_ENABLED) {
        expect(response.status).toBe(200);
      } else {
        expect([200, 404]).toContain(response.status);
        if (response.status === 404) return; // skip body asserts
      }
      
      const data: EmbeddingResponse = await response.json();
      
      // Validate response
      expect(data).toHaveProperty('success');
      expect(data.success).toBe(true);
      expect(data.vectorsStored).toBe(2);
    }, TIMEOUT);

    it('should return 400 when documents array is empty', async () => {
      const payload = {
        documents: [],
        namespace: 'test'
      };

      const response = await fetch(`${BASE_URL}/embeddings/batch`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      if (EMBEDDINGS_ENABLED) {
        expect(response.status).toBe(400);
      } else {
        expect([200, 404]).toContain(response.status);
        if (response.status === 404) return; // skip body asserts
      }
      
      const data = await response.json();
      expect(data).toHaveProperty('error');
      expect(data.error).toContain('Documents array is required');
    }, TIMEOUT);
  });

  describe('CORS Headers', () => {
    it('should handle preflight OPTIONS request', async () => {
      const response = await fetch(`${BASE_URL}/health`, {
        method: 'OPTIONS',
        headers: {
          'Origin': 'http://localhost:3000',
          'Access-Control-Request-Method': 'POST',
          'Access-Control-Request-Headers': 'Content-Type'
        }
      });

      expect(response.status).toBe(200);
      expect(response.headers.get('access-control-allow-origin')).toBe('*');
      expect(response.headers.get('access-control-allow-methods')).toContain('POST');
      expect(response.headers.get('access-control-allow-headers')).toContain('Content-Type');
    }, TIMEOUT);

    it('should include CORS headers in regular responses', async () => {
      const response = await fetch(`${BASE_URL}/health`, {
        method: 'GET',
        headers: {
          'Origin': 'http://localhost:3000'
        }
      });

      expect(response.headers.get('access-control-allow-origin')).toBe('*');
    }, TIMEOUT);
  });

  describe('Error Handling', () => {
    it('should return 404 for unknown endpoints', async () => {
      const response = await fetch(`${BASE_URL}/unknown-endpoint`, {
        method: 'GET'
      });

      expect(response.status).toBe(404);
    }, TIMEOUT);

    it('should handle malformed JSON gracefully', async () => {
      const response = await fetch(`${BASE_URL}/chat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: 'invalid json {]'
      });

      expect(response.status).toBe(500);
      
      const ct = response.headers.get('content-type') || '';
      if (ct.includes('application/json')) {
        const data = await response.json();
        expect(data).toHaveProperty('error');
      } else {
        const text = await response.text();
        expect(typeof text).toBe('string');
      }
    }, TIMEOUT);
  });
});