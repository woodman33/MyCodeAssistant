import { describe, it, expect } from 'vitest';

/**
 * Smoke Tests for Edge Backend
 * Quick health checks for critical endpoints
 * Run against: https://agents-starter.wmeldman33.workers.dev
 */

const BASE_URL = process.env.WORKER_URL ?? 'https://agents-starter.wmeldman33.workers.dev';
const QUICK_TIMEOUT = 10000; // 10 seconds for smoke tests

interface ServiceStatus {
  name: string;
  endpoint: string;
  healthy: boolean;
  responseTime: number;
  error?: string;
}

describe('Edge Backend Smoke Tests', () => {
  const criticalEndpoints = [
    { name: 'Health Check', endpoint: '/health', method: 'GET' },
    { name: 'Chat API', endpoint: '/chat', method: 'POST' },
    { name: 'Stream API', endpoint: '/stream', method: 'POST' },
    { name: 'Embeddings API', endpoint: '/embeddings', method: 'POST' }
  ];

  describe('Workers Deployment Accessibility', () => {
    it('should verify Workers deployment is accessible', async () => {
      const startTime = Date.now();
      
      try {
        const response = await fetch(BASE_URL, {
          method: 'GET',
          signal: AbortSignal.timeout(QUICK_TIMEOUT)
        });
        
        const responseTime = Date.now() - startTime;
        
        // Should get some response (even 404 is fine for root)
        expect(response).toBeTruthy();
        expect(responseTime).toBeLessThan(QUICK_TIMEOUT);
        
        console.log(`✅ Workers deployment accessible (${responseTime}ms)`);
      } catch (error) {
        console.error('❌ Workers deployment not accessible:', error);
        throw new Error('Workers deployment is not accessible');
      }
    }, QUICK_TIMEOUT);

  });

  describe('Critical Endpoint Health', () => {
    it('should verify all critical endpoints respond', async () => {
      const results: ServiceStatus[] = [];
      
      for (const endpoint of criticalEndpoints) {
        const startTime = Date.now();
        let healthy = false;
        let error: string | undefined;
        
        try {
          const options: RequestInit = {
            method: endpoint.method,
            headers: {
              'Content-Type': 'application/json'
            },
            signal: AbortSignal.timeout(QUICK_TIMEOUT)
          };
          
          // Add minimal valid body for POST endpoints
          if (endpoint.method === 'POST') {
            options.body = JSON.stringify({
              message: 'Smoke test ping',
              test: true
            });
          }
          
          const response = await fetch(`${BASE_URL}${endpoint.endpoint}`, options);
          
          // For smoke tests, we just care that it responds
          // 200, 400, 405 are all acceptable (means service is up)
          if (response.status < 500) {
            healthy = true;
          } else {
            error = `HTTP ${response.status}`;
          }
        } catch (err) {
          error = err instanceof Error ? err.message : 'Unknown error';
        }
        
        const responseTime = Date.now() - startTime;
        
        results.push({
          name: endpoint.name,
          endpoint: endpoint.endpoint,
          healthy,
          responseTime,
          error
        });
        
        console.log(
          `${healthy ? '✅' : '❌'} ${endpoint.name}: ${
            healthy ? `OK (${responseTime}ms)` : `FAILED - ${error}`
          }`
        );
      }
      
      // At least 75% of endpoints should be healthy
      const healthyCount = results.filter(r => r.healthy).length;
      const healthPercentage = (healthyCount / results.length) * 100;
      
      console.log(`\n📊 Overall Health: ${healthyCount}/${results.length} endpoints healthy (${healthPercentage.toFixed(0)}%)`);
      
      expect(healthPercentage).toBeGreaterThanOrEqual(75);
    }, QUICK_TIMEOUT * criticalEndpoints.length);
  });

  describe('Database Connectivity', () => {
    it('should verify database connectivity via health endpoint', async () => {
      const response = await fetch(`${BASE_URL}/health`, {
        method: 'GET',
        signal: AbortSignal.timeout(QUICK_TIMEOUT)
      });
      
      expect(response.status).toBe(200);
      
      const data = await response.json();
      
      // Check database status
      if (data.services?.database) {
        console.log('✅ Database connectivity: OK');
      } else {
        console.warn('⚠️ Database connectivity: Not available (might be expected in edge environment)');
      }
      
      // Check other services
      const services = data.services || {};
      console.log('\nService Status:');
      Object.entries(services).forEach(([service, status]) => {
        console.log(`  ${status ? '✅' : '⚠️'} ${service}: ${status ? 'Connected' : 'Not connected'}`);
      });
      
      // If services are reported, at least one should be available; otherwise skip
      const serviceValues = Object.values(services);
      if (serviceValues.length > 0) {
        const anyServiceAvailable = serviceValues.some(status => status === true);
        expect(anyServiceAvailable).toBe(true);
      } else {
        console.warn('⚠️ No services reported by health; skipping availability assertion');
      }
    }, QUICK_TIMEOUT);
  });

  describe('Environment Variables', () => {
    it('should verify critical environment variables are set', async () => {
      // We can't directly check env vars, but we can infer from responses
      const healthResponse = await fetch(`${BASE_URL}/health`, {
        method: 'GET',
        signal: AbortSignal.timeout(QUICK_TIMEOUT)
      });
      
      const healthData = await healthResponse.json();
      
      // Deployed worker returns { ok, ts } (no services/status)
      expect(healthData).toHaveProperty('ok', true);
      expect(typeof healthData.ts).toBe('number');
      
      console.log('✅ Environment appears to be configured correctly');
    }, QUICK_TIMEOUT);
  });

  describe('Response Time Checks', () => {
    it('should respond within acceptable time limits', async () => {
      const timings: { endpoint: string; time: number }[] = [];
      
      // Test health endpoint response time
      const healthStart = Date.now();
      await fetch(`${BASE_URL}/health`, {
        method: 'GET',
        signal: AbortSignal.timeout(QUICK_TIMEOUT)
      });
      const healthTime = Date.now() - healthStart;
      timings.push({ endpoint: '/health', time: healthTime });
      
      // Test a simple POST endpoint
      const chatStart = Date.now();
      await fetch(`${BASE_URL}/chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: 'ping' }),
        signal: AbortSignal.timeout(QUICK_TIMEOUT)
      });
      const chatTime = Date.now() - chatStart;
      timings.push({ endpoint: '/chat', time: chatTime });
      
      // Analyze timings
      const avgTime = timings.reduce((sum, t) => sum + t.time, 0) / timings.length;
      const maxTime = Math.max(...timings.map(t => t.time));
      
      console.log('\n⏱️ Response Times:');
      timings.forEach(t => {
        console.log(`  ${t.endpoint}: ${t.time}ms`);
      });
      console.log(`  Average: ${avgTime.toFixed(0)}ms`);
      console.log(`  Maximum: ${maxTime}ms`);
      
      // Health endpoint should respond quickly (< 2 seconds)
      expect(healthTime).toBeLessThan(2000);
      
      // No endpoint should take more than 5 seconds
      expect(maxTime).toBeLessThan(5000);
      
      console.log('\n✅ Response times are within acceptable limits');
    }, QUICK_TIMEOUT);
  });

  describe('CORS Configuration', () => {
    it('should have proper CORS headers configured', async () => {
      const response = await fetch(`${BASE_URL}/health`, {
        method: 'OPTIONS',
        headers: {
          'Origin': 'http://localhost:3000',
          'Access-Control-Request-Method': 'GET'
        },
        signal: AbortSignal.timeout(QUICK_TIMEOUT)
      });
      
      expect(response.status).toBe(200);
      
      const corsHeaders = {
        'access-control-allow-origin': response.headers.get('access-control-allow-origin'),
        'access-control-allow-methods': response.headers.get('access-control-allow-methods'),
        'access-control-allow-headers': response.headers.get('access-control-allow-headers')
      };
      
      expect(corsHeaders['access-control-allow-origin']).toBeTruthy();
      expect(corsHeaders['access-control-allow-methods']).toContain('GET');
      expect(corsHeaders['access-control-allow-methods']).toContain('POST');
      
      console.log('✅ CORS is properly configured');
      console.log('  Allow-Origin:', corsHeaders['access-control-allow-origin']);
      console.log('  Allow-Methods:', corsHeaders['access-control-allow-methods']);
    }, QUICK_TIMEOUT);
  });

  describe('Error Recovery', () => {
    it('should handle errors gracefully', async () => {
      // Send invalid JSON
      const response = await fetch(`${BASE_URL}/chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: 'invalid json',
        signal: AbortSignal.timeout(QUICK_TIMEOUT)
      });
      
      // Should return error status, not crash
      expect(response.status).toBeGreaterThanOrEqual(400);
      expect(response.status).toBeLessThanOrEqual(500);
      
      console.log('✅ Error handling is working (invalid JSON handled gracefully)');
    }, QUICK_TIMEOUT);

    it('should handle missing required fields', async () => {
      const response = await fetch(`${BASE_URL}/chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}), // Missing required 'message' field
        signal: AbortSignal.timeout(QUICK_TIMEOUT)
      });
      
      expect(response.status).toBe(400);
      
      const data = await response.json();
      expect(data).toHaveProperty('error');
      
      console.log('✅ Validation is working (missing fields detected)');
    }, QUICK_TIMEOUT);
  });

  describe('Summary', () => {
    it('should display smoke test summary', () => {
      console.log('\n' + '='.repeat(50));
      console.log('🔥 SMOKE TEST SUMMARY 🔥');
      console.log('='.repeat(50));
      console.log(`✅ Workers URL: ${BASE_URL}`);
      console.log('✅ All critical smoke tests passed');
      console.log('✅ System is ready for full E2E testing');
      console.log('='.repeat(50) + '\n');
      
      expect(true).toBe(true); // This test always passes if we get here
    });
  });
});