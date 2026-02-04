"use client";

import { useState, useMemo, useCallback } from "react";
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
import { ChevronRight } from "lucide-react";
import { ColumnTooltip } from "./components/ColumnTooltip";
import {
  DIMENSION_CONFIGS,
  LEADERBOARD_TOOLTIPS,
  getScoreColorClass,
} from "./components/dimension-config";
import type { DeveloperMetrics, SortKey, DimensionScores } from "@/types/metrics";

interface LeaderboardProps {
  developers: DeveloperMetrics[];
  onSelectDeveloper?: (developerName: string) => void;
}

const sortButtons: { key: SortKey; label: string }[] = [
  { key: "dxi_score", label: "DXI" },
  { key: "review_speed", label: DIMENSION_CONFIGS.review_speed.label },
  { key: "cycle_time", label: DIMENSION_CONFIGS.cycle_time.label },
  { key: "pr_size", label: DIMENSION_CONFIGS.pr_size.label },
  { key: "review_coverage", label: DIMENSION_CONFIGS.review_coverage.label },
  { key: "commit_frequency", label: DIMENSION_CONFIGS.commit_frequency.label },
];

const dimensionColumns: { key: keyof DimensionScores; label: string }[] = [
  { key: "review_speed", label: DIMENSION_CONFIGS.review_speed.label },
  { key: "cycle_time", label: DIMENSION_CONFIGS.cycle_time.label },
  { key: "pr_size", label: DIMENSION_CONFIGS.pr_size.label },
  { key: "review_coverage", label: DIMENSION_CONFIGS.review_coverage.label },
  { key: "commit_frequency", label: DIMENSION_CONFIGS.commit_frequency.label },
];

function getDxiBadgeVariant(score: number): "default" | "secondary" | "destructive" {
  if (score >= 70) return "default";
  if (score >= 50) return "secondary";
  return "destructive";
}

function getScoreValue(dev: DeveloperMetrics, key: SortKey): number {
  if (key === "dxi_score") return dev.dxi_score;
  return dev.dimension_scores[key] ?? 0;
}

/** Extract the raw value for a dimension from a developer's metrics */
function getRawValue(dev: DeveloperMetrics, key: keyof DimensionScores): number | null {
  switch (key) {
    case "review_speed":
      return dev.avg_review_time_hours;
    case "cycle_time":
      return dev.avg_cycle_time_hours;
    case "pr_size":
      return dev.prs_opened > 0
        ? (dev.lines_added + dev.lines_deleted) / dev.prs_opened
        : null;
    case "review_coverage":
      return dev.reviews_given;
    case "commit_frequency":
      return dev.commits;
  }
}

export function Leaderboard({ developers, onSelectDeveloper }: LeaderboardProps) {
  const [sortKey, setSortKey] = useState<SortKey>("dxi_score");
  const [expandedDeveloper, setExpandedDeveloper] = useState<string | null>(null);

  const handleSortChange = useCallback((key: SortKey) => {
    setSortKey(key);
    setExpandedDeveloper(null);
  }, []);

  const handleRowClick = useCallback((developerName: string) => {
    setExpandedDeveloper((prev) => (prev === developerName ? null : developerName));
  }, []);

  const handleRowKeyDown = useCallback(
    (e: React.KeyboardEvent, developerName: string) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        handleRowClick(developerName);
      }
    },
    [handleRowClick]
  );

  const sortedDevelopers = useMemo(() => {
    return [...developers].sort(
      (a, b) => getScoreValue(b, sortKey) - getScoreValue(a, sortKey)
    );
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
        <div className="flex gap-1 flex-wrap">
          {sortButtons.map(({ key, label }) => (
            <Button
              key={key}
              variant={sortKey === key ? "default" : "outline"}
              size="sm"
              onClick={() => handleSortChange(key)}
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
              <TableHead className="w-10">#</TableHead>
              <TableHead>Developer</TableHead>
              <TableHead className="text-center">
                <ColumnTooltip
                  label="DXI Score"
                  tooltip={LEADERBOARD_TOOLTIPS.dxi_score}
                />
              </TableHead>
              {dimensionColumns.map(({ key, label }) => (
                <TableHead key={key} className="text-center">
                  <ColumnTooltip
                    label={label}
                    tooltip={LEADERBOARD_TOOLTIPS[key]}
                  />
                </TableHead>
              ))}
            </TableRow>
          </TableHeader>
          <TableBody>
            <AnimatePresence mode="popLayout">
              {sortedDevelopers.flatMap((dev, index) => {
                const isExpanded = expandedDeveloper === dev.developer;
                const lines = dev.lines_added + dev.lines_deleted;

                const rows = [
                  <motion.tr
                    key={dev.developer}
                    layout
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 0.3 }}
                    className="border-b transition-colors hover:bg-muted/50 cursor-pointer"
                    onClick={() => handleRowClick(dev.developer)}
                    onKeyDown={(e) => handleRowKeyDown(e, dev.developer)}
                    tabIndex={0}
                    role="row"
                    aria-expanded={isExpanded}
                  >
                    <TableCell className="font-medium">{index + 1}</TableCell>
                    <TableCell>
                      <button
                        className="text-left font-medium hover:underline focus:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 rounded-sm"
                        onClick={(e) => {
                          e.stopPropagation();
                          onSelectDeveloper?.(dev.developer);
                        }}
                      >
                        {dev.developer}
                      </button>
                    </TableCell>
                    <TableCell className="text-center">
                      <Badge variant={getDxiBadgeVariant(dev.dxi_score)}>
                        {dev.dxi_score.toFixed(0)}
                      </Badge>
                    </TableCell>
                    {dimensionColumns.map(({ key }) => (
                      <TableCell
                        key={key}
                        className={`text-center tabular-nums ${getScoreColorClass(dev.dimension_scores[key])}`}
                      >
                        {DIMENSION_CONFIGS[key].formatRawValue(getRawValue(dev, key))}
                      </TableCell>
                    ))}
                  </motion.tr>,
                ];

                if (isExpanded) {
                  rows.push(
                    <tr key={`${dev.developer}-detail`} className="border-b bg-muted/30">
                      <td colSpan={8} className="px-6 py-3">
                        <div className="flex items-center gap-2 mb-2 text-xs text-muted-foreground">
                          <ChevronRight className="h-3 w-3" />
                          <span className="font-medium uppercase tracking-wide">Additional Metrics</span>
                        </div>
                        <div className="flex flex-wrap gap-6 text-sm text-muted-foreground">
                          <div>
                            <span className="font-medium text-foreground/80">PRs:</span>{" "}
                            {dev.prs_merged}/{dev.prs_opened} merged
                          </div>
                          <div>
                            <span className="font-medium text-foreground/80">Lines Changed:</span>{" "}
                            {lines.toLocaleString()}
                          </div>
                        </div>
                      </td>
                    </tr>
                  );
                }

                return rows;
              })}
            </AnimatePresence>
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
