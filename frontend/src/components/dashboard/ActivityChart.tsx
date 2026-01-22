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
  sprintStart?: string;
  sprintEnd?: string;
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

// Format date as YYYY-MM-DD using local time (avoids timezone issues with toISOString)
function formatLocalDate(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

// Generate all dates between start and end (inclusive)
function generateDateRange(start: string, end: string): string[] {
  const dates: string[] = [];
  const current = new Date(start + "T00:00:00");
  const endDate = new Date(end + "T00:00:00");

  while (current <= endDate) {
    dates.push(formatLocalDate(current));
    current.setDate(current.getDate() + 1);
  }
  return dates;
}

// Fill missing dates with zero activity
function fillMissingDates(
  data: DailyActivity[],
  sprintStart?: string,
  sprintEnd?: string,
): DailyActivity[] {
  if (!sprintStart || !sprintEnd) return data;

  const allDates = generateDateRange(sprintStart, sprintEnd);
  const dataMap = new Map(data.map((d) => [d.date, d]));

  return allDates.map((date) => {
    const existing = dataMap.get(date);
    if (existing) return existing;
    return {
      date,
      commits: 0,
      prs_opened: 0,
      prs_merged: 0,
      reviews_given: 0,
    };
  });
}

export function ActivityChart({
  data,
  sprintStart,
  sprintEnd,
}: ActivityChartProps) {
  // Fill in the complete sprint date range
  const filledData = fillMissingDates(data, sprintStart, sprintEnd);

  if (!filledData.length) {
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
  const formattedData = filledData.map((d) => ({
    ...d,
    displayDate: new Date(d.date + "T00:00:00").toLocaleDateString("en-US", {
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
