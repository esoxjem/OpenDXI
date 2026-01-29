import ApexChartController from "controllers/apex_chart_controller"

// DXI Radar Chart controller using ApexCharts
// Renders a radar chart showing the 5 DXI dimension scores
// Usage: <div data-controller="dxi-radar-chart"
//             data-dxi-radar-chart-scores-value='{"review_speed": 75, ...}'></div>
export default class extends ApexChartController {
  static values = {
    scores: Object,
    color: { type: String, default: "#6366f1" }
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

    const scores = this.scoresValue || {}

    // Normalize keys - handle both review_turnaround (from API) and review_speed
    const normalizedScores = { ...scores }
    if (normalizedScores.review_turnaround !== undefined && normalizedScores.review_speed === undefined) {
      normalizedScores.review_speed = normalizedScores.review_turnaround
    }

    // Dimension keys and labels (matching target screenshot order)
    const dimensionKeys = ["review_speed", "cycle_time", "pr_size", "review_coverage", "commit_frequency"]
    const dimensionLabels = {
      review_speed: "Review Speed",
      cycle_time: "Cycle Time",
      pr_size: "PR Size",
      review_coverage: "Review Coverage",
      commit_frequency: "Frequency"
    }

    const categories = dimensionKeys.map(key => dimensionLabels[key])
    const data = dimensionKeys.map(key => normalizedScores[key] || 0)

    const options = {
      ...this.baseOptions,
      series: [{ name: "DXI Score", data: data }],
      chart: {
        ...this.baseOptions.chart,
        type: "radar",
        height: "100%"
      },
      colors: [this.colorValue],
      fill: { opacity: 0.1 },
      stroke: { width: 2 },
      markers: { size: 4, strokeWidth: 2, strokeColors: "#fff" },
      xaxis: {
        categories: categories,
        labels: { style: { colors: "#71717a", fontSize: "11px" } }
      },
      yaxis: { min: 0, max: 100, tickAmount: 4, labels: { show: false } },
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
