"use client";

import { useState, useCallback } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart";
import { Line, LineChart, XAxis, YAxis, ReferenceLine } from "recharts";
import type { SprintHistoryEntry } from "@/types/metrics";

interface DxiTrendChartProps {
  data: SprintHistoryEntry[];
}

const chartConfig = {
  avg_dxi_score: {
    label: "DXI Score",
    color: "oklch(0.55 0.2 250)",
  },
  review_speed: {
    label: "Review Speed",
    color: "oklch(0.65 0.2 145)",
  },
  cycle_time: {
    label: "Cycle Time",
    color: "oklch(0.55 0.2 300)",
  },
  pr_size: {
    label: "PR Size",
    color: "oklch(0.7 0.2 55)",
  },
  review_coverage: {
    label: "Review Coverage",
    color: "oklch(0.6 0.2 10)",
  },
  commit_frequency: {
    label: "Commit Frequency",
    color: "oklch(0.6 0.15 195)",
  },
} satisfies ChartConfig;

type DimensionKey = keyof typeof chartConfig;

const dimensionKeys: DimensionKey[] = [
  "review_speed",
  "cycle_time",
  "pr_size",
  "review_coverage",
  "commit_frequency",
];

export function DxiTrendChart({ data }: DxiTrendChartProps) {
  // Track which lines are visible - DXI Score always on, dimensions start hidden
  const [visibleLines, setVisibleLines] = useState<Set<DimensionKey>>(
    new Set(["avg_dxi_score"])
  );

  const toggleLine = useCallback((key: DimensionKey) => {
    // Don't allow toggling off the main DXI score
    if (key === "avg_dxi_score") return;

    setVisibleLines((prev) => {
      const next = new Set(prev);
      if (next.has(key)) {
        next.delete(key);
      } else {
        next.add(key);
      }
      return next;
    });
  }, []);

  const toggleAllDimensions = useCallback(() => {
    setVisibleLines((prev) => {
      const hasAllDimensions = dimensionKeys.every((k) => prev.has(k));
      const next = new Set<DimensionKey>(["avg_dxi_score"]);
      if (!hasAllDimensions) {
        dimensionKeys.forEach((k) => next.add(k));
      }
      return next;
    });
  }, []);

  if (!data.length) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>DXI Score Trend</CardTitle>
        </CardHeader>
        <CardContent className="flex items-center justify-center h-[350px] text-muted-foreground">
          No historical data available
        </CardContent>
      </Card>
    );
  }

  // Transform data for charting - flatten dimension scores into top level
  const chartData = data.map((sprint) => ({
    sprint_label: sprint.sprint_label,
    avg_dxi_score: sprint.avg_dxi_score,
    review_speed: sprint.dimension_scores.review_speed,
    cycle_time: sprint.dimension_scores.cycle_time,
    pr_size: sprint.dimension_scores.pr_size,
    review_coverage: sprint.dimension_scores.review_coverage,
    commit_frequency: sprint.dimension_scores.commit_frequency,
  }));

  // Calculate trend direction
  const firstScore = data[0]?.avg_dxi_score ?? 0;
  const lastScore = data[data.length - 1]?.avg_dxi_score ?? 0;
  const trend = lastScore - firstScore;
  const trendLabel = trend > 0 ? `+${trend.toFixed(1)}` : trend.toFixed(1);
  const trendColor = trend >= 0 ? "text-green-600" : "text-red-600";

  const hasAllDimensions = dimensionKeys.every((k) => visibleLines.has(k));
  const hasNoDimensions = !dimensionKeys.some((k) => visibleLines.has(k));

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <div>
          <CardTitle>DXI Score Trend</CardTitle>
          <p className="text-sm text-muted-foreground mt-1">
            Overall trend:{" "}
            <span className={`font-semibold ${trendColor}`}>{trendLabel}</span>
          </p>
        </div>
      </CardHeader>
      <CardContent>
        <ChartContainer config={chartConfig} className="h-[350px] w-full">
          <LineChart data={chartData}>
            <XAxis
              dataKey="sprint_label"
              tickLine={false}
              axisLine={false}
              tickMargin={8}
            />
            <YAxis
              tickLine={false}
              axisLine={false}
              tickMargin={8}
              domain={[0, 100]}
              ticks={[0, 25, 50, 75, 100]}
            />
            {/* Reference lines for score thresholds */}
            <ReferenceLine
              y={70}
              stroke="oklch(0.65 0.2 145)"
              strokeDasharray="3 3"
              strokeOpacity={0.3}
            />
            <ReferenceLine
              y={50}
              stroke="oklch(0.8 0.15 85)"
              strokeDasharray="3 3"
              strokeOpacity={0.3}
            />
            <ChartTooltip
              content={
                <ChartTooltipContent
                  formatter={(value, name) => {
                    const config = chartConfig[name as keyof typeof chartConfig];
                    return (
                      <span>
                        {config?.label ?? name}: {Number(value).toFixed(1)}
                      </span>
                    );
                  }}
                />
              }
            />
            {/* Main DXI Score line - always visible */}
            <Line
              type="monotone"
              dataKey="avg_dxi_score"
              stroke="var(--color-avg_dxi_score)"
              strokeWidth={3}
              dot={{ fill: "var(--color-avg_dxi_score)", r: 4 }}
              activeDot={{ r: 6 }}
            />
            {/* Dimension lines - individually toggleable */}
            <Line
              type="monotone"
              dataKey="review_speed"
              stroke="var(--color-review_speed)"
              strokeWidth={1.5}
              strokeDasharray="4 2"
              dot={false}
              hide={!visibleLines.has("review_speed")}
            />
            <Line
              type="monotone"
              dataKey="cycle_time"
              stroke="var(--color-cycle_time)"
              strokeWidth={1.5}
              strokeDasharray="4 2"
              dot={false}
              hide={!visibleLines.has("cycle_time")}
            />
            <Line
              type="monotone"
              dataKey="pr_size"
              stroke="var(--color-pr_size)"
              strokeWidth={1.5}
              strokeDasharray="4 2"
              dot={false}
              hide={!visibleLines.has("pr_size")}
            />
            <Line
              type="monotone"
              dataKey="review_coverage"
              stroke="var(--color-review_coverage)"
              strokeWidth={1.5}
              strokeDasharray="4 2"
              dot={false}
              hide={!visibleLines.has("review_coverage")}
            />
            <Line
              type="monotone"
              dataKey="commit_frequency"
              stroke="var(--color-commit_frequency)"
              strokeWidth={1.5}
              strokeDasharray="4 2"
              dot={false}
              hide={!visibleLines.has("commit_frequency")}
            />
          </LineChart>
        </ChartContainer>

        {/* Interactive Legend */}
        <div className="flex flex-wrap items-center justify-center gap-4 pt-4">
          {/* DXI Score - always active */}
          <div className="flex items-center gap-1.5">
            <div
              className="h-3 w-3 rounded-sm"
              style={{ backgroundColor: "var(--color-avg_dxi_score)" }}
            />
            <span className="text-sm font-medium">
              {chartConfig.avg_dxi_score.label}
            </span>
          </div>

          {/* Toggle all dimensions */}
          <button
            onClick={toggleAllDimensions}
            className="text-xs text-muted-foreground hover:text-foreground underline-offset-2 hover:underline"
          >
            {hasAllDimensions ? "Hide all" : hasNoDimensions ? "Show all" : "Toggle all"}
          </button>

          {/* Dimension toggles */}
          {dimensionKeys.map((key) => {
            const config = chartConfig[key];
            const isActive = visibleLines.has(key);
            return (
              <button
                key={key}
                onClick={() => toggleLine(key)}
                className={`flex items-center gap-1.5 transition-opacity ${
                  isActive ? "opacity-100" : "opacity-40 hover:opacity-70"
                }`}
              >
                <div
                  className="h-3 w-3 rounded-sm"
                  style={{ backgroundColor: `var(--color-${key})` }}
                />
                <span className="text-sm">{config.label}</span>
              </button>
            );
          })}
        </div>
      </CardContent>
    </Card>
  );
}
