defmodule Pronotex.Pronote.LessonTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.Lesson

  test "reads evaluation categories independently of the lesson status" do
    raw = %{
      "N" => "lesson",
      "DateDuCours" => %{"V" => "21/09/2026 08:10:00"},
      "DateDuCoursFin" => %{"V" => "21/09/2026 09:05:00"},
      "ListeContenus" => %{"V" => [%{"G" => 16, "L" => "Mathématiques"}]},
      "Statut" => "Cours modifié"
    }

    notebook = %{
      "estEval" => true,
      "originesCategorie" => %{
        "V" => [%{"G" => 7, "L" => "Évaluation de compétences", "libelleIcone" => "EVA"}]
      }
    }

    lesson = Lesson.parse(Map.put(raw, "cahierDeTextes", %{"V" => notebook}), %{}, "child")
    assert lesson.evaluation == "Évaluation de compétences"
    assert lesson.status == "Cours modifié"
    assert Lesson.parse(raw, %{}, "child").evaluation == nil

    assert Lesson.parse(
             Map.put(raw, "cahierDeTextes", %{"V" => %{"estEval" => true}}),
             %{},
             "child"
           ).evaluation == "Évaluation"

    assert Lesson.parse(
             Map.put(raw, "cahierDeTextes", %{"V" => Map.put(notebook, "estEval", false)}),
             %{},
             "child"
           ).evaluation == nil
  end

  test "uses the explicit end date and preserves multiple teachers and rooms" do
    raw = %{
      "N" => "lesson",
      "DateDuCours" => %{"V" => "17/09/26 09h00"},
      "DateDuCoursFin" => %{"V" => "17/09/2026 10:30:00"},
      "ListeContenus" => %{
        "V" => [
          %{"G" => 16, "L" => "SVT"},
          %{"G" => 3, "L" => "A"},
          %{"G" => 3, "L" => "B"},
          %{"G" => 17, "L" => "101"},
          %{"G" => 17, "L" => "102"}
        ]
      }
    }

    lesson = Lesson.parse(raw, %{}, "child")
    assert lesson.end == ~N[2026-09-17 10:30:00]
    assert lesson.start == ~N[2026-09-17 09:00:00]
    assert lesson.teachers == ["A", "B"]
    assert lesson.classrooms == ["101", "102"]
    refute lesson.canceled
    assert lesson.color == nil
  end

  test "reads the API color independently of the subject and ignores invalid colors" do
    raw = %{
      "N" => "lesson",
      "DateDuCours" => %{"V" => "17/09/26 09h00"},
      "DateDuCoursFin" => %{"V" => "17/09/26 10h00"},
      "ListeContenus" => %{"V" => [%{"G" => 16, "L" => "Une nouvelle matière"}]}
    }

    for color <- ["#0099DA", "#a49e6c", "#000000"] do
      assert Lesson.parse(Map.put(raw, "CouleurFond", color), %{}, "child").color == color
    end

    for color <- [nil, "", "red", "#12345G", "#0099DA; display:none", %{}, 123] do
      assert Lesson.parse(Map.put(raw, "CouleurFond", color), %{}, "child").color == nil
    end
  end
end
