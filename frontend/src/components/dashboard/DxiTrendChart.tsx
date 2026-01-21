"use client";

import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
  ChartLegend,
  ChartLegendContent,
  type ChartConfig,
} from "@/components/ui/chart";
import { Line, LineChart, XAxis, YAxis, ReferenceLine } from "recharts";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import type { SprintHistoryEntry } from "@/types/metrics";

interface DxiTrendChartProps {
  data: SprintHistoryEntry[];
}

const chartConfig = {
  avg_dxi_score: {
    label: "DXI Score",
    color: "hsl(210, 70%, 55%)",
  },
  review_speed: {
    label: "Review Speed",
    color: "hsl(142, 60%, 50%)",
  },
  cycle_time: {
    label: "Cycle Time",
    color: "hsl(280, 60%, 55%)",
  },
  pr_size: {
    label: "PR Size",
    color: "hsl(25, 80%, 55%)",
  },
  review_coverage: {
    label: "Review Coverage",
    color: "hsl(340, 70%, 55%)",
  },
  commit_frequency: {
    label: "Commit Frequency",
    color: "hsl(180, 60%, 45%)",
  },
} satisfies ChartConfig;

export function DxiTrendChart({ data }: DxiTrendChartProps) {
  const [showDimensions, setShowDimensions] = useState(false);

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
    developer_count: sprint.developer_count,
    total_commits: sprint.total_commits,
    total_prs: sprint.total_prs,
  }));

  // Calculate trend direction
  const firstScore = data[0]?.avg_dxi_score ?? 0;
  const lastScore = data[data.length - 1]?.avg_dxi_score ?? 0;
  const trend = lastScore - firstScore;
  const trendLabel = trend > 0 ? `+${trend.toFixed(1)}` : trend.toFixed(1);
  const trendColor = trend >= 0 ? "text-green-600" : "text-red-600";

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
        <div className="flex items-center space-x-2">
          <Switch
            id="show-dimensions"
            checked={showDimensions}
            onCheckedChange={setShowDimensions}
          />
          <Label htmlFor="show-dimensions" className="text-sm">
            Show dimensions
          </Label>
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
              stroke="hsl(142, 60%, 50%)"
              strokeDasharray="3 3"
              strokeOpacity={0.5}
            />
            <ReferenceLine
              y={50}
              stroke="hsl(45, 80%, 50%)"
              strokeDasharray="3 3"
              strokeOpacity={0.5}
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
            <ChartLegend content={<ChartLegendContent />} />
            {/* Main DXI Score line - always visible */}
            <Line
              type="monotone"
              dataKey="avg_dxi_score"
              stroke="hsl(210, 70%, 55%)"
              strokeWidth={3}
              dot={{ fill: "hsl(210, 70%, 55%)", r: 4 }}
              activeDot={{ r: 6 }}
            />
            {/* Dimension lines - toggleable */}
            {showDimensions && (
              <>
                <Line
                  type="monotone"
                  dataKey="review_speed"
                  stroke="hsl(142, 60%, 50%)"
                  strokeWidth={1.5}
                  strokeDasharray="4 2"
                  dot={false}
                />
                <Line
                  type="monotone"
                  dataKey="cycle_time"
                  stroke="hsl(280, 60%, 55%)"
                  strokeWidth={1.5}
                  strokeDasharray="4 2"
                  dot={false}
                />
                <Line
                  type="monotone"
                  dataKey="pr_size"
                  stroke="hsl(25, 80%, 55%)"
                  strokeWidth={1.5}
                  strokeDasharray="4 2"
                  dot={false}
                />
                <Line
                  type="monotone"
                  dataKey="review_coverage"
                  stroke="hsl(340, 70%, 55%)"
                  strokeWidth={1.5}
                  strokeDasharray="4 2"
                  dot={false}
                />
                <Line
                  type="monotone"
                  dataKey="commit_frequency"
                  stroke="hsl(180, 60%, 45%)"
                  strokeWidth={1.5}
                  strokeDasharray="4 2"
                  dot={false}
                />
              </>
            )}
          </LineChart>
        </ChartContainer>
      </CardContent>
    </Card>
  );
}
