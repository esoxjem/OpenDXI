# Helper methods for rendering charts with ApexCharts gem
# Provides consistent, modern styling inspired by Linear/Vercel dashboards
module ApexChartHelper
  def modern_line_chart(data, options = {})
    line_chart(
      [{
        name: options.fetch(:name, "Value"),
        data: data
      }],
      **line_chart_options(options)
    )
  end

  def modern_area_chart(data, options = {})
    area_chart(
      data,
      **area_chart_options(options)
    )
  end

  private

  def line_chart_options(options)
    {
      height: options.fetch(:height, "300px"),
      colors: options.fetch(:colors, ["#6366f1"]),
      curve: :smooth,
      stroke_width: 2,
      markers: { size: 0, hover: { size: 5 } },
      grid: { border_color: "rgba(0, 0, 0, 0.05)" },
      xaxis: {
        labels: { style: { colors: "#71717a", fontSize: "11px" } }
      },
      yaxis: {
        min: options.fetch(:min, 0),
        max: options.fetch(:max, 100),
        labels: { style: { colors: "#71717a", fontSize: "11px" } }
      },
      chart: { toolbar: { show: false }, zoom: { enabled: false } },
      fill: {
        type: :gradient,
        gradient: { shadeIntensity: 1, opacityFrom: 0.15, opacityTo: 0, stops: [0, 90, 100] }
      },
      tooltip: { theme: "light" }
    }
  end

  def area_chart_options(options)
    {
      height: options.fetch(:height, "250px"),
      colors: options.fetch(:colors, ["#06b6d4", "#10b981", "#a855f7"]),
      curve: :smooth,
      stroke_width: 1.5,
      stacked: false,
      markers: { size: 0 },
      legend: { position: :bottom, horizontalAlign: :left },
      grid: { border_color: "rgba(0, 0, 0, 0.04)" },
      xaxis: {
        labels: { style: { colors: "#71717a", fontSize: "11px" } }
      },
      yaxis: {
        labels: { style: { colors: "#71717a", fontSize: "11px" } }
      },
      chart: { toolbar: { show: false } },
      fill: {
        type: :gradient,
        gradient: { opacityFrom: 0.2, opacityTo: 0 }
      },
      tooltip: { theme: "light" }
    }
  end
end
