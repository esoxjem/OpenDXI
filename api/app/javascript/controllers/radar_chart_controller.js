import { Controller } from "@hotwired/stimulus"

// Radar chart controller - renders Chart.js radar charts for DXI dimensions
// Only one custom Stimulus controller needed - Chartkick handles other chart types
export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    labels: Array,
    datasets: Array
  }

  connect() {
    this.renderChart()
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }

  async renderChart() {
    // Dynamic import to avoid loading Chart.js on every page
    const { Chart, registerables } = await import("chart.js")
    Chart.register(...registerables)

    this.chart = new Chart(this.canvasTarget, {
      type: "radar",
      data: {
        labels: this.labelsValue,
        datasets: this.datasetsValue
      },
      options: {
        responsive: true,
        maintainAspectRatio: true,
        scales: {
          r: {
            suggestedMin: 0,
            suggestedMax: 100,
            ticks: {
              stepSize: 25,
              backdropColor: "transparent"
            },
            grid: {
              color: "rgba(0,0,0,0.08)"
            },
            angleLines: {
              color: "rgba(0,0,0,0.08)"
            },
            pointLabels: {
              font: {
                size: 11
              }
            }
          }
        },
        plugins: {
          legend: {
            display: this.datasetsValue.length > 1,
            position: "bottom",
            labels: {
              boxWidth: 12,
              padding: 15
            }
          },
          tooltip: {
            callbacks: {
              label: (context) => `${context.dataset.label}: ${context.raw}`
            }
          }
        }
      }
    })
  }
}
