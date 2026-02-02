/**
 * DXI Dimension Configuration
 *
 * Centralized configuration for all 5 DXI dimensions including:
 * - Thresholds for score calculation
 * - Display labels and descriptions
 * - Tooltip content for quick context
 * - Detailed explanations for learn more sections
 * - Improvement tips for low scorers
 */

export interface DimensionThreshold {
  min: number;
  max: number;
  unit: string;
}

export interface DimensionConfig {
  key: keyof typeof DIMENSION_CONFIGS;
  label: string;
  /** Label shown in developer detail view (may differ from leaderboard) */
  detailLabel: string;
  weight: number;
  threshold: DimensionThreshold;
  /** Brief tooltip for leaderboard column headers */
  tooltip: string;
  /** Function to format the raw value for display */
  formatRawValue: (value: number | null) => string;
  /** Template for the calculation explanation - {value} is replaced with actual */
  calculationTemplate: string;
  /** Threshold explanation bullets */
  thresholdExplanation: readonly string[];
  /** Tips shown when score < 70 */
  improvementTips: readonly string[];
  /** Whether lower raw values are better (for inverse metrics) */
  inverseMetric: boolean;
}

export const DIMENSION_CONFIGS = {
  review_speed: {
    key: "review_speed" as const,
    label: "Review Turnaround",
    detailLabel: "Review Turnaround",
    weight: 25,
    threshold: { min: 2, max: 24, unit: "hours" },
    tooltip:
      "Time to first code review. Fast feedback keeps PRs moving and teammates unblocked.",
    formatRawValue: (value: number | null) =>
      value !== null ? `${value.toFixed(1)}h avg` : "No reviews",
    calculationTemplate: "Your reviews average **{value} hours** turnaround.",
    thresholdExplanation: [
      "< 2 hours = 100 points (perfect)",
      "> 24 hours = 0 points",
      "Linear scale between thresholds",
    ],
    improvementTips: [
      "Check for review requests first thing each morning",
      "Set up Slack/email notifications for review requests",
      "Block 30 minutes daily specifically for code reviews",
    ],
    inverseMetric: true,
  },
  cycle_time: {
    key: "cycle_time" as const,
    label: "Cycle Time",
    detailLabel: "PR Cycle Time",
    weight: 25,
    threshold: { min: 8, max: 72, unit: "hours" },
    tooltip:
      "Average time from PR creation to merge. Faster cycles mean quicker value delivery.",
    formatRawValue: (value: number | null) =>
      value !== null ? `${value.toFixed(1)}h avg` : "No PRs merged",
    calculationTemplate:
      "Your PRs average **{value} hours** from open to merge.",
    thresholdExplanation: [
      "< 8 hours = 100 points (perfect)",
      "> 72 hours = 0 points",
      "Linear scale between thresholds",
    ],
    improvementTips: [
      "Address review comments within 4 hours of receiving them",
      "Break features into smaller, focused PRs for faster reviews",
      "Communicate blockers early to reviewers",
    ],
    inverseMetric: true,
  },
  pr_size: {
    key: "pr_size" as const,
    label: "PR Size",
    detailLabel: "PR Size",
    weight: 20,
    threshold: { min: 200, max: 1000, unit: "lines" },
    tooltip:
      "Average lines changed per PR. Smaller PRs are easier to review and less risky.",
    formatRawValue: (value: number | null) =>
      value !== null ? `${Math.round(value)} lines avg` : "No PRs",
    calculationTemplate: "Your PRs average **{value} lines** changed.",
    thresholdExplanation: [
      "< 200 lines = 100 points (perfect)",
      "> 1000 lines = 0 points",
      "Linear scale between thresholds",
    ],
    improvementTips: [
      "Break large PRs into smaller, focused changes",
      "Aim for PRs under 200 lines for easier reviews",
      "Consider feature flags for incremental delivery",
    ],
    inverseMetric: true,
  },
  review_coverage: {
    key: "review_coverage" as const,
    label: "Reviews",
    detailLabel: "Review Coverage",
    weight: 15,
    threshold: { min: 0, max: 10, unit: "reviews" },
    tooltip:
      "Code reviews given this sprint. Reviewing teammates' code builds shared understanding.",
    formatRawValue: (value: number | null) =>
      value !== null ? `${value} reviews` : "No data",
    calculationTemplate: "You've given **{value} reviews** this sprint.",
    thresholdExplanation: [
      "10+ reviews = 100 points (perfect)",
      "0 reviews = 0 points",
      "10 points per review",
    ],
    improvementTips: [
      "Aim to review at least 2 PRs per day",
      "Pair review with another developer on complex PRs",
      "Set a goal of reviewing all PRs in your area of expertise",
    ],
    inverseMetric: false,
  },
  commit_frequency: {
    key: "commit_frequency" as const,
    label: "Commits",
    detailLabel: "Commit Frequency",
    weight: 15,
    threshold: { min: 0, max: 20, unit: "commits" },
    tooltip:
      "Commits pushed this sprint. Regular commits indicate steady progress and reduce merge conflicts.",
    formatRawValue: (value: number | null) =>
      value !== null ? `${value} commits` : "No data",
    calculationTemplate: "You've made **{value} commits** this sprint.",
    thresholdExplanation: [
      "20+ commits = 100 points (perfect)",
      "0 commits = 0 points",
      "5 points per commit",
    ],
    improvementTips: [
      "Commit working changes at least once per day",
      "Use atomic commits for logical units of work",
      "Don't let work go stale in local branches",
    ],
    inverseMetric: false,
  },
} as const;

/** Leaderboard column tooltip definitions */
export const LEADERBOARD_TOOLTIPS = {
  dxi_score:
    "Developer Experience Index — a composite score (0-100) measuring code velocity and collaboration. 70+ is good, 50-70 moderate, <50 needs improvement.",
  commits: "Total commits pushed during this sprint.",
  prs: "Pull requests merged out of total opened (merged/opened).",
  reviews: "Code reviews given to teammates during this sprint.",
  cycle_time: "Average time from PR creation to merge. Lower is better.",
  lines_changed: "Total lines added plus deleted across all PRs.",
} as const;

/** Get the appropriate score color class based on score value */
export function getScoreColorClass(score: number): string {
  if (score >= 70) return "text-emerald-600 dark:text-emerald-400";
  if (score >= 50) return "text-amber-600 dark:text-amber-400";
  return "text-rose-600 dark:text-rose-400";
}

/** Get the appropriate background color class for gauge zones */
export function getGaugeZoneClass(zone: "good" | "moderate" | "poor"): string {
  switch (zone) {
    case "good":
      return "bg-emerald-500/20 dark:bg-emerald-500/30";
    case "moderate":
      return "bg-amber-500/20 dark:bg-amber-500/30";
    case "poor":
      return "bg-rose-500/20 dark:bg-rose-500/30";
  }
}

/** Get gauge fill gradient based on score */
export function getGaugeFillGradient(score: number): string {
  if (score >= 70) {
    return "from-emerald-500 to-emerald-400";
  }
  if (score >= 50) {
    return "from-amber-500 to-amber-400";
  }
  return "from-rose-500 to-rose-400";
}

export type DimensionKey = keyof typeof DIMENSION_CONFIGS;
