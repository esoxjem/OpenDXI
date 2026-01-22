---
title: Fix DXI trend charts displaying sprints in reverse chronological order
category: ui-bugs
tags:
  - charts
  - data-ordering
  - history-visualization
  - trends
  - api
severity: medium
components_affected:
  - api/app/controllers/api/sprints_controller.rb
  - api/app/controllers/api/developers_controller.rb
  - frontend/src/components/dashboard/DxiTrendChart.tsx
  - frontend/src/components/dashboard/DeveloperTrendChart.tsx
date_solved: 2026-01-22
commit: e5b060e
---

# DXI Trend Charts Displaying Sprints in Reverse Order

## Problem Symptom

The DXI trend charts in both the **History tab** and **Developer History** views were displaying sprints in reverse chronological order—newest sprint on the left, oldest on the right. This is counter-intuitive because trend charts conventionally show time progressing left-to-right.

**Observable behavior:**
- History tab showed "Current Sprint" on the left, older sprints on the right
- Developer trend chart showed the same reversed ordering
- Trend indicators (+/-) were technically correct but visually confusing

## Investigation Steps

1. **Frontend inspection**: Checked `DxiTrendChart.tsx` and `DeveloperTrendChart.tsx` - no sorting logic found; they render data in the order received
2. **API response inspection**: The `/api/sprints/history` endpoint returned sprints with newest first
3. **Backend code review**: Found `Sprint.order(start_date: :desc).limit(count)` in both history endpoints

## Root Cause

The backend history endpoints were using descending order to fetch the most recent N sprints:

```ruby
# api/app/controllers/api/sprints_controller.rb
sprints = Sprint.order(start_date: :desc).limit(count)

# api/app/controllers/api/developers_controller.rb
sprints = Sprint.order(start_date: :desc).limit(count)
```

This correctly fetches the **N most recent** sprints, but returns them in **newest-first** order. The frontend renders them as-is, resulting in reversed trend charts.

**Why not use `order(start_date: :asc)`?**

Using ascending order would fetch the **N oldest sprints ever**, not the N most recent. We need the most recent sprints, but displayed chronologically.

## Working Solution

Add `.reverse` to reorder results after fetching:

```ruby
# api/app/controllers/api/sprints_controller.rb (line 46)
def history
  count = (params[:count] || 6).to_i.clamp(1, 12)
  # Order ascending so trends show oldest→newest (left→right on charts)
  sprints = Sprint.order(start_date: :desc).limit(count).reverse

  render json: {
    sprints: sprints.map { |s| SprintHistorySerializer.new(s).as_json }
  }
end
```

```ruby
# api/app/controllers/api/developers_controller.rb (line 33)
def history
  developer_name = URI.decode_www_form_component(params[:name])
  count = (params[:count] || 6).to_i.clamp(1, 12)

  # Order ascending so trends show oldest→newest (left→right on charts)
  sprints = Sprint.order(start_date: :desc).limit(count).reverse

  # ... rest of method
end
```

**Why `.reverse` works:**
1. `order(start_date: :desc).limit(6)` returns: `[Sprint6, Sprint5, Sprint4, Sprint3, Sprint2, Sprint1]`
2. `.reverse` produces: `[Sprint1, Sprint2, Sprint3, Sprint4, Sprint5, Sprint6]`
3. Charts now display oldest→newest (left→right)

## Prevention Strategies

### 1. Document API contract expectations

When designing time-series endpoints, explicitly document the expected sort order:

```ruby
# GET /api/sprints/history
#
# Returns historical DXI scores across multiple sprints for trend analysis.
# Sprints are ordered chronologically (oldest first) for proper trend display.
```

### 2. Consider adding tests for ordering

```ruby
test "history returns sprints in chronological order (oldest first)" do
  # Create sprints with known dates
  old_sprint = create_sprint(start_date: 2.weeks.ago)
  new_sprint = create_sprint(start_date: 1.week.ago)

  get api_sprints_history_url

  sprints = JSON.parse(response.body)["sprints"]
  assert sprints.first["start_date"] < sprints.last["start_date"]
end
```

### 3. Frontend defensive coding

If the frontend expects chronological order, it could sort defensively:

```typescript
const sortedData = [...data].sort((a, b) =>
  new Date(a.start_date).getTime() - new Date(b.start_date).getTime()
);
```

However, it's better to fix at the source (backend) to maintain a single source of truth.

## Performance Considerations

The `.reverse` operation is negligible because:
- Maximum 12 records (enforced by `.clamp(1, 12)`)
- In-memory Ruby array operation
- No additional database queries

## Cross-References

- **Related components**: `DxiTrendChart.tsx`, `DeveloperTrendChart.tsx`
- **Serializers**: `SprintHistorySerializer`, `DeveloperHistorySerializer`
- **Tests**: `api/test/controllers/api/sprints_controller_test.rb`, `developers_controller_test.rb`

## Verification

After applying the fix:
- History tab shows Nov 12 (oldest) on left → Current Sprint on right
- Developer trend chart shows same chronological order
- Trend indicator (+11.1) correctly shows improvement over time
