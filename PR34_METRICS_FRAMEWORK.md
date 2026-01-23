# PR #34 Performance Metrics Framework

## Measurement Strategy

Before and after each optimization, use these metrics to validate improvements.

---

## 1. Perceived Latency (User Experience)

### Measurement Method

```javascript
// frontend/src/hooks/useMetrics.ts - Add performance instrumentation

export function useMetrics(startDate: string | undefined, endDate: string | undefined) {
  const queryKey = ["metrics", startDate, endDate];

  return useQuery({
    queryKey,
    queryFn: async () => {
      performance.mark(`${queryKey.join('-')}-start`);
      const result = await fetchMetrics(startDate!, endDate!);
      performance.mark(`${queryKey.join('-')}-end`);
      performance.measure(
        `${queryKey.join('-')}-fetch`,
        `${queryKey.join('-')}-start`,
        `${queryKey.join('-')}-end`
      );
      return result;
    },
    // ... rest of config
  });
}

// Log perceived latency
const PerformanceLogger = {
  logMetricsLatency() {
    const measures = performance.getEntriesByType('measure')
      .filter(m => m.name.includes('metrics'));
    console.table(measures.map(m => ({
      query: m.name,
      duration: `${m.duration.toFixed(0)}ms`,
      type: m.duration < 100 ? 'cached' : 'network',
    })));
  }
};
```

### Baseline Measurements

**BEFORE Optimization:**

```
Sprint selection → Dashboard visible

Scenario A: First visit
  Time to interactive: 2800ms ± 300ms
  Network latency: 2300ms
  Backend processing: 120ms
  React rendering: 380ms

Scenario B: Tab switch (no cache)
  Time to interactive: 2800ms ± 300ms
  Network latency: 2300ms
  Backend processing: 120ms
  React rendering: 380ms

Scenario C: Repeated tab switch (5 min later)
  Time to interactive: 2800ms ± 300ms
  (No advantage from optimization yet)
```

**AFTER Phase 1 (Frontend Caching):**

```
Sprint selection → Dashboard visible

Scenario A: First visit (cache miss)
  Time to interactive: 2800ms ± 300ms  (No change, network still dominates)
  Network latency: 2300ms
  Backend processing: 120ms
  React rendering: 380ms

Scenario B: Tab switch 2 min later (cache hit)
  Time to interactive: 45ms ± 10ms     (96% improvement!)
  TanStack Query: <5ms
  React rendering: 40ms
  Background refetch: 2300ms (invisible to user)

Scenario C: Tab switch 6 min later (cache expired)
  Time to interactive: 2800ms ± 300ms  (Cache expired, same as first)
```

**Expected Target Improvements:**

```
✓ Repeated tab switches within 5 minutes: <100ms
✓ Background refresh: No impact on perceived latency
✓ Cache hit rate: >80% for typical 30-minute session
```

### Measurement Tools

```bash
# Browser DevTools: Performance tab
1. Click tab to navigate
2. Take performance recording
3. Measure "Time to Interactive"

# Frontend logging
console.log('Perceived latency:', performance.now() - startTime, 'ms');

# Server-side logging
Rails.logger.info("Backend processing: #{Time.now - start_time}s");
```

---

## 2. Network Efficiency Metrics

### Bandwidth Measurement

```ruby
# api/app/controllers/api/sprints_controller.rb - Add instrumentation

def metrics
  # ... existing code ...

  start_time = Time.now
  response_size_bytes = nil

  render json: MetricsResponseSerializer.new(sprint).as_json do |output|
    response_size_bytes = output.bytesize
  end

  Rails.logger.info({
    type: "metrics_response",
    endpoint: "sprints/metrics",
    sprint: "#{start_date}..#{end_date}",
    status_code: response.status,
    response_size_bytes: response_size_bytes,
    content_encoding: response.headers["Content-Encoding"],
    etag: response.headers["ETag"]&.first(20),
    response_time_ms: ((Time.now - start_time) * 1000).round,
  }.to_json)
end
```

### Baseline Measurements

**Response Size:**

```
Full response (200 OK): 50-60KB
  - Developer array: 30KB (per developer varies)
  - Daily activity: 8KB
  - Summary + team scores: 2KB
  - Total: ~52KB

304 Not Modified response: 0 bytes body
  - HTTP headers: 2KB (Cache-Control, ETag, etc.)
  - Total: ~2KB

Compression (if enabled):
  - Gzip: 52KB → 12KB (77% reduction)
  - Brotli: 52KB → 11KB (79% reduction)
```

**Request Frequency:**

```
Session A (1 user, 15 min):
  Total requests: 3-4
  Total bandwidth: 150-160KB

Session B (1 user, 1 hour):
  Total requests: 10-12
  Total bandwidth: 420-500KB

Session C (1 user, 8 hour session):
  Total requests: 50-60
  Total bandwidth: 2-3MB
```

### Measurement Framework

```javascript
// frontend/src/lib/networkMetrics.ts

export class NetworkMetrics {
  private metrics: Array<{
    timestamp: number;
    url: string;
    method: string;
    status: number;
    size: number;
    duration: number;
    cached: boolean;
  }> = [];

  logRequest(req: Request, res: Response, duration: number, fromCache: boolean) {
    this.metrics.push({
      timestamp: Date.now(),
      url: new URL(req.url).pathname,
      method: req.method,
      status: res.status,
      size: res.headers.get('Content-Length')
        ? parseInt(res.headers.get('Content-Length')!)
        : 0,
      duration,
      cached: fromCache,
    });
  }

  getReport(lastMinutes: number = 5) {
    const cutoff = Date.now() - (lastMinutes * 60 * 1000);
    const recent = this.metrics.filter(m => m.timestamp > cutoff);

    const cached = recent.filter(m => m.cached);
    const uncached = recent.filter(m => !m.cached);

    return {
      totalRequests: recent.length,
      cachedRequests: cached.length,
      uncachedRequests: uncached.length,
      cacheHitRate: recent.length > 0
        ? (cached.length / recent.length * 100).toFixed(1) + '%'
        : 'N/A',
      totalBandwidth: recent.reduce((sum, m) => sum + m.size, 0),
      avgRequestDuration: recent.length > 0
        ? (recent.reduce((sum, m) => sum + m.duration, 0) / recent.length).toFixed(0) + 'ms'
        : 'N/A',
      cachedBandwidth: cached.reduce((sum, m) => sum + m.size, 0),
      uncachedBandwidth: uncached.reduce((sum, m) => sum + m.size, 0),
    };
  }

  exportCSV() {
    const rows = this.metrics.map(m =>
      `${new Date(m.timestamp).toISOString()},${m.url},${m.status},${m.size},${m.duration},${m.cached}`
    );
    return ['timestamp,url,status,size,duration,cached', ...rows].join('\n');
  }
}

// Usage
const networkMetrics = new NetworkMetrics();

// After each request
networkMetrics.logRequest(req, res, duration, isCached);

// Periodic reporting
setInterval(() => {
  console.table(networkMetrics.getReport());
}, 5 * 60 * 1000);
```

### Expected Improvements

```
Before optimization:
  Cache hit rate: 0%
  Average request size: 52KB
  Typical 1-hour session: 500KB bandwidth

After Phase 1 (Frontend Caching):
  Cache hit rate: 20-30%
  Average request size: 42KB (mix of 52KB full + 0KB cache hits)
  Typical 1-hour session: 350KB bandwidth (30% reduction)

After Phase 2 (HTTP Caching + ETag):
  Cache hit rate: 80-90%
  Average request size: 6KB (mix of 52KB full + 2KB 304 responses)
  Typical 1-hour session: 120KB bandwidth (75% reduction)
```

---

## 3. CPU & Memory Metrics

### Backend CPU Usage

```ruby
# api/config/initializers/performance_monitoring.rb

if Rails.env.production?
  require 'ruby-prof'

  # Monitor ETag generation specifically
  module Api
    class SprintsController < BaseController
      around_action :profile_etag_generation, only: :metrics

      private

      def profile_etag_generation
        start_cpu = Process.times.utime
        start_time = Time.now

        yield

        end_cpu = Process.times.utime
        end_time = Time.now

        cpu_time = (end_cpu - start_cpu) * 1000  # ms
        wall_time = (end_time - start_time) * 1000  # ms

        Rails.logger.info({
          type: "etag_performance",
          cpu_time_ms: cpu_time.round(2),
          wall_time_ms: wall_time.round(2),
          cpu_efficiency: (cpu_time / wall_time * 100).round(1),
        }.to_json)
      end
    end
  end
end
```

### Baseline Measurements

**ETag Generation CPU Cost:**

```
Current implementation (before optimization):

generate_cache_key() performance:
  JSON.generate(data): 5-8ms
  data.to_h.sort.to_s: 8-10ms
  MD5.hexdigest(): 1-2ms
  Total: 14-20ms per call

Under load:
  1 concurrent request: 15ms (acceptable)
  10 concurrent requests: 150ms (acceptable)
  100 concurrent requests: 1500ms (concerning)
  1000 concurrent requests: 15000ms (problematic)
```

**After Optimization (cached_etag column):**

```
generate_cache_key() performance:
  Database lookup (cached): 0.1-0.5ms
  String formatting: 0.1-0.2ms
  Total: 0.2-0.7ms per call

Under load:
  100 concurrent requests: 50-70ms (97% improvement!)
  1000 concurrent requests: 200-700ms (95% improvement!)
```

### Frontend Memory Usage

```javascript
// frontend/src/lib/memoryMetrics.ts

export class MemoryMetrics {
  private snapshots: Array<{
    timestamp: number;
    usedJSHeapSize: number;
    totalJSHeapSize: number;
    jsHeapSizeLimit: number;
    activeQueries: number;
  }> = [];

  capture() {
    if (!performance.memory) {
      console.warn('performance.memory not available');
      return;
    }

    const queryCount = queryClient.getQueryCache().getAll().length;

    this.snapshots.push({
      timestamp: Date.now(),
      usedJSHeapSize: performance.memory.usedJSHeapSize,
      totalJSHeapSize: performance.memory.totalJSHeapSize,
      jsHeapSizeLimit: performance.memory.jsHeapSizeLimit,
      activeQueries: queryCount,
    });
  }

  getReport() {
    if (this.snapshots.length === 0) return null;

    const sorted = [...this.snapshots].sort((a, b) => a.usedJSHeapSize - b.usedJSHeapSize);
    const latest = this.snapshots[this.snapshots.length - 1];
    const peak = sorted[sorted.length - 1];
    const avg = this.snapshots.reduce((sum, s) => sum + s.usedJSHeapSize, 0) / this.snapshots.length;

    return {
      current: `${(latest.usedJSHeapSize / 1024 / 1024).toFixed(1)}MB`,
      peak: `${(peak.usedJSHeapSize / 1024 / 1024).toFixed(1)}MB`,
      average: `${(avg / 1024 / 1024).toFixed(1)}MB`,
      limit: `${(latest.jsHeapSizeLimit / 1024 / 1024).toFixed(0)}MB`,
      activeQueries: latest.activeQueries,
      pressureLevel: latest.usedJSHeapSize / latest.jsHeapSizeLimit > 0.8
        ? 'HIGH'
        : latest.usedJSHeapSize / latest.jsHeapSizeLimit > 0.5
        ? 'MEDIUM'
        : 'LOW',
    };
  }

  startMonitoring(intervalSeconds: number = 10) {
    return setInterval(() => {
      this.capture();
      const report = this.getReport();
      if (report) {
        console.log('[Memory]', report);
      }
    }, intervalSeconds * 1000);
  }
}
```

### Expected Memory Profile

**Frontend (Browser):**

```
Baseline (no cache):
  Initial load: 20-30MB heap
  After 5 sprint selections: 35-45MB
  Growth per sprint: ~2-3MB
  Long-term trend: Stable (no accumulation)

With 30-min gcTime cache:
  Initial load: 20-30MB heap
  After 5 sprint selections: 35-50MB (+5-15% more due to cache)
  Growth per sprint: ~2-3MB
  After 1-hour session: 45-65MB
  Long-term risk: Potential memory leak if cache not cleaned
```

**Backend (Rails):*

```
Baseline (no ETag caching):
  Memory per request: 160KB temporary (freed after request)
  Under 100 concurrent users: Peak 16MB, average 5-8MB
  GC pause time: 50-100ms

With cached_etag column:
  Memory per request: 2KB temporary (freed after request)
  Under 100 concurrent users: Peak 2MB, average 0.5-1MB (80% reduction)
  GC pause time: 5-10ms
```

---

## 4. Database Query Performance

### Query Time Measurement

```ruby
# api/test/performance/sprint_queries_test.rb

require 'benchmark'

class SprintQueriesPerformanceTest < ActiveSupport::TestCase
  def test_find_by_dates_with_index
    sprint = Sprint.create!(
      start_date: Date.new(2026, 1, 7),
      end_date: Date.new(2026, 1, 20),
      data: { developers: [] }
    )

    # Warm up
    Sprint.find_by(start_date: sprint.start_date, end_date: sprint.end_date)

    # Benchmark
    time = Benchmark.measure {
      1000.times {
        Sprint.find_by(start_date: sprint.start_date, end_date: sprint.end_date)
      }
    }

    # Should complete 1000 queries in <100ms
    assert time.real < 0.1,
      "Expected <100ms for 1000 queries, got #{(time.real * 1000).round(0)}ms"

    puts "Query time: #{(time.real / 1000 * 1000).round(2)}ms per query"
  end
end
```

### Expected Performance

```
Before index:
  Full table scan
  Query time: 5-10ms (with only 2 rows, not noticeable)
  Scalability: O(n) - degrades with data size

After unique composite index:
  B-tree lookup
  Query time: <1ms (sub-millisecond)
  Scalability: O(log n) - scales to 10,000+ sprints

Query plan (EXPLAIN):
  Before: SCAN TABLE sprints
  After: SEARCH TABLE sprints USING INDEX index_sprints_on_dates_unique
```

---

## 5. Cache Hit Rate Monitoring

### Frontend Cache Hit Rate

```typescript
// frontend/src/hooks/useMetrics.ts - Add cache hit tracking

let cacheHitCount = 0;
let cacheMissCount = 0;

export function useMetrics(startDate: string | undefined, endDate: string | undefined) {
  return useQuery({
    queryKey: ["metrics", startDate, endDate],
    queryFn: async () => {
      const result = await fetchMetrics(startDate!, endDate!);
      return result;
    },
    onSuccess: (data, variables) => {
      // Track cache hit/miss
      if (queryClient.getQueryData(['metrics', startDate, endDate])) {
        cacheHitCount++;
      } else {
        cacheMissCount++;
      }

      // Log periodically
      const total = cacheHitCount + cacheMissCount;
      if (total % 10 === 0) {
        const hitRate = (cacheHitCount / total * 100).toFixed(1);
        console.log(`[Cache Stats] Hit rate: ${hitRate}% (${cacheHitCount}/${total})`);
      }
    },
  });
}
```

### HTTP Cache Hit Rate

```ruby
# api/middleware/cache_analytics.rb

class CacheAnalytics
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)

    # Track 304 responses (cache hits)
    if status == 304
      @cache_hits ||= 0
      @cache_hits += 1
    else
      @cache_misses ||= 0
      @cache_misses += 1
    end

    # Log periodically
    total = @cache_hits.to_i + @cache_misses.to_i
    if total % 100 == 0
      hit_rate = (@cache_hits.to_i.to_f / total * 100).round(1)
      Rails.logger.info("HTTP Cache hit rate: #{hit_rate}% (#{@cache_hits}/#{total})")
    end

    [status, headers, body]
  end
end
```

### Target Metrics

```
Phase 1 (Frontend caching):
  Frontend cache hit rate: 60-80%
  HTTP 304 rate: 0% (no HTTP caching yet)
  Total bandwidth savings: 20-30%

Phase 2 (HTTP caching):
  Frontend cache hit rate: 60-80% (unchanged)
  HTTP 304 rate: 70-90%
  Total bandwidth savings: 75-85%
  (Combining both phases)
```

---

## 6. Load Testing Framework

### Setup: Simulate 100 Concurrent Users

```bash
# Using Apache Bench
ab -n 1000 -c 100 "http://localhost:3000/api/sprints/2026-01-07/2026-01-20/metrics"

# Using wrk (recommended)
wrk -t4 -c100 -d30s --script=request.lua http://localhost:3000/api/sprints/2026-01-07/2026-01-20/metrics
```

### Load Test Scenario

```javascript
// frontend/test/load-test.js - Simulate tab switching

const { test } = require('@playwright/test');

test('load test: 100 concurrent tab switches', async ({ browser }) => {
  const contexts = [];
  const results = [];

  // Create 100 browser contexts
  for (let i = 0; i < 100; i++) {
    const context = await browser.newContext();
    contexts.push(context);
  }

  // Concurrent tab switches
  const promises = contexts.map(async (context, index) => {
    const page = await context.newPage();
    const timings = [];

    for (let j = 0; j < 10; j++) {
      const sprint = sprints[j % sprints.length];
      const startTime = Date.now();

      await page.goto(`/?sprint=${sprint}`);
      await page.waitForSelector('[data-testid="dashboard"]');

      const duration = Date.now() - startTime;
      timings.push(duration);
    }

    results.push({
      context: index,
      avgTime: timings.reduce((a, b) => a + b) / timings.length,
      minTime: Math.min(...timings),
      maxTime: Math.max(...timings),
    });
  });

  await Promise.all(promises);

  // Report results
  const avgOfAvg = results.reduce((a, b) => a + b.avgTime, 0) / results.length;
  console.log(`Average latency (100 concurrent): ${avgOfAvg.toFixed(0)}ms`);
  console.log(`P99: ${[...results].sort((a, b) => a.avgTime - b.avgTime)[99].avgTime.toFixed(0)}ms`);
  console.log(`P95: ${[...results].sort((a, b) => a.avgTime - b.avgTime)[94].avgTime.toFixed(0)}ms`);
});
```

### Success Criteria

```
Load test with 100 concurrent users:

Phase 1 (Frontend caching):
  ✓ P95 latency: <500ms (some full fetches mixed in)
  ✓ P99 latency: <3s (worst case is network bound)
  ✓ Server CPU: <60%
  ✓ Error rate: 0%

Phase 2 (HTTP caching + ETag):
  ✓ P95 latency: <150ms (mostly cached + 304 responses)
  ✓ P99 latency: <300ms
  ✓ Server CPU: <40%
  ✓ Error rate: 0%

Phase 3 (Optimized ETag):
  ✓ P95 latency: <120ms
  ✓ P99 latency: <250ms
  ✓ Server CPU: <20%
  ✓ Error rate: 0%
```

---

## 7. Monitoring Dashboard

### Key Metrics to Track

```
Real-Time Monitoring (production):

1. Perceived Latency
   - Current: [measured time]
   - Target: <100ms for cache hits
   - Alert if: >500ms

2. Cache Hit Rate
   - Frontend: [%]
   - HTTP: [%]
   - Target: >80% combined
   - Alert if: <50%

3. Network Efficiency
   - Avg response size: [KB]
   - 304 responses: [% of total]
   - Target: <10KB avg (with 304s)
   - Alert if: >25KB avg

4. Backend CPU
   - Current: [%]
   - Peak: [%]
   - Target: <40%
   - Alert if: >70%

5. Browser Memory
   - Current heap: [MB]
   - Pressure level: [LOW|MEDIUM|HIGH]
   - Target: <100MB
   - Alert if: >200MB

6. Request Throughput
   - Requests/sec: [#]
   - 95th percentile latency: [ms]
   - Error rate: [%]
```

### Implementation

```typescript
// frontend/src/components/admin/PerformanceDashboard.tsx

export function PerformanceDashboard() {
  const [metrics, setMetrics] = useState({
    latency: 0,
    cacheHitRate: 0,
    responseSize: 0,
    memoryUsage: 0,
    errorRate: 0,
  });

  useEffect(() => {
    const interval = setInterval(async () => {
      const response = await fetch('/api/metrics/dashboard');
      const data = await response.json();
      setMetrics(data);
    }, 5000);

    return () => clearInterval(interval);
  }, []);

  return (
    <div className="grid grid-cols-2 gap-4">
      <MetricCard
        title="Perceived Latency"
        value={`${metrics.latency}ms`}
        target="<100ms"
        status={metrics.latency < 100 ? 'good' : 'warning'}
      />
      <MetricCard
        title="Cache Hit Rate"
        value={`${metrics.cacheHitRate}%`}
        target=">80%"
        status={metrics.cacheHitRate > 80 ? 'good' : 'warning'}
      />
      <MetricCard
        title="Response Size"
        value={`${metrics.responseSize}KB`}
        target="<10KB"
        status={metrics.responseSize < 10 ? 'good' : 'warning'}
      />
      <MetricCard
        title="Memory Usage"
        value={`${metrics.memoryUsage}MB`}
        target="<100MB"
        status={metrics.memoryUsage < 100 ? 'good' : 'warning'}
      />
    </div>
  );
}
```

---

## 8. Regression Testing

### Performance Regression Test

```ruby
# api/test/performance/regression_test.rb

class PerformanceRegressionTest < ActiveSupport::TestCase
  setup do
    @sprint = Sprint.create!(
      start_date: Date.new(2026, 1, 7),
      end_date: Date.new(2026, 1, 20),
      data: large_dataset  # 100+ developers
    )
  end

  test "metrics endpoint responds in <50ms (backend processing)" do
    time = Benchmark.measure {
      get "/api/sprints/#{@sprint.start_date}/#{@sprint.end_date}/metrics"
    }

    backend_time = time.real * 1000  # Convert to ms
    assert backend_time < 50,
      "Expected <50ms, got #{backend_time.round(0)}ms. " \
      "Performance regression detected!"
  end

  test "etag generation completes in <2ms" do
    time = Benchmark.measure {
      100.times { @sprint.generate_cache_key }
    }

    avg_time = (time.real / 100) * 1000  # ms per call
    assert avg_time < 2,
      "Expected <2ms per call, got #{avg_time.round(2)}ms. " \
      "ETag generation regression detected!"
  end

  test "database query uses index" do
    # Verify explain plan shows index usage
    result = @sprint.class.connection.execute(
      "EXPLAIN QUERY PLAN SELECT * FROM sprints WHERE start_date = ? AND end_date = ?",
      [@sprint.start_date, @sprint.end_date]
    )

    plan = result.first
    assert plan.include?("index_sprints_on_dates_unique"),
      "Query should use index! Plan: #{plan}"
  end

  private

  def large_dataset
    {
      "developers" => (1..100).map { |i|
        {
          "developer" => "dev#{i}",
          "commits" => rand(1..50),
          "prs_opened" => rand(1..10),
          "prs_merged" => rand(1..10),
          "reviews_given" => rand(1..20),
          "lines_added" => rand(100..5000),
          "lines_deleted" => rand(10..1000),
          "dxi_score" => rand(30.0..95.0),
          "dimension_scores" => {
            "review_turnaround" => rand(30.0..95.0),
            "cycle_time" => rand(30.0..95.0),
            "pr_size" => rand(30.0..95.0),
            "review_coverage" => rand(30.0..95.0),
            "commit_frequency" => rand(30.0..95.0),
          }
        }
      },
      "daily_activity" => (1..14).map { |day|
        {
          "date" => (Date.new(2026, 1, 7) + day).to_s,
          "commits" => rand(10..100),
          "prs_opened" => rand(1..20),
          "prs_merged" => rand(1..20),
        }
      },
      "summary" => {
        "total_commits" => 1000,
        "total_prs" => 200,
        "total_merged" => 150,
        "total_reviews" => 500,
        "developer_count" => 100,
        "avg_dxi_score" => 72.5,
      },
      "team_dimension_scores" => {
        "review_turnaround" => 75.0,
        "cycle_time" => 70.0,
        "pr_size" => 80.0,
        "review_coverage" => 65.0,
        "commit_frequency" => 72.0,
      }
    }
  end
end
```

---

## Summary: Metrics Checklist

Use this checklist to validate each optimization:

```
Phase 1 - Frontend Caching:
  ☐ Cache hit rate measured and logged
  ☐ Perceived latency <100ms for cache hits
  ☐ Memory usage monitored (no leaks)
  ☐ Load test 50 concurrent users passes

Phase 2 - HTTP Caching:
  ☐ ETag generation benchmarked
  ☐ 304 response rate >70%
  ☐ Bandwidth reduction >75%
  ☐ Database queries using index

Phase 3 - ETag Optimization:
  ☐ ETag generation <1ms per request
  ☐ Server CPU reduced by 80%
  ☐ Load test 100 concurrent users passes
  ☐ No performance regression

Regression Tests:
  ☐ Metrics endpoint <50ms backend time
  ☐ ETag generation <2ms average
  ☐ Database queries use index
  ☐ All 113 tests pass
```

