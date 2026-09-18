defmodule Pronotex.Pronote.HomeworkTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.Homework

  test "homework uses its API color and keeps missing or invalid colors neutral" do
    raw = %{
      "N" => "task",
      "Matiere" => %{"V" => %{"L" => "Nouvelle matière"}},
      "PourLe" => %{"V" => "18/09/2026"}
    }

    assert Homework.parse(raw, "child").color == nil
    assert Homework.parse(Map.put(raw, "CouleurFond", "#D4534C"), "child").color == "#D4534C"

    for invalid <- ["", "red", "#D4534C;display:none", 123] do
      assert Homework.parse(Map.put(raw, "CouleurFond", invalid), "child").color == nil
    end
  end

  test "Saturday includes Monday, but not Tuesday" do
    assert Homework.urgent_until(~D[2026-09-19]) == ~D[2026-09-21]
  end

  test "other days include the following calendar day" do
    assert Homework.urgent_until(~D[2026-09-18]) == ~D[2026-09-19]
    assert Homework.urgent_until(~D[2026-09-20]) == ~D[2026-09-21]
    assert Homework.urgent_until(~D[2026-09-21]) == ~D[2026-09-22]
  end
end
