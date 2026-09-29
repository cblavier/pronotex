defmodule PronotexWeb.GradeTrendChartTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias PronotexWeb.GradeTrendChart

  test "student headroom is capped at twenty" do
    html = chart([{~D[2026-09-21], 12}, {~D[2026-09-28], 20}], [])
    assert_in_delta y(html, "trend-point-0"), 104.8, 0.01
    assert_in_delta y(html, "trend-point-1"), 12.0, 0.01
  end

  test "class headroom is also capped at twenty" do
    html =
      chart([{~D[2026-09-21], 16}, {~D[2026-09-28], 16}], [
        {~D[2026-09-21], 19},
        {~D[2026-09-28], 19}
      ])

    assert_in_delta y(html, "class-trend-point-0"), 31.33, 0.01
  end

  test "student and class lower margins are floored at zero" do
    html =
      chart([{~D[2026-09-21], 0}, {~D[2026-09-28], 0}], [{~D[2026-09-21], 8}, {~D[2026-09-28], 8}])

    assert y(html, "trend-point-0") == 128.0

    html =
      chart([{~D[2026-09-21], 8}, {~D[2026-09-28], 8}], [{~D[2026-09-21], 1}, {~D[2026-09-28], 1}])

    assert_in_delta y(html, "class-trend-point-0"), 116.4, 0.01
  end

  test "both curves use the highest historical class or student value" do
    html =
      chart(
        [{~D[2026-09-21], 10}, {~D[2026-09-28], 14}],
        [{~D[2026-09-21], 16}, {~D[2026-09-28], 14}]
      )

    assert_in_delta y(html, "class-trend-point-0"), 35.2, 0.01
    assert_in_delta y(html, "trend-point-1"), 58.4, 0.01
    assert y(html, "trend-point-1") == y(html, "class-trend-point-1")
  end

  test "empty and constant series render without division by zero" do
    refute chart([], []) =~ "overall-trend"
    assert y(chart([{~D[2026-09-21], 16.5}, {~D[2026-09-28], 16.5}], []), "trend-point-0") == 70.0

    assert y(chart([], [{~D[2026-09-21], 0}, {~D[2026-09-28], 0}]), "class-trend-point-0") ==
             128.0

    assert_in_delta y(chart([{~D[2026-09-21], 20}, {~D[2026-09-28], 20}], []), "trend-point-0"),
                    12.0,
                    0.01
  end

  test "each series needs at least two points" do
    single = [{~D[2026-09-28], 19}]
    multiple = [{~D[2026-09-21], 12}, {~D[2026-09-28], 14}]

    for {student, classroom} <- [{[], []}, {single, []}, {[], single}, {single, single}] do
      refute chart(student, classroom) =~ "overall-trend"
    end

    html = chart(single, multiple)
    refute html =~ ~s(id="trend-point-0")
    assert html =~ ~s(id="class-trend-point-0")

    html = chart(multiple, single)
    assert html =~ ~s(id="trend-point-0")
    refute html =~ "class-average-trend"
    assert html == chart(multiple, [])
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
