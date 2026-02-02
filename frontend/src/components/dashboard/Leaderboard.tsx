"use client";

import { useState, useMemo } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { ColumnTooltip } from "./components/ColumnTooltip";
import { LEADERBOARD_TOOLTIPS } from "./components/dimension-config";
import type { DeveloperMetrics, SortKey } from "@/types/metrics";

interface LeaderboardProps {
  developers: DeveloperMetrics[];
  onSelectDeveloper?: (developerName: string) => void;
}

const sortButtons: { key: SortKey; label: string }[] = [
  { key: "dxi_score", label: "DXI" },
  { key: "commits", label: "Commits" },
  { key: "prs_opened", label: "PRs" },
  { key: "reviews_given", label: "Reviews" },
];

function getDxiBadgeVariant(score: number): "default" | "secondary" | "destructive" {
  if (score >= 70) return "default";
  if (score >= 50) return "secondary";
  return "destructive";
}

export function Leaderboard({ developers, onSelectDeveloper }: LeaderboardProps) {
  const [sortKey, setSortKey] = useState<SortKey>("dxi_score");

  const sortedDevelopers = useMemo(() => {
    return [...developers].sort((a, b) => {
      const aVal = a[sortKey] ?? 0;
      const bVal = b[sortKey] ?? 0;
      return bVal - aVal;
    });
  }, [developers, sortKey]);

  if (!developers.length) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Developer Leaderboard</CardTitle>
        </CardHeader>
        <CardContent className="flex items-center justify-center h-[200px] text-muted-foreground">
          No data available
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0">
        <CardTitle>Developer Leaderboard</CardTitle>
        <div className="flex gap-1">
          {sortButtons.map(({ key, label }) => (
            <Button
              key={key}
              variant={sortKey === key ? "default" : "outline"}
              size="sm"
              onClick={() => setSortKey(key)}
            >
              {label}
            </Button>
          ))}
        </div>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-12">Rank</TableHead>
              <TableHead>Developer</TableHead>
              <TableHead className="text-center">
                <ColumnTooltip
                  label="DXI Score"
                  tooltip={LEADERBOARD_TOOLTIPS.dxi_score}
                />
              </TableHead>
              <TableHead className="text-center">
                <ColumnTooltip
                  label="Commits"
                  tooltip={LEADERBOARD_TOOLTIPS.commits}
                />
              </TableHead>
              <TableHead className="text-center">
                <ColumnTooltip
                  label="PRs"
                  tooltip={LEADERBOARD_TOOLTIPS.prs}
                />
              </TableHead>
              <TableHead className="text-center">
                <ColumnTooltip
                  label="Reviews"
                  tooltip={LEADERBOARD_TOOLTIPS.reviews}
                />
              </TableHead>
              <TableHead className="text-center">
                <ColumnTooltip
                  label="Cycle Time"
                  tooltip={LEADERBOARD_TOOLTIPS.cycle_time}
                />
              </TableHead>
              <TableHead className="text-right">
                <ColumnTooltip
                  label="Lines Changed"
                  tooltip={LEADERBOARD_TOOLTIPS.lines_changed}
                />
              </TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <AnimatePresence mode="popLayout">
              {sortedDevelopers.map((dev, index) => {
                const cycleTime = dev.avg_cycle_time_hours;
                const cycleStr = cycleTime ? `${cycleTime.toFixed(1)}h` : "--";
                const lines = dev.lines_added + dev.lines_deleted;

                return (
                  <motion.tr
                    key={dev.developer}
                    layout
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 0.3 }}
                    className={`border-b transition-colors hover:bg-muted/50 ${
                      onSelectDeveloper ? "cursor-pointer" : ""
                    }`}
                    onClick={() => onSelectDeveloper?.(dev.developer)}
                  >
                    <TableCell className="font-medium">{index + 1}</TableCell>
                    <TableCell className="font-medium">{dev.developer}</TableCell>
                    <TableCell className="text-center">
                      <Badge variant={getDxiBadgeVariant(dev.dxi_score)}>
                        {dev.dxi_score.toFixed(0)}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-center">{dev.commits}</TableCell>
                    <TableCell className="text-center">
                      {dev.prs_merged}/{dev.prs_opened}
                    </TableCell>
                    <TableCell className="text-center">{dev.reviews_given}</TableCell>
                    <TableCell className="text-center">{cycleStr}</TableCell>
                    <TableCell className="text-right">{lines.toLocaleString()}</TableCell>
                  </motion.tr>
                );
              })}
            </AnimatePresence>
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
