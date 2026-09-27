defmodule Pronotex.Pronote.WeekCycleTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.{Lesson, WeekCycle}

  test "uses the school calendar rather than ISO week parity" do
    calendar =
      WeekCycle.calendar(%{
        "PremierLundi" => %{"V" => "31/08/2026"},
        "DomainesFrequences" => [
          %{"V" => "[1..8]"},
          %{"V" => "[1,3..4,7]"},
          %{"V" => "[2,5..6,8]"}
        ]
      })

    assert calendar[~D[2026-09-14]] == "A"
    assert calendar[~D[2026-09-21]] == "A"
    assert calendar[~D[2026-09-28]] == "B"
    assert WeekCycle.counterpart(calendar, ~D[2026-09-21]) == {~D[2026-09-28], "B"}
    assert WeekCycle.calendar(%{}) == %{}
    assert WeekCycle.counterpart(calendar, ~D[2027-09-01]) == nil
  end

  test "respects explicit A/B labels supplied by the school" do
    calendar =
      WeekCycle.calendar(%{
        "PremierLundi" => %{"V" => "31/08/2026"},
        "DomainesFrequences" => [%{"V" => "[]"}, %{"V" => "[1]"}, %{"V" => "[2]"}],
        "LibellesFrequences" => ["Toutes", "Semaine B", "Semaine A"]
      })

    assert calendar[~D[2026-08-31]] == "B"
    assert calendar[~D[2026-09-07]] == "A"
  end

  test "shifts the other cycle onto the displayed week without duplicating common or canceled lessons" do
    current = lesson("Maths", ~D[2026-09-14])
    common = lesson("Maths", ~D[2026-09-21])
    other = lesson("Anglais", ~D[2026-09-21])
    canceled = %{lesson("Sport", ~D[2026-09-21]) | canceled: true}

    assert [^current, ghost] =
             WeekCycle.overlay(
               [current],
               [common, other, canceled],
               ~D[2026-09-14],
               ~D[2026-09-21],
               "B"
             )

    assert ghost.inactive_cycle == "B"
    assert ghost.subject == "Anglais"
    assert ghost.start == ~N[2026-09-14 09:00:00]
    assert ghost.end == ~N[2026-09-14 10:00:00]
  end

  defp lesson(subject, date) do
    %Lesson{
      id: subject,
      subject: subject,
      start: NaiveDateTime.new!(date, ~T[09:00:00]),
      end: NaiveDateTime.new!(date, ~T[10:00:00])
    }
  end
end
