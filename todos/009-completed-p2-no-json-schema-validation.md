# No JSON Schema Validation for Sprint Data

---
status: completed
priority: p2
issue_id: "009"
tags: [code-review, data-integrity, rails]
dependencies: []
---

## Problem Statement

The `data` JSON column on Sprint model accepts any structure without validation. Invalid JSON structure will silently cause runtime errors in serializers and views.

**Why it matters**: Data corruption could go undetected until users see broken dashboards. No validation means no early warning of schema drift.

## Findings

### Evidence from data-integrity-guardian agent:

**File**: `api/app/models/sprint.rb`
**Lines**: 86-100

```ruby
def developers
  data&.dig("developers") || []  # Silently returns [] for any corruption
end
```

**Data Corruption Scenario**:
```ruby
# This saves successfully but breaks the dashboard
Sprint.create!(
  start_date: Date.today,
  end_date: Date.today + 14,
  data: { "developers" => "not_an_array" }  # Wrong type
)
```

## Proposed Solutions

### Option A: Custom Validation (Recommended)

```ruby
validate :validate_data_structure

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

private

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

| Aspect | Assessment |
|--------|------------|
| Pros | Catches corruption early, clear error messages |
| Cons | Adds validation overhead |
| Effort | Small |
| Risk | Low |

### Option B: JSON Schema Gem

Use `json-schema` gem for formal validation.

| Aspect | Assessment |
|--------|------------|
| Pros | Industry standard, detailed validation |
| Cons | Additional dependency |
| Effort | Medium |
| Risk | Low |

## Recommended Action

_To be filled during triage_

## Technical Details

**Affected Files**:
- `api/app/models/sprint.rb`

## Acceptance Criteria

- [x] Invalid JSON structure rejected on save
- [x] Clear error messages for each invalid field
- [x] Existing valid data still saves successfully
- [x] Tests for each validation case

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by data-integrity-guardian agent | No schema validation |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
- File: `api/app/models/sprint.rb`
