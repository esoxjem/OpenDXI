import { Controller } from "@hotwired/stimulus"

// Base controller for ApexCharts-based charts
// Provides common disconnect cleanup and shared options
export default class extends Controller {
  disconnect() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }

  get baseOptions() {
    return {
      chart: {
        fontFamily: "inherit",
        toolbar: { show: false },
        animations: { enabled: true, easing: "easeinout", speed: 800 }
      }
    }
  }
}
