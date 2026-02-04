"use client";

import { useState, useMemo, useCallback } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  Trophy,
  Medal,
  ChevronDown,
  GitPullRequest,
  FileCode,
  Plus,
} from "lucide-react";
import { ColumnTooltip } from "./components/ColumnTooltip";
import {
  DIMENSION_CONFIGS,
  LEADERBOARD_TOOLTIPS,
  getScoreColorClass,
} from "./components/dimension-config";
import { getRawValueForDimension } from "./components";
import type {
  DeveloperMetrics,
  SortKey,
  DimensionScores,
} from "@/types/metrics";

interface LeaderboardProps {
  developers: DeveloperMetrics[];
  onSelectDeveloper?: (developerName: string) => void;
}

const sortButtons: { key: SortKey; label: string }[] = [
  { key: "dxi_score", label: "Overall" },
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

/** Total number of table columns: rank + developer + dxi + dimensions + chevron */
const TOTAL_COLUMNS = 3 + dimensionColumns.length + 1;

/** Returns a tailwind class string for the DXI score pill */
function getDxiScoreClasses(score: number): string {
  if (score >= 70)
    return "bg-emerald-50 text-emerald-700 ring-emerald-600/20 dark:bg-emerald-500/10 dark:text-emerald-400 dark:ring-emerald-500/20";
  if (score >= 50)
    return "bg-amber-50 text-amber-700 ring-amber-600/20 dark:bg-amber-500/10 dark:text-amber-400 dark:ring-amber-500/20";
  return "bg-rose-50 text-rose-700 ring-rose-600/20 dark:bg-rose-500/10 dark:text-rose-400 dark:ring-rose-500/20";
}

function getScoreValue(dev: DeveloperMetrics, key: SortKey): number {
  if (key === "dxi_score") return dev.dxi_score;
  return dev.dimension_scores[key];
}

function getSortLabel(key: SortKey): string {
  if (key === "dxi_score") return "overall DXI score";
  return DIMENSION_CONFIGS[key].label.toLowerCase();
}

/** Rank indicator for top 3 positions */
function RankCell({ rank }: { rank: number }) {
  if (rank === 1) {
    return (
      <span className="inline-flex items-center justify-center h-7 w-7 rounded-full bg-amber-100 dark:bg-amber-500/15">
        <Trophy className="h-3.5 w-3.5 text-amber-600 dark:text-amber-400" />
      </span>
    );
  }
  if (rank === 2) {
    return (
      <span className="inline-flex items-center justify-center h-7 w-7 rounded-full bg-slate-100 dark:bg-slate-500/15">
        <Medal className="h-3.5 w-3.5 text-slate-500 dark:text-slate-400" />
      </span>
    );
  }
  if (rank === 3) {
    return (
      <span className="inline-flex items-center justify-center h-7 w-7 rounded-full bg-orange-100 dark:bg-orange-500/15">
        <Medal className="h-3.5 w-3.5 text-orange-600 dark:text-orange-400" />
      </span>
    );
  }
  return (
    <span className="inline-flex items-center justify-center h-7 w-7 text-sm text-muted-foreground tabular-nums">
      {rank}
    </span>
  );
}

export function Leaderboard({
  developers,
  onSelectDeveloper,
}: LeaderboardProps) {
  const [sortKey, setSortKey] = useState<SortKey>("dxi_score");
  const [expandedDeveloper, setExpandedDeveloper] = useState<string | null>(
    null
  );

  const handleSortChange = useCallback((key: SortKey) => {
    setSortKey(key);
    setExpandedDeveloper(null);
  }, []);

  const toggleExpand = useCallback((developerName: string) => {
    setExpandedDeveloper((prev) =>
      prev === developerName ? null : developerName
    );
  }, []);

  const handleRowKeyDown = useCallback(
    (e: React.KeyboardEvent, developerName: string) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        onSelectDeveloper?.(developerName);
      }
    },
    [onSelectDeveloper]
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
          <CardTitle className="text-base font-semibold">
            Leaderboard
          </CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col items-center justify-center h-[200px] gap-2 text-muted-foreground">
          <Trophy className="h-8 w-8 text-muted-foreground/40" />
          <p className="text-sm">No sprint data yet</p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-4">
        <div className="space-y-1">
          <CardTitle className="text-base font-semibold">
            Leaderboard
          </CardTitle>
          <p className="text-xs text-muted-foreground">
            Ranked by {getSortLabel(sortKey)}
          </p>
        </div>
        <div className="flex items-center rounded-lg bg-muted p-0.5 gap-0.5">
          {sortButtons.map(({ key, label }) => (
            <button
              type="button"
              key={key}
              onClick={() => handleSortChange(key)}
              className={`px-2.5 py-1 text-xs font-medium rounded-md transition-all ${
                sortKey === key
                  ? "bg-background text-foreground shadow-sm"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              {label}
            </button>
          ))}
        </div>
      </CardHeader>
      <CardContent className="px-0">
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead className="w-14 pl-6">Rank</TableHead>
              <TableHead>Developer</TableHead>
              <TableHead className="text-center">
                <ColumnTooltip
                  label="DXI"
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
              <TableHead className="w-10" />
            </TableRow>
          </TableHeader>
          <TableBody>
            <AnimatePresence mode="popLayout">
              {sortedDevelopers.flatMap((dev, index) => {
                const isExpanded = expandedDeveloper === dev.developer;
                const rank = index + 1;
                const lines = dev.lines_added + dev.lines_deleted;

                const rows = [
                  <motion.tr
                    key={dev.developer}
                    layout="position"
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 0.25 }}
                    className={`border-b transition-colors cursor-pointer group ${
                      isExpanded
                        ? "bg-muted/40"
                        : "hover:bg-muted/50"
                    }`}
                    onClick={() => onSelectDeveloper?.(dev.developer)}
                    onKeyDown={(e) => handleRowKeyDown(e, dev.developer)}
                    tabIndex={0}
                    role="row"
                  >
                    <TableCell className="pl-6">
                      <RankCell rank={rank} />
                    </TableCell>
                    <TableCell>
                      <span className="font-medium text-foreground">
                        {dev.developer}
                      </span>
                    </TableCell>
                    <TableCell className="text-center">
                      <span
                        className={`inline-flex items-center justify-center rounded-md px-2.5 py-0.5 text-xs font-semibold ring-1 ring-inset tabular-nums ${getDxiScoreClasses(dev.dxi_score)}`}
                      >
                        {dev.dxi_score.toFixed(0)}
                      </span>
                    </TableCell>
                    {dimensionColumns.map(({ key }) => (
                      <TableCell
                        key={key}
                        className={`text-center text-sm tabular-nums ${getScoreColorClass(dev.dimension_scores[key])}`}
                      >
                        {DIMENSION_CONFIGS[key].formatRawValue(
                          getRawValueForDimension(key, dev)
                        )}
                      </TableCell>
                    ))}
                    <TableCell className="pr-4">
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          toggleExpand(dev.developer);
                        }}
                        className="p-1 rounded hover:bg-muted transition-colors"
                        aria-label={isExpanded ? "Collapse details" : "Expand details"}
                      >
                        <ChevronDown
                          className={`h-4 w-4 text-muted-foreground/40 transition-transform duration-200 ${
                            isExpanded ? "rotate-180" : ""
                          }`}
                        />
                      </button>
                    </TableCell>
                  </motion.tr>,
                ];

                if (isExpanded) {
                  rows.push(
                    <motion.tr
                      key={`${dev.developer}-detail`}
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      exit={{ opacity: 0 }}
                      transition={{ duration: 0.2 }}
                      className="border-b bg-muted/20"
                    >
                      <td colSpan={TOTAL_COLUMNS} className="px-6 py-4">
                        <div className="grid grid-cols-3 gap-4 max-w-md">
                          <div className="flex items-center gap-2.5 rounded-lg border bg-background px-3 py-2.5">
                            <GitPullRequest className="h-4 w-4 text-muted-foreground" />
                            <div>
                              <p className="text-xs text-muted-foreground">Pull requests</p>
                              <p className="text-sm font-medium tabular-nums">
                                {dev.prs_merged}
                                <span className="text-muted-foreground font-normal">/{dev.prs_opened} merged</span>
                              </p>
                            </div>
                          </div>
                          <div className="flex items-center gap-2.5 rounded-lg border bg-background px-3 py-2.5">
                            <FileCode className="h-4 w-4 text-muted-foreground" />
                            <div>
                              <p className="text-xs text-muted-foreground">Lines changed</p>
                              <p className="text-sm font-medium tabular-nums">
                                {lines.toLocaleString()}
                              </p>
                            </div>
                          </div>
                          <div className="flex items-center gap-2.5 rounded-lg border bg-background px-3 py-2.5">
                            <Plus className="h-4 w-4 text-muted-foreground" />
                            <div>
                              <p className="text-xs text-muted-foreground">Added / Deleted</p>
                              <p className="text-sm font-medium tabular-nums">
                                <span className="text-emerald-600 dark:text-emerald-400">+{dev.lines_added.toLocaleString()}</span>
                                {" / "}
                                <span className="text-rose-600 dark:text-rose-400">-{dev.lines_deleted.toLocaleString()}</span>
                              </p>
                            </div>
                          </div>
                        </div>
                      </td>
                    </motion.tr>
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
