defmodule Pronotex.AgendaTest do
  use ExUnit.Case, async: true
  alias Pronotex.Agenda
  alias Pronotex.Pronote.Lesson

  test "splits a gap using the lunch window decoded from Pronote" do
    general = %{
      "debutDemiPension" => 8,
      "finDemiPension" => 12,
      "ListeHeures" => %{"V" => [%{"G" => 8, "L" => "12h10"}, %{"G" => 12, "L" => "13h50"}]}
    }

    afternoon =
      Lesson.parse(
        %{
          "N" => "evaluation",
          "DateDuCours" => %{"V" => "18/09/2026 12h55"},
          "DateDuCoursFin" => %{"V" => "18/09/2026 14h45"},
          "ListeContenus" => %{"V" => []}
        },
        general,
        "child"
      )

    morning = lesson("history", "10:20", "11:15")
    [_, entry] = Agenda.entries([morning, afternoon])

    assert entry.pauses_before == [
             %{start: ~N[2026-09-18 11:15:00], end: ~N[2026-09-18 12:10:00], label: "Pause"},
             %{start: ~N[2026-09-18 12:10:00], end: ~N[2026-09-18 12:55:00], label: "Repas"}
           ]

    [_, entry] = Agenda.entries([morning, %{afternoon | start: ~N[2026-09-18 14:00:00]}])
    assert Enum.map(entry.pauses_before, & &1.label) == ["Pause", "Repas", "Pause"]
    assert List.last(entry.pauses_before).start == ~N[2026-09-18 13:50:00]

    [_, entry] =
      Agenda.entries([
        %{morning | end: ~N[2026-09-18 12:10:00]},
        afternoon
      ])

    assert [%{label: "Repas"}] = entry.pauses_before

    [_, entry] =
      Agenda.entries([
        %{morning | end: ~N[2026-09-18 13:50:00]},
        %{afternoon | start: ~N[2026-09-18 14:00:00]}
      ])

    assert [%{label: "Pause"}] = entry.pauses_before
  end

  test "a replacement hides all canceled lessons it overlaps, including partial overlaps" do
    lessons = [
      lesson("maths", "12:55", "13:50", true),
      lesson("evaluation", "12:55", "14:45"),
      lesson("french", "13:50", "14:45", true),
      lesson("partial", "14:30", "15:30", true),
      lesson("adjacent", "14:45", "15:40", true)
    ]

    assert Enum.map(Agenda.entries(lessons), & &1.id) == ["evaluation", "adjacent"]
  end

  test "identical canceled slots disappear but isolated cancellations remain" do
    lessons = [
      lesson("canceled", "16:00", "16:55", true),
      lesson("replacement", "16:00", "16:55"),
      lesson("isolated", "09:00", "10:00", true)
    ]

    assert Enum.map(Agenda.entries(lessons), & &1.id) == ["isolated", "replacement"]
  end

  test "gaps have exact times and adjacent lessons have no pause" do
    lessons = [
      lesson("last", "16:00", "16:55"),
      lesson("history", "10:20", "11:15"),
      lesson("evaluation", "12:55", "14:45"),
      lesson("english", "14:45", "15:40")
    ]

    [history, evaluation, english, last] = Agenda.entries(lessons)
    assert history.pauses_before == []

    assert evaluation.pauses_before == [
             %{start: history.end, end: evaluation.start, label: "Pause"}
           ]

    assert english.pauses_before == []
    assert last.pauses_before == [%{start: english.end, end: last.start, label: "Pause"}]
    assert Agenda.entries([]) == []
  end

  test "overlapping active lessons do not create gaps inside an ongoing lesson" do
    lessons = [
      lesson("long", "08:00", "11:00"),
      lesson("short", "09:00", "10:00"),
      lesson("next", "10:30", "12:00"),
      lesson("afternoon", "13:00", "14:00")
    ]

    [first, second, third, fourth] = Agenda.entries(lessons)
    assert Enum.all?([first, second, third], &(&1.pauses_before == []))
    assert fourth.pauses_before == [%{start: third.end, end: fourth.start, label: "Pause"}]
  end

  defp lesson(id, from, to, canceled \\ false) do
    %Lesson{
      id: id,
      subject: id,
      start: NaiveDateTime.from_iso8601!("2026-09-18T#{from}:00"),
      end: NaiveDateTime.from_iso8601!("2026-09-18T#{to}:00"),
      canceled: canceled
    }
  end
end
