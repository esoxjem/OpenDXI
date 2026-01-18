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
  Legend,
} from "recharts";
import type { DimensionScores } from "@/types/metrics";

interface DxiRadarChartProps {
  teamDimensionScores: DimensionScores | undefined;
  developerScores?: DimensionScores;
}

const chartConfig = {
  team: {
    label: "Team",
    color: "hsl(var(--primary))",
  },
  developer: {
    label: "Developer",
    color: "hsl(var(--chart-2))",
  },
} satisfies ChartConfig;

/**
 * Convert server-provided dimension scores to radar chart format.
 * When developerScores is provided, includes both team and developer data.
 */
function formatForRadarChart(
  teamScores: DimensionScores | undefined,
  developerScores?: DimensionScores
) {
  if (!teamScores) {
    return [
      { dimension: "Review Speed", team: 50, developer: 50 },
      { dimension: "Cycle Time", team: 50, developer: 50 },
      { dimension: "PR Size", team: 50, developer: 50 },
      { dimension: "Review Coverage", team: 50, developer: 50 },
      { dimension: "Commit Frequency", team: 50, developer: 50 },
    ];
  }

  return [
    {
      dimension: "Review Speed",
      team: Math.round(teamScores.review_speed),
      developer: developerScores ? Math.round(developerScores.review_speed) : undefined,
    },
    {
      dimension: "Cycle Time",
      team: Math.round(teamScores.cycle_time),
      developer: developerScores ? Math.round(developerScores.cycle_time) : undefined,
    },
    {
      dimension: "PR Size",
      team: Math.round(teamScores.pr_size),
      developer: developerScores ? Math.round(developerScores.pr_size) : undefined,
    },
    {
      dimension: "Review Coverage",
      team: Math.round(teamScores.review_coverage),
      developer: developerScores ? Math.round(developerScores.review_coverage) : undefined,
    },
    {
      dimension: "Commit Frequency",
      team: Math.round(teamScores.commit_frequency),
      developer: developerScores ? Math.round(developerScores.commit_frequency) : undefined,
    },
  ];
}

export function DxiRadarChart({ teamDimensionScores, developerScores }: DxiRadarChartProps) {
  const radarData = formatForRadarChart(teamDimensionScores, developerScores);
  const isComparison = !!developerScores;

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
        <CardTitle>
          {isComparison ? "Developer vs Team" : "DXI Dimensions"}
        </CardTitle>
      </CardHeader>
      <CardContent>
        <ChartContainer config={chartConfig} className="h-[300px] w-full">
          <RadarChart data={radarData}>
            <PolarGrid />
            <PolarAngleAxis dataKey="dimension" tick={{ fontSize: 11 }} />
            <PolarRadiusAxis angle={30} domain={[0, 100]} tick={{ fontSize: 10 }} />
            <ChartTooltip content={<ChartTooltipContent />} />
            <Radar
              name="Team"
              dataKey="team"
              stroke="hsl(var(--primary))"
              fill="hsl(var(--primary))"
              fillOpacity={isComparison ? 0.15 : 0.3}
              strokeWidth={2}
            />
            {isComparison && (
              <Radar
                name="Developer"
                dataKey="developer"
                stroke="hsl(var(--chart-2))"
                fill="hsl(var(--chart-2))"
                fillOpacity={0.3}
                strokeWidth={2}
              />
            )}
            {isComparison && <Legend />}
          </RadarChart>
        </ChartContainer>
      </CardContent>
    </Card>
  );
}
