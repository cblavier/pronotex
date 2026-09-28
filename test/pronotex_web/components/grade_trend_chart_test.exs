defmodule PronotexWeb.GradeTrendChartTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias PronotexWeb.GradeTrendChart

  test "student maximum leaves two points of headroom, including above twenty" do
    html = chart([{~D[2026-09-21], 12}, {~D[2026-09-28], 20}], [])
    assert y(html, "trend-point-0") == 128.0
    assert_in_delta y(html, "trend-point-1"), 35.2, 0.01
  end

  test "both curves use the highest historical class or student value" do
    html =
      chart(
        [{~D[2026-09-21], 10}, {~D[2026-09-28], 14}],
        [{~D[2026-09-21], 16}, {~D[2026-09-28], 14}]
      )

    assert_in_delta y(html, "class-trend-point-0"), 41.0, 0.01
    assert_in_delta y(html, "trend-point-1"), 70.0, 0.01
    assert y(html, "trend-point-1") == y(html, "class-trend-point-1")
  end

  test "empty and constant series render without division by zero" do
    refute chart([], []) =~ "overall-trend"
    assert y(chart([{~D[2026-09-28], 16.5}], []), "trend-point-0") == 128.0
    assert y(chart([], [{~D[2026-09-28], 0}]), "class-trend-point-0") == 128.0
  end

  defp chart(points, class_points) do
    render_component(&GradeTrendChart.chart/1, points: points, class_points: class_points)
  end

  defp y(html, id) do
    [style] = html |> Floki.parse_document!() |> Floki.find("##{id}") |> Floki.attribute("style")
    [_, top] = Regex.run(~r/top: ([\d.]+)%/, style)
    {top, ""} = Float.parse(top)
    Float.round(top * 1.4, 2)
  end
end
