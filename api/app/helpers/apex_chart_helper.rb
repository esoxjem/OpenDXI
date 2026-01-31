# Helper methods for rendering charts with ApexCharts gem
# Uses default ApexCharts styling for clean, consistent appearance
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
      chart: { toolbar: { show: false } }
    }
  end

  def area_chart_options(options)
    {
      height: options.fetch(:height, "250px"),
      stacked: false,
      legend: { position: :bottom },
      chart: { toolbar: { show: false } }
    }
  end
end
