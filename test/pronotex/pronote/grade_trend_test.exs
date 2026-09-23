defmodule Pronotex.Pronote.GradeTrendTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.GradeTrend

  defp grade(overrides) do
    Map.merge(
      %{
        date: ~D[2026-09-01],
        subject: "Maths",
        score: "10",
        out_of: "20",
        coefficient: nil,
        bonus: false,
        optional: false
      },
      overrides
    )
  end

  test "normalizes scales, applies coefficients and weights subjects equally" do
    marks = [
      grade(%{date: ~D[2026-09-03], score: "20", coefficient: "3"}),
      grade(%{}),
      grade(%{date: ~D[2026-09-02], subject: "Français", score: "7,5", out_of: "10"})
    ]

    assert GradeTrend.points(marks) == [
             {~D[2026-09-01], 10.0},
             {~D[2026-09-02], 12.5},
             {~D[2026-09-03], 16.25}
           ]
  end

  test "same-day grades produce one point independent of input order" do
    marks = [grade(%{}), grade(%{score: "20"})]
    assert GradeTrend.points(marks) == [{~D[2026-09-01], 15.0}]
    assert GradeTrend.points(Enum.reverse(marks)) == GradeTrend.points(marks)
  end

  test "ignores unsupported marks and treats explicit zero statuses as zero" do
    marks =
      for fields <- [
            %{score: "Absent"},
            %{score: "18", bonus: true},
            %{score: "18", optional: true},
            %{out_of: "0"},
            %{coefficient: "0"},
            %{coefficient: "inconnu"},
            %{score: nil},
            %{score: "Absent (zéro)"},
            %{score: "Non rendu (zéro)"}
          ],
          do: grade(fields)

    assert GradeTrend.points(marks) == [{~D[2026-09-01], 0.0}]
    assert GradeTrend.points([]) == []
  end

  test "chart has no axes or tooltips and is omitted without two distinct dates" do
    import Phoenix.LiveViewTest
    alias PronotexWeb.GradeTrendChart
    refute render_component(&GradeTrendChart.chart/1, points: []) =~ "overall-trend"

    refute render_component(&GradeTrendChart.chart/1, points: [{~D[2026-09-01], 15.0}]) =~
             "overall-trend"

    html =
      render_component(&GradeTrendChart.chart/1,
        points: [{~D[2026-09-01], 10.0}, {~D[2026-09-03], 15.0}]
      )

    assert html =~ "Évolution estimée"
    assert html =~ "<path"
    refute html =~ "<text"
    refute html =~ "<title"
  end
end
