/**
 * Edge Backend API Worker
 * Handles REST and Server-Sent Events (SSE) endpoints
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

interface ChatRequest {
  message: string;
  context?: any;
  stream?: boolean;
}

interface ChatResponse {
  response: string;
  timestamp: string;
  metadata?: any;
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
      switch (true) {
        case path === '/health':
          return handleHealth();
        
        case path === '/chat':
          if (request.method !== 'POST') {
            return new Response('Method not allowed', {
              status: 405,
              headers: corsHeaders
            });
          }
          return handleChat(request, env, corsHeaders);
        
        case path === '/stream':
          if (request.method !== 'POST') {
            return new Response('Method not allowed', {
              status: 405,
              headers: corsHeaders
            });
          }
          return handleStream(request, env, corsHeaders);
        
        case path.startsWith('/langflow'):
          // Proxy all methods to LangFlow
          return handleLangFlowProxy(request, env, corsHeaders);
        
        default:
          return new Response('Not found', {
            status: 404,
            headers: corsHeaders
          });
      }
    } catch (error) {
      console.error('Worker error:', error);
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

async function handleHealth(): Promise<Response> {
  // Return the simplified health response as specified
  const health = {
    status: "ok"
  };

  return new Response(JSON.stringify(health), {
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'
    }
  });
}

async function handleLangFlowProxy(
  request: Request,
  env: Env,
  corsHeaders: any
): Promise<Response> {
  try {
    // Get LangFlow URL from KV store, fallback to local
    const langflowUrl = await env.KV.get('LANGFLOW_URL') || 'http://localhost:7860';
    
    // Parse the request URL and extract the path after /langflow
    const url = new URL(request.url);
    const langflowPath = url.pathname.replace('/langflow', '');
    
    // Construct the target URL
    const targetUrl = `${langflowUrl}${langflowPath}${url.search}`;
    
    // Clone the request with the new URL
    const headers = new Headers(request.headers);
    
    // Remove CF-specific headers that shouldn't be forwarded
    headers.delete('cf-connecting-ip');
    headers.delete('cf-ipcountry');
    headers.delete('cf-ray');
    headers.delete('cf-visitor');
    
    // Add X-Forwarded headers
    headers.set('X-Forwarded-For', request.headers.get('CF-Connecting-IP') ||
                                   request.headers.get('X-Forwarded-For') ||
                                   'unknown');
    headers.set('X-Forwarded-Proto', url.protocol.replace(':', ''));
    headers.set('X-Forwarded-Host', url.hostname);
    
    // Prepare request options
    const requestOptions: RequestInit = {
      method: request.method,
      headers: headers,
      redirect: 'manual'
    };
    
    // Only include body for methods that support it
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      requestOptions.body = await request.arrayBuffer();
    }
    
    // Make the proxy request
    const proxyResponse = await fetch(targetUrl, requestOptions);
    
    // Clone response headers
    const responseHeaders = new Headers(proxyResponse.headers);
    
    // Add CORS headers
    Object.entries(corsHeaders).forEach(([key, value]) => {
      responseHeaders.set(key, value as string);
    });
    
    // Handle redirects
    if (proxyResponse.status >= 300 && proxyResponse.status < 400) {
      const location = responseHeaders.get('Location');
      if (location) {
        // Rewrite the location header to point back to our proxy
        const locationUrl = new URL(location, langflowUrl);
        const newLocation = `/langflow${locationUrl.pathname}${locationUrl.search}`;
        responseHeaders.set('Location', newLocation);
      }
    }
    
    // Return the proxied response
    return new Response(proxyResponse.body, {
      status: proxyResponse.status,
      statusText: proxyResponse.statusText,
      headers: responseHeaders
    });
    
  } catch (error) {
    console.error('LangFlow proxy error:', error);
    
    // Check if it's a connection error
    const isConnectionError = error instanceof Error &&
                             (error.message.includes('ECONNREFUSED') ||
                              error.message.includes('fetch failed') ||
                              error.message.includes('network'));
    
    const errorResponse = {
      error: 'LangFlow proxy error',
      message: isConnectionError ?
        'Unable to connect to LangFlow. Please ensure LangFlow is running and accessible.' :
        'An error occurred while proxying to LangFlow',
      details: error instanceof Error ? error.message : 'Unknown error',
      timestamp: new Date().toISOString()
    };
    
    return new Response(JSON.stringify(errorResponse), {
      status: isConnectionError ? 503 : 500,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  }
}

async function handleChat(request: Request, env: Env, corsHeaders: any): Promise<Response> {
  const chatRequest: ChatRequest = await request.json();
  
  // Validate request
  if (!chatRequest.message) {
    return new Response(
      JSON.stringify({ error: 'Message is required' }), 
      { 
        status: 400,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      }
    );
  }

  // Store message in KV for session management
  const sessionId = crypto.randomUUID();
  await env.KV.put(
    `session:${sessionId}`,
    JSON.stringify({
      message: chatRequest.message,
      timestamp: new Date().toISOString(),
      context: chatRequest.context
    }),
    { expirationTtl: 3600 } // 1 hour TTL
  );

  // TODO: Integrate with actual AI service
  const response: ChatResponse = {
    response: `Echo: ${chatRequest.message}`,
    timestamp: new Date().toISOString(),
    metadata: {
      sessionId,
      model: 'echo-test'
    }
  };

  return new Response(JSON.stringify(response), {
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json'
    }
  });
}

async function handleStream(request: Request, env: Env, corsHeaders: any): Promise<Response> {
  const chatRequest: ChatRequest = await request.json();
  
  // Validate request
  if (!chatRequest.message) {
    return new Response(
      JSON.stringify({ error: 'Message is required' }), 
      { 
        status: 400,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      }
    );
  }

  // Create a TransformStream for SSE
  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();
  const encoder = new TextEncoder();

  // Start streaming response
  (async () => {
    try {
      // Send initial connection message
      await writer.write(encoder.encode(`data: ${JSON.stringify({ type: 'connected' })}\n\n`));

      // Simulate streaming response (replace with actual AI integration)
      const words = chatRequest.message.split(' ');
      for (const word of words) {
        await writer.write(encoder.encode(`data: ${JSON.stringify({ 
          type: 'token',
          content: word + ' '
        })}\n\n`));
        
        // Add small delay to simulate streaming
        await new Promise(resolve => setTimeout(resolve, 100));
      }

      // Send completion message
      await writer.write(encoder.encode(`data: ${JSON.stringify({ 
        type: 'done',
        timestamp: new Date().toISOString()
      })}\n\n`));

    } catch (error) {
      console.error('Streaming error:', error);
      await writer.write(encoder.encode(`data: ${JSON.stringify({ 
        type: 'error',
        error: 'Stream interrupted'
      })}\n\n`));
    } finally {
      await writer.close();
    }
  })();

  return new Response(readable, {
    headers: {
      ...corsHeaders,
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    }
  });
}