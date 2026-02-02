# DXI Metric Explainability

**Date:** 2026-02-02
**Status:** Ready for Planning

## Problem Statement

Users don't understand DXI metrics. Specifically:
1. They don't understand what DXI is or what each metric/column means
2. They don't understand WHY their score is what it is (the calculation)
3. They don't know how to improve their scores

This confusion happens immediately - both on the leaderboard view and developer detail view. The dashboard serves both engineering managers (evaluating team performance) and individual developers (tracking their own metrics).

### Current State

- Only one tooltip exists in the entire app (in the header) explaining DXI
- Users see scores but have no context for thresholds or calculations
- Developer detail view shows dimension breakdowns without explaining what each dimension measures
- No actionable guidance on how to improve scores

## What We're Building

A **Progressive Disclosure** system that provides contextual explanations at the right depth, in the right place:

### 1. Leaderboard View - Tooltips on Column Headers

Each column header (DXI Score, Commits, PRs, Reviews, Cycle Time, Lines Changed) will have a **tooltip on hover** with a brief definition.

**Example tooltip for "Cycle Time" column:**
> "Average time from PR creation to merge. Lower is better."

**Example tooltip for "DXI Score" column:**
> "Developer Experience Index - a composite score (0-100) measuring code velocity and collaboration. 70+ is good, 50-70 moderate, <50 needs improvement."

### 2. Developer Detail View - Visual Gauges with Inline Expand

Each of the 5 DXI dimensions gets an enhanced card showing:

#### A. Visual Gauge
A horizontal gauge/thermometer showing:
- The good→bad scale with thresholds marked
- The developer's position on that scale
- Color coding (green for good zone, yellow for moderate, red for needs improvement)

**Example for PR Size (score: 45):**
```
PR Size: 45/100
[====|=========|=======X====]
     200      500      800   1000 lines
     Good    Moderate   Needs Improvement

Your average: 780 lines per PR
```

#### B. Inline "Learn More" Expansion
A "Learn more" link that expands **in place** to reveal:

1. **The Math** - How this score was calculated
   - "Your PRs average 780 lines. Target is <200 lines for a perfect score."
   - "Score formula: PRs under 200 lines = 100, over 1000 lines = 0, linear between"

2. **Improvement Tips** (shown when score < 70)
   - "Break large PRs into smaller, focused changes"
   - "Aim for PRs under 200 lines for easier reviews"
   - "Consider feature flags for incremental delivery"

### 3. DXI Dimensions Reference

For clarity, here are the 5 dimensions with their thresholds:

| Dimension | Weight | Perfect Score (100) | Zero Score (0) |
|-----------|--------|---------------------|----------------|
| Review Turnaround | 25% | < 2 hours | > 24 hours |
| PR Cycle Time | 25% | < 8 hours | > 72 hours |
| PR Size | 20% | < 200 lines | > 1000 lines |
| Review Coverage | 15% | 10+ reviews/sprint | 0 reviews |
| Commit Frequency | 15% | 20+ commits/sprint | 0 commits |

## Why This Approach

1. **Meets users where they are** - Explanations appear in context, not on a separate page
2. **Layered depth** - Quick tooltips for scanning, detailed expansions for learning
3. **User control** - Expand/collapse lets users choose their depth of exploration
4. **Serves both audiences** - Managers get quick tooltips, developers get detailed breakdowns
5. **Mobile-friendly** - Inline expand works better than hover tooltips on touch devices
6. **Shows the math** - Visual gauges make thresholds immediately understandable
7. **Actionable** - Improvement tips give developers concrete next steps

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Leaderboard explanations | Tooltips on hover | Quick-scan view needs lightweight help |
| Detail view explanations | Inline expand | Deeper exploration needs user control |
| Score visualization | Horizontal gauge | Shows position on scale intuitively |
| Improvement tips trigger | Scores below 70 | Aligned with "good" threshold definition |
| Expansion pattern | "Learn more" link | Clear affordance, doesn't clutter default view |

## Scope

### In Scope
- Tooltips on all leaderboard column headers
- Visual gauge component for each dimension in developer detail view
- Inline expand "Learn more" for each dimension showing calculation + tips
- Improvement tips content for all 5 dimensions

### Out of Scope (for now)
- Dedicated methodology page (can add later if needed)
- Guided onboarding tour
- Email/notification-based tips
- Customizable thresholds

## Open Questions

1. **Gauge design** - Should the gauge be a horizontal bar, semi-circle, or vertical thermometer?
2. **Animation** - Should the expand/collapse be animated?
3. **Persistence** - Should expanded state persist across page navigation?

## Next Steps

Run `/workflows:plan` to create implementation tasks.
