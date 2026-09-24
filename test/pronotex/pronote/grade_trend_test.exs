defmodule Pronotex.Pronote.GradeTrendTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.GradeTrend

  defp snapshot(id, time, score, scale \\ "20"),
    do: %{id: id, observed_at: time, data: %{"overall" => score, "overall_out_of" => scale}}

  test "uses official values in observation order, including intraday changes" do
    first = ~U[2026-09-01 08:00:00Z]
    second = ~U[2026-09-01 12:00:00Z]

    assert GradeTrend.points([snapshot(2, second, "7,5", "10"), snapshot(1, first, "14,25")]) ==
             [{first, 14.25}, {second, 15.0}]
  end

  test "does not invent values and ignores unchanged averages" do
    first = ~U[2026-09-01 08:00:00Z]
    later = ~U[2026-09-02 08:00:00Z]
    assert GradeTrend.points([]) == []

    assert GradeTrend.points([snapshot(1, first, "15"), snapshot(2, later, "15")]) == [
             {first, 15.0}
           ]

    for {score, scale} <- [{nil, "20"}, {"Absent", "20"}, {"12", nil}, {"12", "0"}] do
      assert GradeTrend.points([snapshot(1, first, score, scale)]) == []
    end
  end

  test "chart displays one official point without an invented past" do
    import Phoenix.LiveViewTest
    alias PronotexWeb.GradeTrendChart
    refute render_component(&GradeTrendChart.chart/1, points: []) =~ "overall-trend"
    html = render_component(&GradeTrendChart.chart/1, points: [{~U[2026-09-01 08:00:00Z], 15.0}])
    assert html =~ "trend-point-0"
    assert html =~ "moyenne officielle 15,00"
    refute html =~ "estimée"

    html =
      render_component(&GradeTrendChart.chart/1,
        points: [{~U[2026-09-01 08:00:00Z], 10.0}, {~U[2026-09-01 12:00:00Z], 15.0}]
      )

    assert html =~ "M 12.0"
    assert html =~ "588.0"
  end

  test "class evolution is independent from the student's overall average" do
    first = ~U[2026-09-01 08:00:00Z]
    later = ~U[2026-09-02 08:00:00Z]

    snapshots = [
      put_in(snapshot(1, first, "15"), [:data, "class_overall"], "12,5"),
      put_in(snapshot(2, later, "15"), [:data, "class_overall"], "13")
    ]

    assert GradeTrend.points(snapshots) == [{first, 15.0}]
    assert GradeTrend.points(snapshots, :class_overall) == [{first, 12.5}, {later, 13.0}]
    assert GradeTrend.points([snapshot(3, later, "15")], :class_overall) == []
  end

  test "both curves share time and score scales and the class uses light grey" do
    import Phoenix.LiveViewTest
    alias PronotexWeb.GradeTrendChart
    first = ~U[2026-09-01 08:00:00Z]
    middle = ~U[2026-09-02 08:00:00Z]
    last = ~U[2026-09-03 08:00:00Z]

    html =
      render_component(&GradeTrendChart.chart/1,
        points: [{middle, 15.0}],
        class_points: [{first, 10.0}, {last, 15.0}]
      )

    document = Floki.parse_fragment!(html)
    assert Floki.attribute(document, ".class-average-trend", "stroke") == ["#d1d5db"]
    assert Floki.attribute(document, "svg > path", "d") == ["M 300.0 70.0"]

    assert Floki.attribute(document, ".class-average-trend path", "d") ==
             ["M 12.0 128.0 C 300.0 128.0, 300.0 70.0, 588.0 70.0"]

    html = render_component(&GradeTrendChart.chart/1, points: [], class_points: [{first, 12.0}])
    assert html =~ "class-average-trend"
    refute html =~ "<circle"
    document = Floki.parse_fragment!(html)

    assert Floki.attribute(document, "#class-trend-point-0", "aria-describedby") ==
             ["class-trend-tooltip-0"]

    assert Floki.find(document, "#class-trend-point-0.trend-point-class .trend-point-dot") != []
    assert Floki.text(Floki.find(document, "#class-trend-tooltip-0")) =~ "12,00 / 20"
  end
end
