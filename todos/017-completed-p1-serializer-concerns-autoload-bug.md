# P1: Rails Autoload Bug - DimensionScoreSerializable Not Found

## Problem

The metrics API endpoint (`GET /api/sprints/:start/:end/metrics`) returns a 500 error:

```
NameError: uninitialized constant MetricsResponseSerializer::DimensionScoreSerializable
```

## Root Cause

`app/serializers/concerns/dimension_score_serializable.rb` exists but Rails doesn't autoload `app/serializers/concerns/` by default. Only `app/models/concerns/` and `app/controllers/concerns/` are in the default autoload paths.

## Impact

- **Critical**: Frontend dashboard shows "Failed to load metrics" error
- All metrics display is broken
- Developer history endpoints likely affected too

## Solution Options

1. **Add autoload path** (recommended):
   ```ruby
   # config/application.rb
   config.autoload_paths << Rails.root.join("app/serializers/concerns")
   ```

2. **Move concern to standard location**:
   Move `app/serializers/concerns/dimension_score_serializable.rb` to `app/models/concerns/`

3. **Use explicit require**:
   ```ruby
   # In metrics_response_serializer.rb
   require_relative "concerns/dimension_score_serializable"
   ```

## Files Affected

- `api/app/serializers/metrics_response_serializer.rb`
- `api/app/serializers/concerns/dimension_score_serializable.rb`
- `api/config/application.rb` (for the fix)

## Discovered

Found during browser testing of PR #2 (Rails 8 monolith migration).
