"use client";

import { motion } from "framer-motion";
import { ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { KpiCard } from "./KpiCard";
import { DxiRadarChart } from "./DxiRadarChart";
import { DeveloperTrendChart } from "./DeveloperTrendChart";
import { useDeveloperHistory } from "@/hooks/useMetrics";
import type { DeveloperMetrics, DimensionScores } from "@/types/metrics";

interface DeveloperDetailViewProps {
  developer: DeveloperMetrics;
  teamScores: DimensionScores;
  onBack: () => void;
}

function getDxiBadgeVariant(score: number): "default" | "secondary" | "destructive" {
  if (score >= 70) return "default";
  if (score >= 50) return "secondary";
  return "destructive";
}

function getInitials(name: string): string {
  return name
    .split(/[\s-_]+/)
    .map((part) => part[0]?.toUpperCase() || "")
    .slice(0, 2)
    .join("");
}

export function DeveloperDetailView({
  developer,
  teamScores,
  onBack,
}: DeveloperDetailViewProps) {
  const initials = getInitials(developer.developer);
  const linesChanged = developer.lines_added + developer.lines_deleted;
  const cycleTime = developer.avg_cycle_time_hours;
  const reviewTime = developer.avg_review_time_hours;

  // Fetch historical data for this developer
  const { data: historyData, isLoading: historyLoading } = useDeveloperHistory(
    developer.developer,
    6
  );

  return (
    <motion.div
      initial={{ opacity: 0, x: 20 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, x: -20 }}
      transition={{ duration: 0.3 }}
      className="space-y-6"
    >
      {/* Header */}
      <div className="flex items-center gap-4">
        <Button variant="ghost" size="icon" onClick={onBack}>
          <ArrowLeft className="h-4 w-4" />
        </Button>
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center text-lg font-semibold text-primary">
            {initials}
          </div>
          <div>
            <h2 className="text-xl font-bold">{developer.developer}</h2>
            <Badge variant={getDxiBadgeVariant(developer.dxi_score)}>
              DXI Score: {developer.dxi_score.toFixed(0)}
            </Badge>
          </div>
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <KpiCard
          title="Commits"
          value={developer.commits.toString()}
          index={0}
        />
        <KpiCard
          title="PRs Merged"
          value={`${developer.prs_merged}/${developer.prs_opened}`}
          index={1}
        />
        <KpiCard
          title="Reviews Given"
          value={developer.reviews_given.toString()}
          index={2}
        />
        <KpiCard
          title="Lines Changed"
          value={linesChanged.toLocaleString()}
          index={3}
        />
      </div>

      {/* Second row KPIs */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <KpiCard
          title="Avg Cycle Time"
          value={cycleTime ? `${cycleTime.toFixed(1)}h` : "--"}
          index={4}
        />
        <KpiCard
          title="Avg Review Time"
          value={reviewTime ? `${reviewTime.toFixed(1)}h` : "--"}
          index={5}
        />
      </div>

      {/* Radar Chart - Developer vs Team */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <DxiRadarChart
          teamDimensionScores={teamScores}
          developerScores={developer.dimension_scores}
        />

        {/* Dimension Breakdown */}
        <Card>
          <CardHeader>
            <CardTitle>Dimension Breakdown</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              <DimensionRow
                label="Review Speed"
                developerScore={developer.dimension_scores.review_speed}
                teamScore={teamScores.review_speed}
              />
              <DimensionRow
                label="Cycle Time"
                developerScore={developer.dimension_scores.cycle_time}
                teamScore={teamScores.cycle_time}
              />
              <DimensionRow
                label="PR Size"
                developerScore={developer.dimension_scores.pr_size}
                teamScore={teamScores.pr_size}
              />
              <DimensionRow
                label="Review Coverage"
                developerScore={developer.dimension_scores.review_coverage}
                teamScore={teamScores.review_coverage}
              />
              <DimensionRow
                label="Commit Frequency"
                developerScore={developer.dimension_scores.commit_frequency}
                teamScore={teamScores.commit_frequency}
              />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Trend Chart */}
      {historyLoading ? (
        <Card>
          <CardHeader>
            <CardTitle>DXI Trend</CardTitle>
          </CardHeader>
          <CardContent className="flex items-center justify-center h-[350px] text-muted-foreground">
            Loading historical data...
          </CardContent>
        </Card>
      ) : historyData ? (
        <DeveloperTrendChart
          developerData={historyData.sprints}
          teamData={historyData.team_history}
        />
      ) : null}
    </motion.div>
  );
}

function DimensionRow({
  label,
  developerScore,
  teamScore,
}: {
  label: string;
  developerScore: number;
  teamScore: number;
}) {
  const diff = developerScore - teamScore;
  const diffColor = diff >= 0 ? "text-green-600" : "text-red-600";
  const diffSign = diff >= 0 ? "+" : "";

  return (
    <div className="flex items-center justify-between">
      <span className="text-sm font-medium">{label}</span>
      <div className="flex items-center gap-4">
        <span className="text-sm text-muted-foreground">
          Team: {teamScore.toFixed(0)}
        </span>
        <span className="text-sm font-semibold w-12 text-right">
          {developerScore.toFixed(0)}
        </span>
        <span className={`text-xs w-12 text-right ${diffColor}`}>
          {diffSign}{diff.toFixed(0)}
        </span>
      </div>
    </div>
  );
}
