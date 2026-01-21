"use client";

import { Card, CardContent } from "@/components/ui/card";
import { motion } from "framer-motion";
import { ChartContainer, type ChartConfig } from "@/components/ui/chart";
import { Area, AreaChart } from "recharts";
import { TrendingUp, TrendingDown, Minus } from "lucide-react";

interface KpiCardProps {
  title: string;
  value: string;
  sparklineData?: number[];
  index?: number;
  /** Previous value for trend calculation */
  previousValue?: number;
  /** Current numeric value for trend calculation */
  currentValue?: number;
  /** Unit suffix for trend display (e.g., "h" for hours, "%" for percentage) */
  trendUnit?: string;
  /** If true, lower values are better (e.g., cycle time) */
  invertTrend?: boolean;
}

const chartConfig = {
  value: {
    color: "hsl(var(--primary))",
  },
} satisfies ChartConfig;

export function KpiCard({
  title,
  value,
  sparklineData,
  index = 0,
  previousValue,
  currentValue,
  trendUnit = "",
  invertTrend = false,
}: KpiCardProps) {
  // Transform sparkline data to chart format
  const chartData =
    sparklineData?.map((v, i) => ({ index: i, value: v })) || [];

  // Calculate trend if both values are provided
  const hasTrend =
    previousValue !== undefined &&
    currentValue !== undefined &&
    previousValue !== 0;

  let trendDelta: number | null = null;
  let trendDirection: "up" | "down" | "neutral" = "neutral";

  if (hasTrend) {
    trendDelta = currentValue - previousValue;

    if (Math.abs(trendDelta) < 0.1) {
      trendDirection = "neutral";
    } else if (trendDelta > 0) {
      trendDirection = "up";
    } else {
      trendDirection = "down";
    }
  }

  // Determine if trend is positive (green) or negative (red)
  // For inverted metrics (like cycle time), down is good
  const isPositive =
    trendDirection === "neutral"
      ? null
      : invertTrend
        ? trendDirection === "down"
        : trendDirection === "up";

  const trendColorClass =
    isPositive === null
      ? "text-muted-foreground"
      : isPositive
        ? "text-green-600 dark:text-green-500"
        : "text-red-600 dark:text-red-500";

  const TrendIcon =
    trendDirection === "up"
      ? TrendingUp
      : trendDirection === "down"
        ? TrendingDown
        : Minus;

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4, delay: index * 0.1 }}
    >
      <Card className="h-full">
        <CardContent className="py-4">
          <p className="text-sm text-muted-foreground mb-1">{title}</p>
          <div className="flex items-baseline gap-2">
            <h3 className="text-2xl font-bold">{value}</h3>
            {hasTrend && trendDelta !== null && (
              <div
                className={`flex items-center gap-0.5 text-xs ${trendColorClass}`}
              >
                <TrendIcon className="h-3 w-3" />
                <span>
                  {trendDelta > 0 ? "+" : ""}
                  {Math.abs(trendDelta) < 10
                    ? trendDelta.toFixed(1)
                    : Math.round(trendDelta)}
                  {trendUnit}
                </span>
              </div>
            )}
          </div>
          {chartData.length > 1 && (
            <ChartContainer
              config={chartConfig}
              className="h-[40px] w-full mt-2"
            >
              <AreaChart data={chartData}>
                <defs>
                  <linearGradient
                    id={`gradient-${title}`}
                    x1="0"
                    y1="0"
                    x2="0"
                    y2="1"
                  >
                    <stop
                      offset="0%"
                      stopColor="hsl(var(--primary))"
                      stopOpacity={0.3}
                    />
                    <stop
                      offset="100%"
                      stopColor="hsl(var(--primary))"
                      stopOpacity={0}
                    />
                  </linearGradient>
                </defs>
                <Area
                  type="monotone"
                  dataKey="value"
                  stroke="hsl(var(--primary))"
                  strokeWidth={2}
                  fill={`url(#gradient-${title})`}
                />
              </AreaChart>
            </ChartContainer>
          )}
        </CardContent>
      </Card>
    </motion.div>
  );
}
