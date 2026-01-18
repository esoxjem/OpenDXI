"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart";
import {
  RadarChart,
  PolarGrid,
  PolarAngleAxis,
  PolarRadiusAxis,
  Radar,
} from "recharts";
import type { DimensionScores } from "@/types/metrics";

interface DxiRadarChartProps {
  teamDimensionScores: DimensionScores | undefined;
}

const chartConfig = {
  score: {
    label: "Score",
    color: "hsl(var(--primary))",
  },
} satisfies ChartConfig;

/**
 * Convert server-provided dimension scores to radar chart format.
 */
function formatForRadarChart(scores: DimensionScores | undefined) {
  if (!scores) {
    return [
      { dimension: "Review Speed", score: 50 },
      { dimension: "Cycle Time", score: 50 },
      { dimension: "PR Size", score: 50 },
      { dimension: "Review Coverage", score: 50 },
      { dimension: "Commit Frequency", score: 50 },
    ];
  }

  return [
    { dimension: "Review Speed", score: Math.round(scores.review_speed) },
    { dimension: "Cycle Time", score: Math.round(scores.cycle_time) },
    { dimension: "PR Size", score: Math.round(scores.pr_size) },
    { dimension: "Review Coverage", score: Math.round(scores.review_coverage) },
    { dimension: "Commit Frequency", score: Math.round(scores.commit_frequency) },
  ];
}

export function DxiRadarChart({ teamDimensionScores }: DxiRadarChartProps) {
  const radarData = formatForRadarChart(teamDimensionScores);

  if (!teamDimensionScores) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>DXI Dimensions</CardTitle>
        </CardHeader>
        <CardContent className="flex items-center justify-center h-[300px] text-muted-foreground">
          No data available
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>DXI Dimensions</CardTitle>
      </CardHeader>
      <CardContent>
        <ChartContainer config={chartConfig} className="h-[300px] w-full">
          <RadarChart data={radarData}>
            <PolarGrid />
            <PolarAngleAxis dataKey="dimension" tick={{ fontSize: 11 }} />
            <PolarRadiusAxis angle={30} domain={[0, 100]} tick={{ fontSize: 10 }} />
            <ChartTooltip content={<ChartTooltipContent />} />
            <Radar
              name="Score"
              dataKey="score"
              stroke="hsl(var(--primary))"
              fill="hsl(var(--primary))"
              fillOpacity={0.3}
              strokeWidth={2}
            />
          </RadarChart>
        </ChartContainer>
      </CardContent>
    </Card>
  );
}
