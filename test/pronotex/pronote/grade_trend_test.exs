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
end
