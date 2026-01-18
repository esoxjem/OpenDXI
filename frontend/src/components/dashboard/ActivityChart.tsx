"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
  ChartLegend,
  ChartLegendContent,
  type ChartConfig,
} from "@/components/ui/chart";
import { Area, AreaChart, XAxis, YAxis } from "recharts";
import type { DailyActivity } from "@/types/metrics";

interface ActivityChartProps {
  data: DailyActivity[];
}

const chartConfig = {
  commits: {
    label: "Commits",
    color: "hsl(210, 70%, 55%)",
  },
  prs_merged: {
    label: "PRs Merged",
    color: "hsl(142, 60%, 50%)",
  },
  reviews_given: {
    label: "Reviews",
    color: "hsl(280, 60%, 55%)",
  },
} satisfies ChartConfig;

export function ActivityChart({ data }: ActivityChartProps) {
  if (!data.length) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Activity Timeline</CardTitle>
        </CardHeader>
        <CardContent className="flex items-center justify-center h-[300px] text-muted-foreground">
          No activity data available
        </CardContent>
      </Card>
    );
  }

  // Format date for display
  const formattedData = data.map((d) => ({
    ...d,
    displayDate: new Date(d.date).toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
    }),
  }));

  return (
    <Card>
      <CardHeader>
        <CardTitle>Activity Timeline</CardTitle>
      </CardHeader>
      <CardContent>
        <ChartContainer config={chartConfig} className="h-[300px] w-full">
          <AreaChart data={formattedData}>
            <defs>
              <linearGradient id="fillCommits" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="hsl(210, 70%, 55%)" stopOpacity={0.3} />
                <stop offset="100%" stopColor="hsl(210, 70%, 55%)" stopOpacity={0} />
              </linearGradient>
              <linearGradient id="fillPrs" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="hsl(142, 60%, 50%)" stopOpacity={0.3} />
                <stop offset="100%" stopColor="hsl(142, 60%, 50%)" stopOpacity={0} />
              </linearGradient>
              <linearGradient id="fillReviews" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="hsl(280, 60%, 55%)" stopOpacity={0.3} />
                <stop offset="100%" stopColor="hsl(280, 60%, 55%)" stopOpacity={0} />
              </linearGradient>
            </defs>
            <XAxis
              dataKey="displayDate"
              tickLine={false}
              axisLine={false}
              tickMargin={8}
            />
            <YAxis tickLine={false} axisLine={false} tickMargin={8} />
            <ChartTooltip content={<ChartTooltipContent />} />
            <ChartLegend content={<ChartLegendContent />} />
            <Area
              type="monotone"
              dataKey="commits"
              stroke="hsl(210, 70%, 55%)"
              strokeWidth={2}
              fill="url(#fillCommits)"
              stackId="1"
            />
            <Area
              type="monotone"
              dataKey="prs_merged"
              stroke="hsl(142, 60%, 50%)"
              strokeWidth={2}
              fill="url(#fillPrs)"
              stackId="1"
            />
            <Area
              type="monotone"
              dataKey="reviews_given"
              stroke="hsl(280, 60%, 55%)"
              strokeWidth={2}
              fill="url(#fillReviews)"
              stackId="1"
            />
          </AreaChart>
        </ChartContainer>
      </CardContent>
    </Card>
  );
}
