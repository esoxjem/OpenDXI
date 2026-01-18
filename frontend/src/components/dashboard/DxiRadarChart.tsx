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
import type { DeveloperMetrics } from "@/types/metrics";

interface DxiRadarChartProps {
  developers: DeveloperMetrics[];
}

const chartConfig = {
  score: {
    label: "Score",
    color: "hsl(var(--primary))",
  },
} satisfies ChartConfig;

/**
 * Calculate team-level dimension scores for the radar chart.
 * These mirror the DXI scoring algorithm from the backend.
 */
function calculateDimensionScores(developers: DeveloperMetrics[]) {
  if (!developers.length) {
    return [
      { dimension: "Review Speed", score: 50 },
      { dimension: "Cycle Time", score: 50 },
      { dimension: "PR Size", score: 50 },
      { dimension: "Review Coverage", score: 50 },
      { dimension: "Commit Frequency", score: 50 },
    ];
  }

  const safeAvg = (values: (number | null)[]) => {
    const valid = values.filter((v): v is number => v !== null);
    return valid.length ? valid.reduce((a, b) => a + b, 0) / valid.length : 0;
  };

  const reviewTimes = developers.map((d) => d.avg_review_time_hours);
  const cycleTimes = developers.map((d) => d.avg_cycle_time_hours);
  const prSizes = developers.map(
    (d) => (d.lines_added + d.lines_deleted) / Math.max(d.prs_opened, 1)
  );
  const reviews = developers.map((d) => d.reviews_given);
  const commits = developers.map((d) => d.commits);

  const avgReviewTime = safeAvg(reviewTimes);
  const reviewScore = avgReviewTime
    ? Math.max(0, Math.min(100, 100 - (avgReviewTime - 2) * (100 / 22)))
    : 50;

  const avgCycleTime = safeAvg(cycleTimes);
  const cycleScore = avgCycleTime
    ? Math.max(0, Math.min(100, 100 - (avgCycleTime - 8) * (100 / 64)))
    : 50;

  const avgPrSize = safeAvg(prSizes);
  const sizeScore = Math.max(0, Math.min(100, 100 - (avgPrSize - 200) * (100 / 800)));

  const avgReviews = safeAvg(reviews);
  const reviewCovScore = Math.min(100, avgReviews * 10);

  const avgCommits = safeAvg(commits);
  const commitScore = Math.min(100, avgCommits * 5);

  return [
    { dimension: "Review Speed", score: Math.round(reviewScore) },
    { dimension: "Cycle Time", score: Math.round(cycleScore) },
    { dimension: "PR Size", score: Math.round(sizeScore) },
    { dimension: "Review Coverage", score: Math.round(reviewCovScore) },
    { dimension: "Commit Frequency", score: Math.round(commitScore) },
  ];
}

export function DxiRadarChart({ developers }: DxiRadarChartProps) {
  const radarData = calculateDimensionScores(developers);

  if (!developers.length) {
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
