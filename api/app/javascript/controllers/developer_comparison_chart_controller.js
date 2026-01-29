import { Controller } from "@hotwired/stimulus"

// Developer Comparison Chart - Radar chart comparing developer vs team
// Usage: <canvas data-controller="developer-comparison-chart"
//               data-developer-comparison-chart-dev-scores-value='{"review_speed": 75, ...}'
//               data-developer-comparison-chart-team-scores-value='{"review_speed": 65, ...}'></canvas>
export default class extends Controller {
  static values = {
    devScores: Object,
    teamScores: Object
  }

  connect() {
    this.retryTimeout = null
    this.retryCount = 0
    this.initChart()
  }

  disconnect() {
    if (this.retryTimeout) {
      clearTimeout(this.retryTimeout)
      this.retryTimeout = null
    }
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }

  initChart() {
    // Wait for Chart.js to be available
    if (typeof Chart === "undefined") {
      if (this.retryCount++ < 50) {
        this.retryTimeout = setTimeout(() => this.initChart(), 100)
      }
      return
    }
    this.retryTimeout = null

    const devScores = this.devScoresValue || {}
    const teamScores = this.teamScoresValue || {}

    // Normalize keys
    const normalizeScores = (scores) => {
      const normalized = { ...scores }
      if (normalized.review_turnaround !== undefined && normalized.review_speed === undefined) {
        normalized.review_speed = normalized.review_turnaround
      }
      return normalized
    }

    const normDevScores = normalizeScores(devScores)
    const normTeamScores = normalizeScores(teamScores)

    // Dimension labels and keys
    const dimensionKeys = ["review_speed", "cycle_time", "pr_size", "review_coverage", "commit_frequency"]
    const dimensionLabels = {
      review_speed: "Review Speed",
      cycle_time: "Cycle Time",
      pr_size: "PR Size",
      review_coverage: "Review Coverage",
      commit_frequency: "Commit Frequency"
    }

    const labels = dimensionKeys.map(key => dimensionLabels[key])
    const devData = dimensionKeys.map(key => normDevScores[key] || 0)
    const teamData = dimensionKeys.map(key => normTeamScores[key] || 0)

    this.chart = new Chart(this.element, {
      type: "radar",
      data: {
        labels: labels,
        datasets: [
          {
            label: "Team",
            data: teamData,
            backgroundColor: "rgba(156, 163, 175, 0.2)",
            borderColor: "rgb(156, 163, 175)",
            borderWidth: 2,
            pointBackgroundColor: "rgb(156, 163, 175)",
            pointBorderColor: "#fff",
            pointRadius: 3
          },
          {
            label: "Developer",
            data: devData,
            backgroundColor: "rgba(99, 102, 241, 0.2)",
            borderColor: "rgb(99, 102, 241)",
            borderWidth: 2,
            pointBackgroundColor: "rgb(99, 102, 241)",
            pointBorderColor: "#fff",
            pointRadius: 3
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            display: false
          }
        },
        scales: {
          r: {
            beginAtZero: true,
            max: 100,
            ticks: {
              stepSize: 20,
              backdropColor: "transparent",
              font: { size: 9 }
            },
            grid: {
              color: "rgba(0, 0, 0, 0.1)"
            },
            angleLines: {
              color: "rgba(0, 0, 0, 0.1)"
            },
            pointLabels: {
              font: { size: 10 }
            }
          }
        }
      }
    })
  }
}
