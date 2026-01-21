/**
 * TypeScript interfaces for OpenDXI Dashboard metrics.
 *
 * These types mirror the Pydantic models in the FastAPI backend
 * to ensure type-safe communication between frontend and backend.
 */

export interface DimensionScores {
  review_speed: number;
  cycle_time: number;
  pr_size: number;
  review_coverage: number;
  commit_frequency: number;
}

export interface DeveloperMetrics {
  developer: string;
  commits: number;
  prs_opened: number;
  prs_merged: number;
  reviews_given: number;
  lines_added: number;
  lines_deleted: number;
  avg_review_time_hours: number | null;
  avg_cycle_time_hours: number | null;
  dxi_score: number;
  dimension_scores: DimensionScores;
}

export interface DailyActivity {
  date: string;
  commits: number;
  prs_opened: number;
  prs_merged: number;
  reviews_given: number;
}

export interface MetricsSummary {
  total_commits: number;
  total_prs: number;
  total_merged: number;
  total_reviews: number;
  avg_dxi_score: number;
}

export interface MetricsResponse {
  developers: DeveloperMetrics[];
  daily: DailyActivity[];
  summary: MetricsSummary;
  team_dimension_scores: DimensionScores;
}

export interface Sprint {
  label: string;
  value: string;
  start: string;
  end: string;
  is_current: boolean;
}

export interface SprintListResponse {
  sprints: Sprint[];
}

/** Sort options for the leaderboard */
export type SortKey = "dxi_score" | "commits" | "prs_opened" | "reviews_given";

/** Application configuration from backend */
export interface ConfigResponse {
  github_org: string;
}

/** Single sprint entry for historical trend analysis */
export interface SprintHistoryEntry {
  sprint_label: string;
  start_date: string;
  end_date: string;
  avg_dxi_score: number;
  dimension_scores: DimensionScores;
  developer_count: number;
  total_commits: number;
  total_prs: number;
}

/** Historical DXI scores across multiple sprints */
export interface SprintHistoryResponse {
  sprints: SprintHistoryEntry[];
}
