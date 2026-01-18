"use client";

import { Card, CardContent } from "@/components/ui/card";
import { motion } from "framer-motion";
import {
  ChartContainer,
  type ChartConfig,
} from "@/components/ui/chart";
import { Area, AreaChart } from "recharts";

interface KpiCardProps {
  title: string;
  value: string;
  sparklineData?: number[];
  index?: number;
}

const chartConfig = {
  value: {
    color: "hsl(var(--primary))",
  },
} satisfies ChartConfig;

export function KpiCard({ title, value, sparklineData, index = 0 }: KpiCardProps) {
  // Transform sparkline data to chart format
  const chartData = sparklineData?.map((v, i) => ({ index: i, value: v })) || [];

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
          </div>
          {chartData.length > 1 && (
            <ChartContainer config={chartConfig} className="h-[40px] w-full mt-2">
              <AreaChart data={chartData}>
                <defs>
                  <linearGradient id={`gradient-${title}`} x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="hsl(var(--primary))" stopOpacity={0.3} />
                    <stop offset="100%" stopColor="hsl(var(--primary))" stopOpacity={0} />
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
