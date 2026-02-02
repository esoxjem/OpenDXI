"use client";

import { motion } from "framer-motion";
import { cn } from "@/lib/utils";
import { GaugeBar } from "./GaugeBar";
import { LearnMoreExpand } from "./LearnMoreExpand";
import {
  DIMENSION_CONFIGS,
  getScoreColorClass,
  type DimensionKey,
} from "./dimension-config";

interface DimensionGaugeProps {
  /** Which dimension this gauge represents */
  dimension: DimensionKey;
  /** The score for this dimension (0-100) */
  score: number;
  /** Team average score for comparison */
  teamScore: number;
  /** Raw metric value (e.g., avg hours, count) */
  rawValue: number | null;
  /** Animation delay index for staggered animations */
  index?: number;
  /** Optional class name */
  className?: string;
}

/**
 * DimensionGauge - Complete gauge component with score visualization and explanations
 *
 * Combines:
 * - Dimension label with weight indicator
 * - Score display with team comparison
 * - Visual gauge bar showing position on threshold scale
 * - Raw metric value display
 * - Expandable learn more section with calculation details and tips
 */
export function DimensionGauge({
  dimension,
  score,
  teamScore,
  rawValue,
  index = 0,
  className,
}: DimensionGaugeProps) {
  const config = DIMENSION_CONFIGS[dimension];
  const diff = score - teamScore;
  const diffSign = diff >= 0 ? "+" : "";

  // Handle edge case: no data
  const hasData = rawValue !== null || score > 0;

  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{
        duration: 0.4,
        delay: index * 0.08,
        ease: [0.32, 0.72, 0, 1],
      }}
      className={cn(
        "relative p-4 rounded-lg",
        "bg-muted/30 hover:bg-muted/50 transition-colors",
        "border border-transparent hover:border-muted-foreground/10",
        className
      )}
    >
      {/* Header: Label, Weight, Score */}
      <div className="flex items-start justify-between mb-3">
        <div className="space-y-0.5">
          <h4 className="text-sm font-semibold text-foreground">
            {config.detailLabel}
          </h4>
          <span className="text-[10px] font-mono text-muted-foreground/60 uppercase tracking-wider">
            {config.weight}% weight
          </span>
        </div>

        <div className="flex items-baseline gap-3">
          {/* Team comparison */}
          <div className="text-right">
            <span className="text-[10px] text-muted-foreground/70 block mb-0.5">
              Team
            </span>
            <span className="text-xs font-mono text-muted-foreground">
              {teamScore.toFixed(0)}
            </span>
          </div>

          {/* Score and diff */}
          <div className="text-right">
            <span className="text-[10px] text-muted-foreground/70 block mb-0.5">
              You
            </span>
            <div className="flex items-baseline gap-1.5">
              <span
                className={cn(
                  "text-xl font-bold font-mono tabular-nums",
                  getScoreColorClass(score)
                )}
              >
                {hasData ? score.toFixed(0) : "--"}
              </span>
              {hasData && (
                <span
                  className={cn(
                    "text-xs font-mono",
                    diff >= 0
                      ? "text-emerald-500/80"
                      : "text-rose-500/80"
                  )}
                >
                  {diffSign}
                  {diff.toFixed(0)}
                </span>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Gauge visualization */}
      {hasData ? (
        <>
          <GaugeBar score={score} config={config} animate={true} />

          {/* Raw value display */}
          <div className="mt-3 flex items-center justify-between">
            <span className="text-xs text-muted-foreground">
              {config.formatRawValue(rawValue)}
            </span>

            {/* Threshold context */}
            <span className="text-[10px] font-mono text-muted-foreground/50">
              {config.inverseMetric ? "Lower is better" : "Higher is better"}
            </span>
          </div>

          {/* Learn more expansion */}
          <div className="mt-3 pt-3 border-t border-muted-foreground/10">
            <LearnMoreExpand
              config={config}
              rawValue={rawValue}
              score={score}
            />
          </div>
        </>
      ) : (
        /* No data state */
        <div className="py-6 text-center">
          <div className="text-2xl mb-2">📊</div>
          <p className="text-sm text-muted-foreground">No activity yet</p>
          <p className="text-xs text-muted-foreground/60 mt-1">
            {dimension === "review_speed"
              ? "Give some code reviews to see your score"
              : dimension === "cycle_time"
              ? "Open and merge some PRs to see your score"
              : dimension === "pr_size"
              ? "Open some PRs to see your score"
              : dimension === "review_coverage"
              ? "Review some PRs to see your score"
              : "Make some commits to see your score"}
          </p>
        </div>
      )}
    </motion.div>
  );
}

/**
 * Helper function to extract raw values from developer metrics
 * based on dimension key
 */
export function getRawValueForDimension(
  dimension: DimensionKey,
  metrics: {
    avg_review_time_hours: number | null;
    avg_cycle_time_hours: number | null;
    lines_added: number;
    lines_deleted: number;
    prs_opened: number;
    reviews_given: number;
    commits: number;
  }
): number | null {
  switch (dimension) {
    case "review_speed":
      return metrics.avg_review_time_hours;
    case "cycle_time":
      return metrics.avg_cycle_time_hours;
    case "pr_size":
      // Calculate avg lines per PR
      if (metrics.prs_opened === 0) return null;
      return (metrics.lines_added + metrics.lines_deleted) / metrics.prs_opened;
    case "review_coverage":
      return metrics.reviews_given;
    case "commit_frequency":
      return metrics.commits;
    default:
      return null;
  }
}
