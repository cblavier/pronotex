defmodule Pronotex.Pronote.GradesTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.Grades

  test "preserves zero, decimal commas and non-numeric marks" do
    assert Grades.value(%{"V" => "0"}) == "0"
    assert Grades.value(%{"V" => "14,5"}) == "14,5"
    assert Grades.value(%{"V" => "|1"}) == "Absent"
    assert Grades.value(%{"V" => "|3"}) == "Non noté"
    assert Grades.value(%{"V" => "|7"}) == "Non rendu (zéro)"
    assert Grades.value(nil) == nil
  end

  test "missing averages are not calculated from published subject averages" do
    report =
      Grades.parse(%{
        "listeServices" => %{"V" => [%{"N" => "m", "L" => "Maths", "moyEleve" => %{"V" => "18"}}]}
      })

    assert report.overall == nil
    assert report.class_overall == nil
    assert report.grades == []
    assert [%{score: "18", min: nil, max: nil}] = report.averages
  end

  test "period keys are stable and readable" do
    assert Grades.period_key("Semestre 1") == "semester1"
    assert Grades.period_key("Trimestre 2") == "trimester2"
    assert Grades.period_key("Hors période") == "hors-periode"
  end
end
