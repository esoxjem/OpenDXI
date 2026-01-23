"use client";

import { useSearchParams, useRouter } from "next/navigation";
import { Suspense, useCallback, useMemo } from "react";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  useConfig,
  useSprints,
  useMetrics,
  useRefreshMetrics,
  useSprintHistory,
} from "@/hooks/useMetrics";
import { useAuth } from "@/hooks/useAuth";
import { SprintSelector } from "@/components/dashboard/SprintSelector";
import { KpiCard } from "@/components/dashboard/KpiCard";
import { ActivityChart } from "@/components/dashboard/ActivityChart";
import { DxiRadarChart } from "@/components/dashboard/DxiRadarChart";
import { Leaderboard } from "@/components/dashboard/Leaderboard";
import { DashboardSkeleton } from "@/components/dashboard/DashboardSkeleton";
import { DeveloperCard } from "@/components/dashboard/DeveloperCard";
import { DeveloperDetailView } from "@/components/dashboard/DeveloperDetailView";
import { DxiTrendChart } from "@/components/dashboard/DxiTrendChart";
import { UserMenu } from "@/components/layout/UserMenu";

function DashboardContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { isAuthenticated, isLoading: authLoading } = useAuth();

  // Gate: check auth before fetching data
  if (authLoading) return <DashboardSkeleton />;
  if (!isAuthenticated) {
    window.location.href = "/login";
    return null;
  }

  const sprintParam = searchParams.get("sprint");
  const viewParam = searchParams.get("view") || "team";
  const developerParam = searchParams.get("developer");

  const { data: config } = useConfig();
  const { data: sprints, isLoading: sprintsLoading } = useSprints();
  const refreshMutation = useRefreshMetrics();

  // Use URL param or default to first (current) sprint
  const selectedSprint = sprintParam || sprints?.[0]?.value;
  const [startDate, endDate] = selectedSprint?.split("|") || [];

  const {
    data: metrics,
    isLoading: metricsLoading,
    error,
  } = useMetrics(startDate, endDate);
  const { data: sprintHistory, isLoading: historyLoading } =
    useSprintHistory(6);

  // Calculate previous sprint metrics for trend indicators
  const previousSprintMetrics = useMemo(() => {
    if (!sprintHistory || sprintHistory.length < 2) return null;

    // Find the current sprint index in history
    const currentSprintIndex = sprintHistory.findIndex(
      (s) => s.start_date === startDate && s.end_date === endDate,
    );

    // If current sprint is in history and has a previous sprint
    if (currentSprintIndex > 0) {
      return sprintHistory[currentSprintIndex - 1];
    }

    // If current sprint is most recent (not in history yet or is latest)
    // Use second-to-last from history as "previous"
    if (
      currentSprintIndex === -1 ||
      currentSprintIndex === sprintHistory.length - 1
    ) {
      return sprintHistory[sprintHistory.length - 2] || null;
    }

    return null;
  }, [sprintHistory, startDate, endDate]);

  const updateUrlParams = useCallback(
    (updates: Record<string, string | null>) => {
      const params = new URLSearchParams(searchParams);
      for (const [key, value] of Object.entries(updates)) {
        if (value === null) {
          params.delete(key);
        } else {
          params.set(key, value);
        }
      }
      router.push(`?${params.toString()}`);
    },
    [router, searchParams],
  );

  const handleSprintChange = (value: string) => {
    updateUrlParams({ sprint: value });
  };

  const handleRefresh = () => {
    if (startDate && endDate) {
      refreshMutation.mutate({ start: startDate, end: endDate });
    }
  };

  const handleViewChange = (value: string) => {
    updateUrlParams({ view: value, developer: null });
  };

  const handleSelectDeveloper = (developerName: string) => {
    updateUrlParams({ view: "developers", developer: developerName });
  };

  const handleBackFromDeveloper = () => {
    updateUrlParams({ developer: null });
  };

  // Loading state
  if (sprintsLoading || (metricsLoading && !metrics)) {
    return <DashboardSkeleton />;
  }

  // Error state
  if (error) {
    return (
      <div className="flex flex-col items-center justify-center h-[60vh] text-center">
        <h2 className="text-xl font-semibold mb-2">Failed to load metrics</h2>
        <p className="text-muted-foreground mb-4">
          {error instanceof Error ? error.message : "An error occurred"}
        </p>
        <Button onClick={handleRefresh}>Retry</Button>
      </div>
    );
  }

  // Calculate KPI values
  const summary = metrics?.summary || {
    total_commits: 0,
    total_prs: 0,
    total_merged: 0,
    total_reviews: 0,
    avg_dxi_score: 0,
  };
  const developers = metrics?.developers || [];
  const daily = metrics?.daily || [];
  const teamScores = metrics?.team_dimension_scores;

  // Calculate average cycle time and review time
  const cycleTimes = developers
    .map((d) => d.avg_cycle_time_hours)
    .filter((v): v is number => v !== null);
  const avgCycle = cycleTimes.length
    ? cycleTimes.reduce((a, b) => a + b, 0) / cycleTimes.length
    : 0;

  const reviewTimes = developers
    .map((d) => d.avg_review_time_hours)
    .filter((v): v is number => v !== null);
  const avgReview = reviewTimes.length
    ? reviewTimes.reduce((a, b) => a + b, 0) / reviewTimes.length
    : 0;

  // Previous sprint values for trends
  const prevDxi = previousSprintMetrics?.avg_dxi_score;
  const prevCommits = previousSprintMetrics?.total_commits;
  // For cycle time and review time, we'd need to recalculate from history
  // For now, use dimension scores as proxy (higher score = better time)
  const prevCycleScore = previousSprintMetrics?.dimension_scores?.cycle_time;
  const currentCycleScore = teamScores?.cycle_time;
  const prevReviewScore = previousSprintMetrics?.dimension_scores?.review_speed;
  const currentReviewScore = teamScores?.review_speed;

  // Sparkline data
  const commitSparkline = daily.map((d) => d.commits);
  const prSparkline = daily.map((d) => d.prs_merged);

  // Find selected developer for detail view
  const selectedDeveloper = developerParam
    ? developers.find((d) => d.developer === developerParam)
    : null;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-bold">
            {config?.github_org || "OpenDXI"} DXI Dashboard
          </h1>
          <p className="text-muted-foreground">Developer Experience Index</p>
        </div>
        <div className="flex items-center gap-2">
          {sprints && (
            <SprintSelector
              sprints={sprints}
              value={selectedSprint}
              onValueChange={handleSprintChange}
            />
          )}
          <Button
            variant="outline"
            onClick={handleRefresh}
            disabled={refreshMutation.isPending}
          >
            {refreshMutation.isPending ? "Refreshing..." : "Refresh"}
          </Button>
          <UserMenu />
        </div>
      </div>

      {/* Tabs */}
      <Tabs value={viewParam} onValueChange={handleViewChange}>
        <TabsList>
          <TabsTrigger value="team">Team Overview</TabsTrigger>
          <TabsTrigger value="developers">Developers</TabsTrigger>
          <TabsTrigger value="history">History</TabsTrigger>
        </TabsList>

        {/* Team Overview Tab */}
        <TabsContent value="team" className="space-y-6">
          {/* KPI Cards */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <KpiCard
              title="DXI Score"
              value={summary.avg_dxi_score.toFixed(0)}
              sparklineData={developers.slice(0, 10).map((d) => d.dxi_score)}
              index={0}
              currentValue={summary.avg_dxi_score}
              previousValue={prevDxi}
            />
            <KpiCard
              title="Commits"
              value={summary.total_commits.toString()}
              sparklineData={commitSparkline}
              index={1}
              currentValue={summary.total_commits}
              previousValue={prevCommits}
            />
            <KpiCard
              title="PR Cycle Time"
              value={avgCycle > 0 ? `${avgCycle.toFixed(1)}h` : "--"}
              sparklineData={prSparkline}
              index={2}
              currentValue={currentCycleScore}
              previousValue={prevCycleScore}
              invertTrend={false} // Higher score is better
            />
            <KpiCard
              title="Review Time"
              value={avgReview > 0 ? `${avgReview.toFixed(1)}h` : "--"}
              index={3}
              currentValue={currentReviewScore}
              previousValue={prevReviewScore}
              invertTrend={false} // Higher score is better
            />
          </div>

          {/* Charts */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
            <div className="lg:col-span-2">
              <ActivityChart data={daily} sprintStart={startDate} sprintEnd={endDate} />
            </div>
            <DxiRadarChart teamDimensionScores={teamScores} />
          </div>

          {/* Leaderboard */}
          <Leaderboard
            developers={developers}
            onSelectDeveloper={handleSelectDeveloper}
          />
        </TabsContent>

        {/* Developers Tab */}
        <TabsContent value="developers">
          {selectedDeveloper && teamScores ? (
            <DeveloperDetailView
              developer={selectedDeveloper}
              teamScores={teamScores}
              onBack={handleBackFromDeveloper}
            />
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
              {developers.map((dev, index) => (
                <DeveloperCard
                  key={dev.developer}
                  developer={dev}
                  onClick={() => handleSelectDeveloper(dev.developer)}
                  index={index}
                />
              ))}
              {developers.length === 0 && (
                <div className="col-span-full text-center py-12 text-muted-foreground">
                  No developers found for this sprint
                </div>
              )}
            </div>
          )}
        </TabsContent>

        {/* History Tab */}
        <TabsContent value="history" className="space-y-6">
          {historyLoading ? (
            <div className="flex items-center justify-center h-[400px] text-muted-foreground">
              Loading historical data...
            </div>
          ) : (
            <>
              <DxiTrendChart data={sprintHistory || []} />
              {/* Summary stats for historical context */}
              {sprintHistory && sprintHistory.length > 0 && (
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                  <div className="rounded-lg border bg-card p-4">
                    <div className="text-sm font-medium text-muted-foreground">
                      Sprints Analyzed
                    </div>
                    <div className="text-2xl font-bold">
                      {sprintHistory.length}
                    </div>
                  </div>
                  <div className="rounded-lg border bg-card p-4">
                    <div className="text-sm font-medium text-muted-foreground">
                      Avg Developer Count
                    </div>
                    <div className="text-2xl font-bold">
                      {Math.round(
                        sprintHistory.reduce(
                          (sum, s) => sum + s.developer_count,
                          0,
                        ) / sprintHistory.length,
                      )}
                    </div>
                  </div>
                  <div className="rounded-lg border bg-card p-4">
                    <div className="text-sm font-medium text-muted-foreground">
                      Total PRs (All Sprints)
                    </div>
                    <div className="text-2xl font-bold">
                      {sprintHistory.reduce((sum, s) => sum + s.total_prs, 0)}
                    </div>
                  </div>
                </div>
              )}
            </>
          )}
        </TabsContent>
      </Tabs>
    </div>
  );
}

export default function Dashboard() {
  return (
    <main className="container mx-auto py-6 px-4">
      <Suspense fallback={<DashboardSkeleton />}>
        <DashboardContent />
      </Suspense>
    </main>
  );
}
