import ApexChartController from "controllers/apex_chart_controller"

// Developer Comparison Chart - Radar chart comparing developer vs team
// Usage: <div data-controller="developer-comparison-chart"
//             data-developer-comparison-chart-dev-scores-value='{"review_speed": 75, ...}'
//             data-developer-comparison-chart-team-scores-value='{"review_speed": 65, ...}'></div>
export default class extends ApexChartController {
  static values = {
    devScores: Object,
    teamScores: Object,
    developerName: { type: String, default: "Developer" }
  }

  connect() {
    this.initChart()
  }

  initChart() {
    // Wait for ApexCharts to be available (loaded via script tag)
    if (typeof ApexCharts === "undefined") {
      setTimeout(() => this.initChart(), 100)
      return
    }

    const devScores = this.devScoresValue || {}
    const teamScores = this.teamScoresValue || {}

    // Normalize keys - handle both review_turnaround and review_speed
    const normalizeScores = (scores) => {
      const normalized = { ...scores }
      if (normalized.review_turnaround !== undefined && normalized.review_speed === undefined) {
        normalized.review_speed = normalized.review_turnaround
      }
      return normalized
    }

    const normDevScores = normalizeScores(devScores)
    const normTeamScores = normalizeScores(teamScores)

    // Dimension keys and labels
    const dimensionKeys = ["review_speed", "cycle_time", "pr_size", "review_coverage", "commit_frequency"]
    const dimensionLabels = {
      review_speed: "Review Speed",
      cycle_time: "Cycle Time",
      pr_size: "PR Size",
      review_coverage: "Review Coverage",
      commit_frequency: "Commit Frequency"
    }

    const categories = dimensionKeys.map(key => dimensionLabels[key])
    const devData = dimensionKeys.map(key => normDevScores[key] || 0)
    const teamData = dimensionKeys.map(key => normTeamScores[key] || 0)

    const options = {
      ...this.baseOptions,
      series: [
        { name: this.developerNameValue, data: devData },
        { name: "Team Average", data: teamData }
      ],
      chart: {
        ...this.baseOptions.chart,
        type: "radar",
        height: "100%"
      },
      colors: ["#6366f1", "#9ca3af"],
      fill: { opacity: [0.1, 0.05] },
      stroke: { width: 2 },
      markers: { size: 4, strokeWidth: 2, strokeColors: "#fff" },
      xaxis: {
        categories: categories,
        labels: { style: { colors: "#71717a", fontSize: "11px" } }
      },
      yaxis: { min: 0, max: 100, tickAmount: 4, labels: { show: false } },
      legend: { position: "bottom", markers: { radius: 3 } },
      plotOptions: {
        radar: {
          polygons: {
            strokeColors: "rgba(0,0,0,0.06)",
            connectorColors: "rgba(0,0,0,0.06)"
          }
        }
      }
    }

    this.chart = new ApexCharts(this.element, options)
    this.chart.render()
  }
}
