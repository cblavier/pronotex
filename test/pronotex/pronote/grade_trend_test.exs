defmodule Pronotex.Pronote.GradeTrendTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.GradeTrend

  defp snapshot(id, time, score, scale \\ "20"),
    do: %{id: id, observed_at: time, data: %{"overall" => score, "overall_out_of" => scale}}

  test "keeps only the latest official values per day in chronological order" do
    first = ~U[2026-09-01 08:00:00Z]
    second = ~U[2026-09-01 12:00:00Z]
    next_day = ~U[2026-09-02 08:00:00Z]

    assert GradeTrend.points([
             snapshot(3, next_day, "16"),
             snapshot(2, second, "7,5", "10"),
             snapshot(1, first, "14,25")
           ]) == [{second, 15.0}, {next_day, 16.0}]
  end

  test "daily replacement keeps the pair together and breaks timestamp ties by id" do
    first = ~U[2026-09-28 08:00:00Z]
    latest = ~U[2026-09-28 18:00:00Z]

    snapshots = [
      put_in(snapshot(3, latest, "19,7"), [:data, "class_overall"], "14,9"),
      put_in(snapshot(1, first, "18,5"), [:data, "class_overall"], "14,8"),
      put_in(snapshot(2, latest, "19"), [:data, "class_overall"], "14,9")
    ]

    assert GradeTrend.points(snapshots) == [{latest, 19.7}]
    assert GradeTrend.points(snapshots, :class_overall) == [{latest, 14.9}]
  end

  test "daily replacement happens before deduplicating unchanged pairs" do
    first = ~U[2026-09-27 08:00:00Z]
    morning = ~U[2026-09-28 08:00:00Z]
    evening = ~U[2026-09-28 18:00:00Z]

    assert GradeTrend.points([
             snapshot(1, first, "18"),
             snapshot(2, morning, "19"),
             snapshot(3, evening, "18")
           ]) == [{first, 18.0}]
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

  test "chart waits for two official points without an invented past" do
    import Phoenix.LiveViewTest
    alias PronotexWeb.GradeTrendChart
    refute render_component(&GradeTrendChart.chart/1, points: []) =~ "overall-trend"
    html = render_component(&GradeTrendChart.chart/1, points: [{~U[2026-09-01 08:00:00Z], 15.0}])
    refute html =~ "overall-trend"
    refute html =~ "estimée"

    html =
      render_component(&GradeTrendChart.chart/1,
        points: [{~U[2026-09-01 08:00:00Z], 10.0}, {~U[2026-09-01 12:00:00Z], 15.0}]
      )

    assert html =~ "M 12.0"
    assert html =~ "588.0"
  end

  test "either average changing retains both points and unchanged pairs are deduplicated" do
    first = ~U[2026-10-03 08:00:00Z]
    later = ~U[2026-10-05 08:00:00Z]
    last = ~U[2026-10-06 08:00:00Z]

    snapshots = [
      put_in(snapshot(1, first, "17,7"), [:data, "class_overall"], "14,30"),
      put_in(snapshot(2, later, "17,7"), [:data, "class_overall"], "14,90"),
      put_in(snapshot(3, last, "18"), [:data, "class_overall"], "14,90"),
      put_in(snapshot(4, DateTime.add(last, 86400), "18,0"), [:data, "class_overall"], "14,9")
    ]

    assert GradeTrend.points(snapshots) == [{first, 17.7}, {later, 17.7}, {last, 18.0}]

    assert GradeTrend.points(snapshots, :class_overall) ==
             [{first, 14.3}, {later, 14.9}, {last, 14.9}]

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
        points: [{middle, 15.0}, {last, 15.0}],
        class_points: [{first, 10.0}, {last, 15.0}]
      )

    document = Floki.parse_fragment!(html)
    assert Floki.attribute(document, ".class-average-trend", "stroke") == ["#d1d5db"]

    assert Floki.attribute(document, "svg > path", "d") == [
             "M 300.0 37.78 C 444.0 37.78, 444.0 37.78, 588.0 37.78"
           ]

    assert Floki.attribute(document, ".class-average-trend path", "d") ==
             ["M 12.0 102.22 C 300.0 102.22, 300.0 37.78, 588.0 37.78"]

    html =
      render_component(&GradeTrendChart.chart/1,
        points: [],
        class_points: [{first, 12.0}, {last, 13.0}]
      )

    assert html =~ "class-average-trend"
    refute html =~ "<circle"
    document = Floki.parse_fragment!(html)

    assert Floki.attribute(document, "#class-trend-point-0", "aria-describedby") ==
             ["class-trend-tooltip-0"]

    assert Floki.find(document, "#class-trend-point-0.trend-point-class .trend-point-dot") != []
    assert Floki.text(Floki.find(document, "#class-trend-tooltip-0")) =~ "12,00 / 20"
  end
end
