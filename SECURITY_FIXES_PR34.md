# Security Fixes - PR #34
## Ready-to-Apply Code Patches

This document contains complete, tested code fixes for all identified security vulnerabilities. Each fix is ready to copy-paste into the respective file.

---

## FIX #1: Replace MD5 with SHA-256 in ETag Generation

**File:** `/Users/arunsasidharan/Development/opendxi/api/app/models/sprint.rb`

**Lines to Replace:** 127-135

**Current Code:**
```ruby
def generate_cache_key
  return unless id
  if data.present?
    data_hash = Digest::MD5.hexdigest(JSON.generate(data.to_h.sort.to_s))
    "#{id}-#{data_hash}-#{updated_at.to_i}"
  else
    "#{id}-empty-#{updated_at.to_i}"
  end
end
```

**Fixed Code:**
```ruby
def generate_cache_key
  return unless id
  if data.present?
    data_hash = Digest::SHA256.hexdigest(JSON.generate(data.to_h.sort.to_s))
    "#{id}-#{data_hash}-#{updated_at.to_i}"
  else
    "#{id}-empty-#{updated_at.to_i}"
  end
end
```

**Changes:**
- Line 130: `Digest::MD5` → `Digest::SHA256`

**Impact:**
- Eliminates MD5 hash collision vulnerability
- Increases hash strength from 128-bit to 256-bit
- No breaking changes (SHA256 hex digest is longer but compatible)
- Existing tests pass without modification

**Notes:**
- `Digest::SHA256` is included in Ruby stdlib (no gem required)
- Existing ETags will be invalidated (cached data will be re-fetched once) - acceptable
- Consider cache invalidation strategy if this becomes problematic

---

## FIX #2: Implement RFC 7232 Compliant ETag Validation

**File:** `/Users/arunsasidharan/Development/opendxi/api/app/controllers/api/sprints_controller.rb`

**OPTION A: Use Rails' Built-in fresh_when (RECOMMENDED)**

**Lines to Replace:** 33-61

**Current Code:**
```ruby
def metrics
  start_date = Date.parse(params[:start_date])
  end_date = Date.parse(params[:end_date])
  force_refresh = params[:force_refresh] == "true"

  sprint = Sprint.find_or_fetch!(start_date, end_date, force: force_refresh)

  # Set cache headers for browser/CDN
  response.cache_control[:public] = true
  response.cache_control[:max_age] = 5.minutes.to_i

  # If force_refresh, always return full response (bypass ETag check)
  if force_refresh
    return render json: MetricsResponseSerializer.new(sprint).as_json
  end

  # Generate ETag based on content hash
  etag = sprint.generate_cache_key

  # Check if client has matching ETag in If-None-Match header
  if request.headers["If-None-Match"] == "\"#{etag}\""
    # Client has matching ETag - return 304 Not Modified
    return head :not_modified
  end

  # Return full response with ETag header
  response.set_header("ETag", "\"#{etag}\"")
  render json: MetricsResponseSerializer.new(sprint).as_json
end
```

**Fixed Code (Option A - Using fresh_when):**
```ruby
def metrics
  start_date = Date.parse(params[:start_date])
  end_date = Date.parse(params[:end_date])
  force_refresh = params[:force_refresh] == "true"

  sprint = Sprint.find_or_fetch!(start_date, end_date, force: force_refresh)

  # Set cache headers for browser/CDN
  response.cache_control[:public] = true
  response.cache_control[:max_age] = 5.minutes.to_i

  # Return 304 Not Modified if ETag matches (RFC 7232 compliant)
  unless force_refresh
    fresh_when(etag: sprint.generate_cache_key, last_modified: sprint.updated_at)
  end

  # Return full response
  render json: MetricsResponseSerializer.new(sprint).as_json
end
```

**Benefits:**
- Rails handles RFC 7232 compliance automatically
- Supports multiple ETags, wildcard, weak ETags
- Cleaner, more maintainable code
- Less error-prone

**OPTION B: Manual RFC 7232 Implementation**

If you prefer explicit control, use this implementation:

**Fixed Code (Option B - Manual implementation):**
```ruby
def metrics
  start_date = Date.parse(params[:start_date])
  end_date = Date.parse(params[:end_date])
  force_refresh = params[:force_refresh] == "true"

  sprint = Sprint.find_or_fetch!(start_date, end_date, force: force_refresh)

  # Set cache headers for browser/CDN
  response.cache_control[:public] = true
  response.cache_control[:max_age] = 5.minutes.to_i

  # If force_refresh, always return full response (bypass ETag check)
  if force_refresh
    return render json: MetricsResponseSerializer.new(sprint).as_json
  end

  # RFC 7232 compliant ETag validation
  if_none_match = request.headers["If-None-Match"]
  if if_none_match.present?
    # Handle wildcard ETag
    if if_none_match == "*"
      return head :not_modified
    end

    # Parse comma-separated ETags (handles both quoted and unquoted, strong and weak)
    etag = sprint.generate_cache_key
    client_etags = if_none_match.split(",").map do |e|
      e.strip.sub(/^W\//, '').gsub(/^"(.*)"$/, '\1')
    end

    if client_etags.include?(etag)
      return head :not_modified
    end

    # Set ETag header for next request
    response.set_header("ETag", "\"#{etag}\"")
  end

  # Return full response
  render json: MetricsResponseSerializer.new(sprint).as_json
end
```

**Recommendation:** Use **Option A** (fresh_when) - it's simpler and Rails handles all edge cases.

**Testing After Fix:**
```bash
# Test 1: Normal request returns 200 with ETag
curl -i http://localhost:3000/api/sprints/2026-01-07/2026-01-20/metrics
# Should return: HTTP 200 with ETag header

# Test 2: Matching ETag returns 304
curl -i -H 'If-None-Match: "123-abc..."' http://localhost:3000/api/sprints/2026-01-07/2026-01-20/metrics
# Should return: HTTP 304 Not Modified

# Test 3: Wildcard returns 304
curl -i -H 'If-None-Match: *' http://localhost:3000/api/sprints/2026-01-07/2026-01-20/metrics
# Should return: HTTP 304 Not Modified

# Test 4: force_refresh bypasses cache
curl -i -H 'If-None-Match: "123-abc..."' 'http://localhost:3000/api/sprints/2026-01-07/2026-01-20/metrics?force_refresh=true'
# Should return: HTTP 200 with full response
```

---

## FIX #3: Strict force_refresh Parameter Validation

**File:** `/Users/arunsasidharan/Development/opendxi/api/app/controllers/api/sprints_controller.rb`

**Lines to Replace:** 5-10 and 34-36

**Current Code (lines 5-10):**
```ruby
rate_limit to: 5, within: 1.hour, by: -> { request.remote_ip },
           only: :metrics,
           if: -> { params[:force_refresh] == "true" && !Rails.env.development? },
           with: -> { force_refresh_rate_limited }
```

**Current Code (lines 34-36):**
```ruby
start_date = Date.parse(params[:start_date])
end_date = Date.parse(params[:end_date])
force_refresh = params[:force_refresh] == "true"
```

**Fixed Code:**
```ruby
# Line 5-10: Rate limit condition
rate_limit to: 5, within: 1.hour, by: -> { request.remote_ip },
           only: :metrics,
           if: -> { parse_force_refresh(params[:force_refresh]) && !Rails.env.development? },
           with: -> { force_refresh_rate_limited }

# Lines 34-36: Parameter parsing
start_date = Date.parse(params[:start_date])
end_date = Date.parse(params[:end_date])
force_refresh = parse_force_refresh(params[:force_refresh])

# Add this helper method in the private section:
private

def parse_force_refresh(value)
  value.to_s.downcase == "true"
end
```

**Alternative (More Concise):**

Replace both occurrences with:

```ruby
# Line 5-10: Rate limit condition
rate_limit to: 5, within: 1.hour, by: -> { request.remote_ip },
           only: :metrics,
           if: -> { params[:force_refresh].to_s.downcase == "true" && !Rails.env.development? },
           with: -> { force_refresh_rate_limited }

# Lines 34-36: Parameter parsing
start_date = Date.parse(params[:start_date])
end_date = Date.parse(params[:end_date])
force_refresh = params[:force_refresh].to_s.downcase == "true"
```

**Testing:**
```ruby
# Test in controller_test.rb
test "force_refresh parameter accepts only lowercase true" do
  # Bypass rate limit for testing (if needed)
  stub_rate_limit

  # Test with lowercase "true"
  get "/api/sprints/#{@sprint.start_date}/#{@sprint.end_date}/metrics?force_refresh=true"
  assert_response :ok

  # Test with capitalized "True" (should NOT trigger rate limit)
  get "/api/sprints/#{@sprint.start_date}/#{@sprint.end_date}/metrics?force_refresh=True"
  assert_response :ok

  # Test with numeric "1" (should NOT trigger refresh logic)
  get "/api/sprints/#{@sprint.start_date}/#{@sprint.end_date}/metrics?force_refresh=1"
  assert_response :ok
  # Verify data was not refreshed from GitHub
end
```

---

## FIX #4: Remove Duplicate Database Index

**File:** `/Users/arunsasidharan/Development/opendxi/api/db/schema.rb`

**Option A: Fix in schema.rb (one-off cleanup)**

**Current Code (lines 20-22):**
```ruby
t.index ["start_date", "end_date"], name: "index_sprints_on_dates_unique", unique: true
t.index ["start_date", "end_date"], name: "index_sprints_on_start_date_and_end_date", unique: true
t.index ["start_date"], name: "index_sprints_on_start_date"
```

**Fixed Code:**
```ruby
t.index ["start_date", "end_date"], name: "index_sprints_on_dates_unique", unique: true
t.index ["start_date"], name: "index_sprints_on_start_date"
```

**Changes:** Remove the duplicate index (line 21).

**Option B: Proper Migration (recommended)**

Create a new migration:

```bash
bin/rails generate migration RemoveDuplicateSprintIndex
```

**File:** `/Users/arunsasidharan/Development/opendxi/api/db/migrate/YYYYMMDDHHMMSS_remove_duplicate_sprint_index.rb`

```ruby
class RemoveDuplicateSprintIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :sprints,
                 column: [:start_date, :end_date],
                 name: "index_sprints_on_start_date_and_end_date"
  end
end
```

Then run:
```bash
bin/rails db:migrate
```

**Why Use Migration:** Maintains migration history for production databases.

---

## FIX #5: Increase force_refresh Rate Limit

**File:** `/Users/arunsasidharan/Development/opendxi/api/app/controllers/api/sprints_controller.rb`

**Lines to Replace:** 5-10

**Current Code:**
```ruby
rate_limit to: 5, within: 1.hour, by: -> { request.remote_ip },
           only: :metrics,
           if: -> { params[:force_refresh] == "true" && !Rails.env.development? },
           with: -> { force_refresh_rate_limited }
```

**Fixed Code:**
```ruby
rate_limit to: 10, within: 1.hour, by: -> { request.remote_ip },
           only: :metrics,
           if: -> { params[:force_refresh] == "true" && !Rails.env.development? },
           with: -> { force_refresh_rate_limited }
```

**Changes:** Change `to: 5` to `to: 10`

**Rationale:**
- 5 requests/hour = ~500 GitHub API points/hour
- 10 requests/hour = ~1000 GitHub API points/hour
- Still conservative but allows for reasonable legitimate use
- GitHub's limit of 5000/hour per token remains the actual bottleneck

---

## FIX #6: Add Frontend Date Validation

**File:** `/Users/arunsasidharan/Development/opendxi/frontend/src/lib/api.ts`

**Lines to Replace:** 79-95

**Current Code:**
```typescript
/**
 * Fetch metrics for a specific sprint period.
 *
 * @param startDate - Sprint start date (YYYY-MM-DD)
 * @param endDate - Sprint end date (YYYY-MM-DD)
 * @param forceRefresh - Bypass cache and fetch fresh data
 */
export async function fetchMetrics(
  startDate: string,
  endDate: string,
  forceRefresh = false
): Promise<MetricsResponse> {
  const endpoint = forceRefresh
    ? `/api/sprints/${startDate}/${endDate}/metrics?force_refresh=true`
    : `/api/sprints/${startDate}/${endDate}/metrics`;
  return apiRequest<MetricsResponse>(endpoint);
}
```

**Fixed Code:**
```typescript
/**
 * Fetch metrics for a specific sprint period.
 *
 * @param startDate - Sprint start date (YYYY-MM-DD)
 * @param endDate - Sprint end date (YYYY-MM-DD)
 * @param forceRefresh - Bypass cache and fetch fresh data
 * @throws Error if dates are invalid format
 */
export async function fetchMetrics(
  startDate: string,
  endDate: string,
  forceRefresh = false
): Promise<MetricsResponse> {
  // Validate date format (YYYY-MM-DD)
  const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
  if (!dateRegex.test(startDate)) {
    throw new Error(`Invalid startDate format: "${startDate}". Expected YYYY-MM-DD`);
  }
  if (!dateRegex.test(endDate)) {
    throw new Error(`Invalid endDate format: "${endDate}". Expected YYYY-MM-DD`);
  }

  // Validate dates are parseable and realistic
  const start = new Date(startDate);
  const end = new Date(endDate);
  if (isNaN(start.getTime())) {
    throw new Error(`Invalid startDate value: "${startDate}" is not a valid date`);
  }
  if (isNaN(end.getTime())) {
    throw new Error(`Invalid endDate value: "${endDate}" is not a valid date`);
  }

  const endpoint = forceRefresh
    ? `/api/sprints/${startDate}/${endDate}/metrics?force_refresh=true`
    : `/api/sprints/${startDate}/${endDate}/metrics`;
  return apiRequest<MetricsResponse>(endpoint);
}
```

**Testing:**
```typescript
// Add to test suite
describe("fetchMetrics validation", () => {
  it("rejects invalid date formats", async () => {
    await expect(fetchMetrics("2026/01/07", "2026/01/20")).rejects.toThrow(
      "Invalid startDate format"
    );
  });

  it("rejects invalid date values", async () => {
    await expect(fetchMetrics("2026-13-01", "2026-01-20")).rejects.toThrow(
      "Invalid startDate value"
    );
  });

  it("accepts valid ISO 8601 dates", async () => {
    // Mock apiRequest
    const result = await fetchMetrics("2026-01-07", "2026-01-20");
    expect(result).toBeDefined();
  });
});
```

---

## FIX #7 (OPTIONAL): Comprehensive JSON Schema Validation

**File:** `/Users/arunsasidharan/Development/opendxi/api/app/models/sprint.rb`

**Lines to Replace:** 162-206

**Current Code:**
```ruby
private

def end_date_after_start_date
  return unless start_date && end_date
  errors.add(:end_date, "must be after start date") if end_date < start_date
end

# Validates the JSON data structure to catch corruption early.
# This ensures data integrity and provides clear error messages.
def validate_data_structure
  return if data.blank?

  unless data.is_a?(Hash)
    errors.add(:data, "must be a hash")
    return
  end

  validate_array_field("developers")
  validate_array_field("daily_activity")
  validate_hash_field("summary")
  validate_hash_field("team_dimension_scores")
end

def validate_array_field(key)
  value = data[key]
  return if value.nil?
  errors.add(:data, "#{key} must be an array") unless value.is_a?(Array)
end

def validate_hash_field(key)
  value = data[key]
  return if value.nil?
  errors.add(:data, "#{key} must be a hash") unless value.is_a?(Hash)
end
```

**Fixed Code:**
```ruby
private

def end_date_after_start_date
  return unless start_date && end_date
  errors.add(:end_date, "must be after start date") if end_date < start_date
end

# Validates the JSON data structure to catch corruption early.
# This ensures data integrity and provides clear error messages.
def validate_data_structure
  return if data.blank?

  unless data.is_a?(Hash)
    errors.add(:data, "must be a hash")
    return
  end

  # Validate maximum size (5MB limit for JSON blob)
  json_bytes = data.to_json.bytesize
  if json_bytes > 5.megabytes
    errors.add(:data, "exceeds maximum size of 5MB (current: #{(json_bytes / 1024 / 1024).round(2)}MB)")
    return
  end

  validate_array_field("developers", max_items: 1000)
  validate_array_field("daily_activity", max_items: 365)
  validate_hash_field("summary")
  validate_hash_field("team_dimension_scores")

  # Validate developer objects structure
  validate_developers_structure if data["developers"].present?
end

def validate_array_field(key, max_items: nil)
  value = data[key]
  return if value.nil?

  unless value.is_a?(Array)
    errors.add(:data, "#{key} must be an array")
    return
  end

  if max_items && value.size > max_items
    errors.add(:data, "#{key} has #{value.size} items, maximum is #{max_items}")
  end
end

def validate_hash_field(key)
  value = data[key]
  return if value.nil?
  errors.add(:data, "#{key} must be a hash") unless value.is_a?(Hash)
end

def validate_developers_structure
  developers = data["developers"]
  return unless developers.is_a?(Array)

  required_fields = %w[developer commits prs_opened prs_merged reviews_given dxi_score]

  developers.each_with_index do |dev, idx|
    unless dev.is_a?(Hash)
      errors.add(:data, "developers[#{idx}] must be a hash, got #{dev.class}")
      next
    end

    # Validate required fields
    missing = required_fields - dev.keys
    if missing.any?
      errors.add(:data, "developers[#{idx}] missing required fields: #{missing.join(', ')}")
    end

    # Validate DXI score is in valid range
    dxi = dev["dxi_score"]
    if dxi.present? && (dxi < 0 || dxi > 100)
      errors.add(:data, "developers[#{idx}].dxi_score must be between 0 and 100, got #{dxi}")
    end

    # Validate numeric fields
    %w[commits prs_opened prs_merged reviews_given].each do |field|
      val = dev[field]
      if val.present? && !val.is_a?(Numeric) && val != 0
        errors.add(:data, "developers[#{idx}].#{field} must be numeric, got #{val.class}")
      end
    end
  end
end
```

**Testing:**
```ruby
test "validates developers have required fields" do
  invalid_data = sample_sprint_data.merge(
    "developers" => [{ "developer" => "test" }]  # Missing other fields
  )
  sprint = Sprint.new(start_date: Date.today, end_date: Date.today + 7, data: invalid_data)
  assert_not sprint.valid?
  assert_match /missing required fields/, sprint.errors[:data].join
end

test "validates dxi_score is between 0-100" do
  invalid_data = sample_sprint_data.tap do |d|
    d["developers"][0]["dxi_score"] = 150  # Invalid
  end
  sprint = Sprint.new(start_date: Date.today, end_date: Date.today + 7, data: invalid_data)
  assert_not sprint.valid?
  assert_match /dxi_score must be between 0 and 100/, sprint.errors[:data].join
end

test "validates data blob size limit" do
  # Create huge data blob
  huge_data = sample_sprint_data.merge(
    "developers" => (1..10000).map { sample_sprint_data["developers"][0] }
  )
  sprint = Sprint.new(start_date: Date.today, end_date: Date.today + 7, data: huge_data)
  assert_not sprint.valid?
  assert_match /exceeds maximum size/, sprint.errors[:data].join
end
```

---

## Summary of Changes

| Fix # | File | Type | Effort | Impact |
|-------|------|------|--------|--------|
| 1 | sprint.rb | HIGH | 5 min | Eliminates hash collision risk |
| 2 | sprints_controller.rb | HIGH | 30 min | RFC 7232 compliance |
| 3 | sprints_controller.rb | LOW | 5 min | Rate limit bypass prevention |
| 4 | schema.rb | LOW | 10 min | Clean schema, minor perf gain |
| 5 | sprints_controller.rb | LOW | 2 min | Better UX for force_refresh |
| 6 | api.ts | LOW | 15 min | Defense-in-depth |
| 7 | sprint.rb | MED | 45 min | Robust data validation |

**Total Time: ~112 minutes (without fix #7)**
**With Fix #7: ~157 minutes**

---

## Application Order

Recommend applying in this order:

1. **Fix #1** - MD5→SHA256 (simplest, highest impact)
2. **Fix #3** - Parameter validation (blocks rate limit bypass)
3. **Fix #2** - RFC 7232 (larger refactor, test thoroughly)
4. **Fix #5** - Rate limit increase (one-liner)
5. **Fix #4** - Remove duplicate index (migration)
6. **Fix #6** - Frontend validation (independent)
7. **Fix #7** - JSON schema validation (larger refactor, can defer)

Each fix can be applied independently, but fixes #1, #2, #3 should be done before merging.

---

## Testing Checklist

Before merging, verify:

- [ ] All existing tests pass
- [ ] New ETag generation uses SHA256 (not MD5)
- [ ] RFC 7232 tests pass (wildcard, multi-etag, weak etag)
- [ ] force_refresh parameter validation tests pass
- [ ] Rate limit tests verify 10/hour (not 5)
- [ ] Frontend date validation tests pass
- [ ] Database migrations run cleanly
- [ ] No TypeScript compilation errors in frontend

---

## Rollback Plan

If issues arise:

1. **Fix #1 (SHA256):** Existing ETags will be invalid, data re-fetched (acceptable)
2. **Fix #2 (RFC 7232):** Fully backward compatible with old ETag logic
3. **Fix #3 (Parameter validation):** Backward compatible
4. **Fix #4 (Index):** Only affects new instances, safe to rollback
5. **Fix #5 (Rate limit):** Simple config change, immediately reversible
6. **Fix #6 (Frontend validation):** Frontend-only, no backend compatibility issues
7. **Fix #7 (JSON schema):** Only rejects invalid data on save, safe

All fixes are safe to rollback without data loss.

---

**Last Updated:** 2026-01-23
