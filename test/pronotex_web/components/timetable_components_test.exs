defmodule PronotexWeb.TimetableComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias Pronotex.Pronote.Lesson
  alias PronotexWeb.TimetableComponents

  test "a canceled lesson and its replacement do not create a third column" do
    canceled = %{lesson("Ancien cours") | canceled: true}
    replacement = lesson("VIE DE CLASSE")
    other = Map.put(lesson("ANGLAIS LV1"), :inactive_cycle, "A")
    cards = cards([canceled, replacement, other])
    assert length(cards) == 2
    refute Floki.text(cards) =~ "Ancien cours"
    assert Floki.text(cards) =~ "VIE DE CLASSE"
    assert Floki.text(cards) =~ "ANGLAIS"
    assert Enum.all?(Floki.attribute(cards, "style"), &String.contains?(&1, "width: 50"))
  end

  test "genuine simultaneous subjects share their cycle's cell without losing their names" do
    other = Map.put(lesson("ANGLAIS LV1"), :inactive_cycle, "B")
    cards = cards([lesson("MATHEMATIQUES"), lesson("SCIENCES VIE & TERRE"), other])
    assert length(cards) == 2
    assert Floki.text(cards) =~ "MATHS / SVT"
    assert Floki.text(cards) =~ "ANGLAIS"
  end

  test "an isolated cancellation stays visible and consecutive lessons stay separate" do
    canceled = %{lesson("MATHEMATIQUES") | canceled: true}

    next = %{
      lesson("SCIENCES VIE & TERRE")
      | start: ~N[2026-09-21 10:00:00],
        end: ~N[2026-09-21 11:00:00]
    }

    cards = cards([canceled, next])
    assert length(cards) == 2
    assert Floki.text(cards) =~ "Annulé"
    assert Enum.all?(Floki.attribute(cards, "style"), &String.contains?(&1, "width: 100"))
  end

  test "only the current active lesson is highlighted, from start inclusive to end exclusive" do
    active = lesson("Maths")
    inactive = Map.put(lesson("Anglais"), :inactive_cycle, "A")
    canceled = %{active | canceled: true}

    assert cards([active, inactive]) |> Floki.find("[aria-current=time]") |> length() == 1
    assert cards([active], ~N[2026-09-21 09:00:00]) |> Floki.attribute("aria-current") == ["time"]
    assert cards([active], ~N[2026-09-21 08:59:59]) |> Floki.find("[aria-current=time]") == []
    assert cards([active], ~N[2026-09-21 10:00:00]) |> Floki.find("[aria-current=time]") == []
    assert cards([active], ~N[2026-09-22 09:30:00]) |> Floki.find("[aria-current=time]") == []
    assert cards([canceled]) |> Floki.find("[aria-current=time]") == []
  end

  test "the shared badge and timetable retain the evaluation label unless canceled" do
    exam = %{lesson("HISTOIRE-GEOGRAPHIE") | evaluation: "Devoir sur table"}
    assert Floki.text(cards([exam])) =~ "Devoir sur table"

    assert render_component(&PronotexWeb.CoreComponents.lesson_badges/1, lesson: exam) =~
             "Devoir sur table"

    refute Floki.text(cards([%{exam | canceled: true}])) =~ "Devoir sur table"
  end

  defp cards(lessons, now \\ ~N[2026-09-21 09:30:00]) do
    render_component(&TimetableComponents.week_timetable/1,
      lessons: lessons,
      monday: ~D[2026-09-21],
      today: ~D[2026-09-21],
      now: now,
      loading: false,
      cycle: "B"
    )
    |> Floki.parse_document!()
    |> Floki.find(".week-lesson")
  end

  defp lesson(subject) do
    %Lesson{
      id: subject,
      subject: subject,
      start: ~N[2026-09-21 09:00:00],
      end: ~N[2026-09-21 10:00:00]
    }
  end
end
