"use client";

import { motion } from "framer-motion";
import { cn } from "@/lib/utils";
import type { DimensionConfig } from "./dimension-config";

interface GaugeBarProps {
  /** Score value 0-100 */
  score: number;
  /** Dimension configuration with thresholds */
  config: DimensionConfig;
  /** Whether to animate the fill on mount */
  animate?: boolean;
  /** Optional class name */
  className?: string;
}

/**
 * GaugeBar - A horizontal score visualization with color-coded zones
 *
 * Visual design:
 * - Three distinct zones (good/moderate/poor) shown as background segments
 * - Score indicator as a filled bar with gradient
 * - Threshold markers at zone boundaries
 * - Subtle grid pattern for technical aesthetic
 */
export function GaugeBar({
  score,
  config,
  animate = true,
  className,
}: GaugeBarProps) {
  const clampedScore = Math.max(0, Math.min(100, score));

  // Calculate zone boundaries (70 and 50 thresholds)
  const goodZoneStart = 70;
  const moderateZoneStart = 50;

  // Determine fill color based on score
  const getFillColor = () => {
    if (clampedScore >= 70) return "bg-gradient-to-r from-emerald-500 to-emerald-400";
    if (clampedScore >= 50) return "bg-gradient-to-r from-amber-500 to-amber-400";
    return "bg-gradient-to-r from-rose-500 to-rose-400";
  };

  // Get the glow color for the indicator
  const getGlowColor = () => {
    if (clampedScore >= 70) return "shadow-emerald-500/50";
    if (clampedScore >= 50) return "shadow-amber-500/50";
    return "shadow-rose-500/50";
  };

  return (
    <div className={cn("relative", className)} role="presentation">
      {/* Gauge track with zone backgrounds */}
      <div
        className="relative h-3 rounded-full overflow-hidden bg-muted/50"
        role="meter"
        aria-valuenow={clampedScore}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-label={`${config.detailLabel} score: ${clampedScore.toFixed(0)} out of 100`}
      >
        {/* Zone backgrounds - subtle color coding */}
        <div className="absolute inset-0 flex">
          {/* Poor zone: 0-50 */}
          <div
            className="h-full bg-rose-500/10 dark:bg-rose-500/20"
            style={{ width: `${moderateZoneStart}%` }}
          />
          {/* Moderate zone: 50-70 */}
          <div
            className="h-full bg-amber-500/10 dark:bg-amber-500/20"
            style={{ width: `${goodZoneStart - moderateZoneStart}%` }}
          />
          {/* Good zone: 70-100 */}
          <div
            className="h-full bg-emerald-500/10 dark:bg-emerald-500/20"
            style={{ width: `${100 - goodZoneStart}%` }}
          />
        </div>

        {/* Subtle grid pattern overlay for technical feel */}
        <div
          className="absolute inset-0 opacity-[0.03] dark:opacity-[0.05]"
          style={{
            backgroundImage: `repeating-linear-gradient(
              90deg,
              transparent,
              transparent 9px,
              currentColor 9px,
              currentColor 10px
            )`,
          }}
        />

        {/* Score fill bar */}
        <motion.div
          className={cn(
            "absolute top-0 left-0 h-full rounded-full",
            getFillColor()
          )}
          initial={animate ? { width: 0 } : { width: `${clampedScore}%` }}
          animate={{ width: `${clampedScore}%` }}
          transition={{
            duration: 0.6,
            ease: [0.32, 0.72, 0, 1], // Custom ease-out curve
            delay: 0.1,
          }}
        >
          {/* Shine effect on the fill */}
          <div className="absolute inset-0 rounded-full bg-gradient-to-b from-white/30 to-transparent" />
        </motion.div>

        {/* Score position indicator dot */}
        <motion.div
          className={cn(
            "absolute top-1/2 -translate-y-1/2 w-4 h-4 rounded-full border-2 border-background",
            getFillColor(),
            "shadow-lg",
            getGlowColor()
          )}
          initial={animate ? { left: 0, opacity: 0 } : { left: `calc(${clampedScore}% - 8px)`, opacity: 1 }}
          animate={{ left: `calc(${clampedScore}% - 8px)`, opacity: 1 }}
          transition={{
            duration: 0.6,
            ease: [0.32, 0.72, 0, 1],
            delay: 0.1,
          }}
        >
          {/* Inner highlight */}
          <div className="absolute inset-0.5 rounded-full bg-gradient-to-br from-white/40 to-transparent" />
        </motion.div>

        {/* Zone threshold markers */}
        <div
          className="absolute top-0 bottom-0 w-px bg-foreground/20"
          style={{ left: `${moderateZoneStart}%` }}
        />
        <div
          className="absolute top-0 bottom-0 w-px bg-foreground/20"
          style={{ left: `${goodZoneStart}%` }}
        />
      </div>

      {/* Zone labels below gauge */}
      <div className="flex justify-between mt-1.5 px-0.5">
        <div className="flex items-center gap-1">
          <span className="text-[10px] font-mono text-muted-foreground/70">0</span>
        </div>
        <div className="flex gap-4 text-[10px] font-medium">
          <span className="text-rose-500/70 dark:text-rose-400/70">Needs work</span>
          <span className="text-amber-500/70 dark:text-amber-400/70">Moderate</span>
          <span className="text-emerald-500/70 dark:text-emerald-400/70">Good</span>
        </div>
        <div className="flex items-center gap-1">
          <span className="text-[10px] font-mono text-muted-foreground/70">100</span>
        </div>
      </div>
    </div>
  );
}
