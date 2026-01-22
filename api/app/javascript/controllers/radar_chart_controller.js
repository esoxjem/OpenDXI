import { Controller } from "@hotwired/stimulus"
import Chart from "Chart.js"

// Radar Chart Controller for DXI dimension visualization
// Uses Chart.js radar chart to display team and/or developer scores
export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    team: Object,
    developer: Object
  }

  connect() {
    this.initializeChart()
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }

  initializeChart() {
    const ctx = this.canvasTarget.getContext("2d")

    this.chart = new Chart(ctx, {
      type: "radar",
      data: {
        labels: ["Review Speed", "Cycle Time", "PR Size", "Review Coverage", "Commits"],
        datasets: this.buildDatasets()
      },
      options: {
        responsive: true,
        maintainAspectRatio: true,
        scales: {
          r: {
            min: 0,
            max: 100,
            ticks: {
              stepSize: 20,
              backdropColor: "transparent"
            },
            pointLabels: {
              font: { size: 11 }
            },
            grid: {
              color: "rgba(0, 0, 0, 0.1)"
            },
            angleLines: {
              color: "rgba(0, 0, 0, 0.1)"
            }
          }
        },
        plugins: {
          legend: {
            position: "bottom",
            labels: {
              usePointStyle: true,
              padding: 20
            }
          },
          tooltip: {
            callbacks: {
              label: function(context) {
                return `${context.dataset.label}: ${context.raw.toFixed(1)}`
              }
            }
          }
        },
        elements: {
          line: {
            borderWidth: 2
          },
          point: {
            radius: 3,
            hoverRadius: 5
          }
        }
      }
    })
  }

  buildDatasets() {
    const datasets = []

    // Team average dataset
    if (this.hasTeamValue && Object.keys(this.teamValue).length > 0) {
      datasets.push({
        label: "Team Average",
        data: this.extractScores(this.teamValue),
        borderColor: "rgb(59, 130, 246)",
        backgroundColor: "rgba(59, 130, 246, 0.2)",
        pointBackgroundColor: "rgb(59, 130, 246)"
      })
    }

    // Developer dataset (if provided)
    if (this.hasDeveloperValue && Object.keys(this.developerValue).length > 0) {
      datasets.push({
        label: "Developer",
        data: this.extractScores(this.developerValue),
        borderColor: "rgb(234, 88, 12)",
        backgroundColor: "rgba(234, 88, 12, 0.2)",
        pointBackgroundColor: "rgb(234, 88, 12)"
      })
    }

    return datasets
  }

  extractScores(scores) {
    // Map dimension keys to chart order
    // Labels: ["Review Speed", "Cycle Time", "PR Size", "Review Coverage", "Commits"]
    return [
      scores["review_turnaround"] || scores["review_speed"] || 0,
      scores["cycle_time"] || 0,
      scores["pr_size"] || 0,
      scores["review_coverage"] || 0,
      scores["commit_frequency"] || 0
    ]
  }

  // Update chart when values change
  teamValueChanged() {
    if (this.chart) {
      this.chart.data.datasets = this.buildDatasets()
      this.chart.update()
    }
  }

  developerValueChanged() {
    if (this.chart) {
      this.chart.data.datasets = this.buildDatasets()
      this.chart.update()
    }
  }
}
