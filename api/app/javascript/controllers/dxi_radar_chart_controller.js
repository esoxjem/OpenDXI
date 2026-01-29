import { Controller } from "@hotwired/stimulus"

// DXI Radar Chart controller using Chart.js
// Renders a radar chart showing the 5 DXI dimension scores
// Usage: <canvas data-controller="dxi-radar-chart"
//               data-dxi-radar-chart-scores-value='{"review_speed": 75, ...}'></canvas>
export default class extends Controller {
  static values = {
    scores: Object
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
      if (this.retryCount++ < 50) { // Max 5 seconds (50 retries * 100ms)
        this.retryTimeout = setTimeout(() => this.initChart(), 100)
      }
      return
    }
    this.retryTimeout = null

    const scores = this.scoresValue || {}

    // Normalize keys - handle both review_turnaround (from API) and review_speed
    if (scores.review_turnaround !== undefined && scores.review_speed === undefined) {
      scores.review_speed = scores.review_turnaround
    }

    // Map dimension keys to display labels (matching target screenshot order)
    const dimensionKeys = ["review_speed", "cycle_time", "pr_size", "review_coverage", "commit_frequency"]
    const dimensionLabels = {
      review_speed: "Review Speed",
      cycle_time: "Cycle Time",
      pr_size: "PR Size",
      review_coverage: "Review Coverage",
      commit_frequency: "Frequency"
    }

    const labels = dimensionKeys.map(key => dimensionLabels[key])
    const data = dimensionKeys.map(key => scores[key] || 0)

    this.chart = new Chart(this.element, {
      type: "radar",
      data: {
        labels: labels,
        datasets: [{
          label: "Team DXI",
          data: data,
          backgroundColor: "rgba(99, 102, 241, 0.2)",
          borderColor: "rgb(99, 102, 241)",
          borderWidth: 2,
          pointBackgroundColor: "rgb(99, 102, 241)",
          pointBorderColor: "#fff",
          pointHoverBackgroundColor: "#fff",
          pointHoverBorderColor: "rgb(99, 102, 241)"
        }]
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
              backdropColor: "transparent"
            },
            grid: {
              color: "rgba(0, 0, 0, 0.1)"
            },
            angleLines: {
              color: "rgba(0, 0, 0, 0.1)"
            },
            pointLabels: {
              font: {
                size: 11
              }
            }
          }
        }
      }
    })
  }
}
