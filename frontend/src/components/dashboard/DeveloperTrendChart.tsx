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
import type { DeveloperHistoryEntry, SprintHistoryEntry } from "@/types/metrics";

interface DeveloperTrendChartProps {
  developerData: DeveloperHistoryEntry[];
  teamData: SprintHistoryEntry[];
}

const chartConfig = {
  developer_dxi: {
    label: "Developer DXI",
    color: "oklch(0.55 0.2 250)",
  },
  team_dxi: {
    label: "Team Avg",
    color: "oklch(0.65 0.15 195)",
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

type DimensionKey = "review_speed" | "cycle_time" | "pr_size" | "review_coverage" | "commit_frequency";

const dimensionKeys: DimensionKey[] = [
  "review_speed",
  "cycle_time",
  "pr_size",
  "review_coverage",
  "commit_frequency",
];

export function DeveloperTrendChart({
  developerData,
  teamData,
}: DeveloperTrendChartProps) {
  // Track which lines are visible - DXI scores always on, dimensions start hidden
  const [visibleLines, setVisibleLines] = useState<Set<string>>(
    new Set(["developer_dxi", "team_dxi"])
  );

  const toggleLine = useCallback((key: string) => {
    // Don't allow toggling off the main developer DXI score
    if (key === "developer_dxi") return;

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
      const next = new Set<string>(["developer_dxi", "team_dxi"]);
      if (!hasAllDimensions) {
        dimensionKeys.forEach((k) => next.add(k));
      }
      return next;
    });
  }, []);

  if (!developerData.length) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>DXI Trend</CardTitle>
        </CardHeader>
        <CardContent className="flex items-center justify-center h-[350px] text-muted-foreground">
          No historical data available
        </CardContent>
      </Card>
    );
  }

  // Merge developer and team data for charting
  const chartData = developerData.map((dev, index) => {
    const team = teamData[index];
    return {
      sprint_label: dev.sprint_label,
      developer_dxi: dev.dxi_score,
      team_dxi: team?.avg_dxi_score ?? 0,
      review_speed: dev.dimension_scores.review_speed,
      cycle_time: dev.dimension_scores.cycle_time,
      pr_size: dev.dimension_scores.pr_size,
      review_coverage: dev.dimension_scores.review_coverage,
      commit_frequency: dev.dimension_scores.commit_frequency,
    };
  });

  // Calculate trend direction
  const firstScore = developerData[0]?.dxi_score ?? 0;
  const lastScore = developerData[developerData.length - 1]?.dxi_score ?? 0;
  const trend = lastScore - firstScore;
  const trendLabel = trend > 0 ? `+${trend.toFixed(1)}` : trend.toFixed(1);
  const trendColor = trend >= 0 ? "text-green-600" : "text-red-600";

  // Compare to team trend
  const teamFirstScore = teamData[0]?.avg_dxi_score ?? 0;
  const teamLastScore = teamData[teamData.length - 1]?.avg_dxi_score ?? 0;
  const teamTrend = teamLastScore - teamFirstScore;
  const outperforming = trend > teamTrend;

  const hasAllDimensions = dimensionKeys.every((k) => visibleLines.has(k));

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <div>
          <CardTitle>DXI Trend</CardTitle>
          <p className="text-sm text-muted-foreground mt-1">
            Trend:{" "}
            <span className={`font-semibold ${trendColor}`}>{trendLabel}</span>
            {developerData.length > 1 && (
              <span className="ml-2 text-xs">
                {outperforming ? "↑ Above team pace" : "↓ Below team pace"}
              </span>
            )}
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
            {/* Developer DXI Score line - always visible */}
            <Line
              type="monotone"
              dataKey="developer_dxi"
              stroke="var(--color-developer_dxi)"
              strokeWidth={3}
              dot={{ fill: "var(--color-developer_dxi)", r: 4 }}
              activeDot={{ r: 6 }}
            />
            {/* Team average line - toggleable */}
            <Line
              type="monotone"
              dataKey="team_dxi"
              stroke="var(--color-team_dxi)"
              strokeWidth={2}
              strokeDasharray="6 3"
              dot={false}
              hide={!visibleLines.has("team_dxi")}
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
          {/* Developer DXI Score - always active */}
          <div className="flex items-center gap-1.5">
            <div
              className="h-3 w-3 rounded-sm"
              style={{ backgroundColor: "var(--color-developer_dxi)" }}
            />
            <span className="text-sm font-medium">
              {chartConfig.developer_dxi.label}
            </span>
          </div>

          {/* Team average toggle */}
          <button
            onClick={() => toggleLine("team_dxi")}
            className={`flex items-center gap-1.5 transition-opacity ${
              visibleLines.has("team_dxi") ? "opacity-100" : "opacity-40 hover:opacity-70"
            }`}
          >
            <div
              className="h-3 w-3 rounded-sm"
              style={{ backgroundColor: "var(--color-team_dxi)" }}
            />
            <span className="text-sm">{chartConfig.team_dxi.label}</span>
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

          {/* Show/Hide all dimensions */}
          <button
            onClick={toggleAllDimensions}
            className={`flex items-center gap-1.5 transition-opacity ${
              hasAllDimensions ? "opacity-100" : "opacity-40 hover:opacity-70"
            }`}
          >
            <div className="h-3 w-3 rounded-sm bg-muted-foreground" />
            <span className="text-sm">{hasAllDimensions ? "Hide all" : "Show all"}</span>
          </button>
        </div>
      </CardContent>
    </Card>
  );
}
